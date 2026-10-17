import "dart:math" as math;
import "dart:typed_data";
import "package:flutter/services.dart";
import "../models/song_model.dart";
import "../music_theory.dart";
import "audio_decoder_helper.dart";
import "midi_parser.dart";
import "audio_time_stretcher.dart";
import "onnx_pitch_transcriber.dart";

class AudioTranscriberResult {
  final Song song;
  final int totalNotesDetected;
  final double durationSeconds;
  final int estimatedBpm;
  final String detectedKey;
  final String report;

  const AudioTranscriberResult({
    required this.song,
    required this.totalNotesDetected,
    required this.durationSeconds,
    required this.estimatedBpm,
    required this.detectedKey,
    required this.report,
  });
}

/// High-performance audio-to-score transcription service.
/// Decodes audio waveforms, tracks melodic pitch contours, detects note onsets (including 1/16 and 1/32 notes),
/// performs musical quantization, guarantees strict monophony (no note overlaps),
/// and outputs violin-ready Song models.
class AudioTranscriber {
  static const int targetSampleRate = 22050;
  static const int minViolinMidi = 48; // C3 (130.8 Hz) - allows vocal/viola lower octave input
  static const int maxViolinMidi = 100; // E7 (2637 Hz)

  static const _decoderChannel = MethodChannel("com.easyviolin.easy_violin/audio_decoder");

  /// Transcribes audio file bytes (WAV, AAC, M4A, MP3, or raw PCM) into a violin Song.
  ///
  /// [speedMultiplier]:
  /// - 1.0 = native tempo.
  /// - 0.5 = pre-generation was slowed down 2x, so note timestamps and durations
  ///   are accelerated back to normal tempo (multiplied by 0.5) and BPM is doubled.
  static Future<AudioTranscriberResult> transcribeAudioBytes(
    Uint8List audioBytes, {
    String title = "Распознанное аудио",
    double speedMultiplier = 1.0,
    bool enableTimeStretchSlowdown = true,
    void Function(double progress, String status)? onProgress,
  }) async {
    onProgress?.call(0.1, "Чтение и декодирование аудио...");
    final pcmSamples = await _decodeAudioToMonoFloat32(audioBytes);

    if (pcmSamples.isEmpty) {
      throw const FormatException("Не удалось извлечь аудиоданные из файла");
    }

    // Pre-normalize audio samples to standard digital headroom (-1.0 dBFS peak = ~0.89)
    // This ensures quiet recordings, live phone mics, and soft violin playing
    // have adequate signal level for neural and DSP pitch detection.
    double maxAmp = 0.0;
    for (int i = 0; i < pcmSamples.length; i++) {
      final a = pcmSamples[i].abs();
      if (a > maxAmp) maxAmp = a;
    }
    if (maxAmp > 1e-4) {
      final gain = (0.89 / maxAmp).clamp(1.0, 50.0);
      for (int i = 0; i < pcmSamples.length; i++) {
        pcmSamples[i] = (pcmSamples[i] * gain).clamp(-1.0, 1.0);
      }
    }

    final durationSec = (pcmSamples.length / targetSampleRate) * speedMultiplier;

    // Option A: WSOLA Time-Stretch 2x Slowdown
    // For virtuosic violin runs (Paganini, fast 1/16 and 1/32 passages),
    // time-stretching by 2x doubles the temporal analysis window resolution,
    // allowing the neural network to distinctly resolve rapid notes and octaves.
    Float32List processedSamples = pcmSamples;
    double effectiveSpeedMultiplier = speedMultiplier;

    if (enableTimeStretchSlowdown && speedMultiplier == 1.0) {
      onProgress?.call(0.18, "WSOLA-замедление 2x для сверхточного распознавания быстрых пассажей...");
      processedSamples = AudioTimeStretcher.timeStretch(pcmSamples, stretchFactor: 2.0);
      effectiveSpeedMultiplier = 0.5; // Restores original timing & tempo when decoding notes!
    }

    // 1. Neural AI transcription via Spotify Basic Pitch ONNX
    List<SongNote>? aiNotes;
    try {
      final onnxReady = await OnnxPitchTranscriber.initialize();
      if (onnxReady) {
        onProgress?.call(0.25, "Нейросетевая транскрипция (Spotify Basic Pitch ONNX)...");
        final detected = await OnnxPitchTranscriber.transcribe(
          audioSamples: processedSamples,
          speedMultiplier: effectiveSpeedMultiplier,
          noteThreshold: 0.28,
          onsetThreshold: 0.38,
          onProgress: onProgress,
        );
        if (detected.isNotEmpty) {
          aiNotes = detected;
        }
      }
    } catch (_) {
      // Fallback seamlessly to algorithmic MPM DSP
    }

    if (aiNotes != null && aiNotes.isNotEmpty) {
      final bpm = _estimateBpmFromSongNotes(aiNotes);
      final keySignature = _estimateKeySignature(aiNotes);
      final song = Song(
        id: "transcribed_${DateTime.now().millisecondsSinceEpoch}",
        title: title,
        composer: "Spotify Basic Pitch ONNX",
        tempoBpm: bpm,
        notes: aiNotes,
      );
      final methodLabel = (enableTimeStretchSlowdown && speedMultiplier == 1.0)
          ? "ONNX Basic Pitch + WSOLA 2x"
          : "ONNX Basic Pitch";
      final report = "Нейросетевая транскрипция ($methodLabel): Распознано ${aiNotes.length} нот, темп ~$bpm BPM ($keySignature), ${durationSec.toStringAsFixed(1)} сек.";
      onProgress?.call(1.0, "Готово!");
      return AudioTranscriberResult(
        song: song,
        totalNotesDetected: aiNotes.length,
        durationSeconds: durationSec,
        estimatedBpm: bpm,
        detectedKey: keySignature,
        report: report,
      );
    }

    // 2. Algorithmic fallback: MPM (McLeod Pitch Method) + onset detection
    onProgress?.call(0.3, "Анализ частот и поиск нот (MPM)...");
    final rawNotes = _extractNotesFromAudio(
      processedSamples,
      targetSampleRate,
      speedMultiplier: effectiveSpeedMultiplier,
      onProgress: (p) => onProgress?.call(0.3 + p * 0.45, "Анализ частот и поиск нот..."),
    );

    onProgress?.call(0.8, "Фильтрация и устранение нахлёстов...");
    final monophonicNotes = _enforceMonophony(rawNotes, speedMultiplier: effectiveSpeedMultiplier);

    if (monophonicNotes.isEmpty) {
      throw const FormatException("В аудиозаписи не удалось обнаружить скрипичные ноты");
    }

    onProgress?.call(0.9, "Определение темпа и тональности...");
    final bpm = _estimateBpm(monophonicNotes);
    final keySignature = _estimateKeySignature(monophonicNotes);

    final song = Song(
      id: "transcribed_${DateTime.now().millisecondsSinceEpoch}",
      title: title,
      composer: "Распознано EasyViolin",
      tempoBpm: bpm,
      notes: monophonicNotes,
    );

    final report = "Распознано ${monophonicNotes.length} нот, темп ~$bpm BPM ($keySignature), ${durationSec.toStringAsFixed(1)} сек.";
    onProgress?.call(1.0, "Готово!");

    return AudioTranscriberResult(
      song: song,
      totalNotesDetected: monophonicNotes.length,
      durationSeconds: durationSec,
      estimatedBpm: bpm,
      detectedKey: keySignature,
      report: report,
    );
  }

  /// Estimates musical tempo (BPM) from transcribed notes using inter-onset intervals (IOI).
  static int _estimateBpmFromSongNotes(List<SongNote> notes) {
    if (notes.length < 2) return 100;

    final intervals = <int>[];
    for (int i = 0; i < notes.length - 1; i++) {
      final ioi = notes[i + 1].startTimeMs - notes[i].startTimeMs;
      if (ioi >= 80 && ioi <= 2000) {
        intervals.add(ioi);
      }
    }

    if (intervals.isEmpty) return 100;

    intervals.sort();
    final medianIoi = intervals[intervals.length ~/ 2];

    double beatMs = medianIoi.toDouble();
    while (beatMs < 300) { beatMs *= 2.0; }
    while (beatMs > 900) { beatMs /= 2.0; }

    final bpm = (60000.0 / beatMs).round().clamp(50, 220);
    return bpm;
  }

  /// Internal decoder for audio files into mono Float32List at 22050 Hz.
  static Future<Float32List> _decodeAudioToMonoFloat32(Uint8List audioBytes) async {
    // 1. Check if it's already a canonical RIFF WAV file
    if (_isWavFormat(audioBytes)) {
      final pcm = _parseWavToMonoFloat32(audioBytes);
      if (pcm != null && pcm.isNotEmpty) return pcm;
    }

    // 2. Call native audio decoder via platform channel (AVAudioFile on macOS/iOS, MediaCodec on Android)
    try {
      dynamic result;
      try {
        result = await _decoderChannel.invokeMethod('decodeAudioFile', {
          'audioBytes': audioBytes,
          'targetSampleRate': targetSampleRate,
        });
      } catch (_) {
        result = await _decoderChannel.invokeMethod('decodeToWav', {
          'audioBytes': audioBytes,
          'targetSampleRate': targetSampleRate,
        });
      }

      if (result is Float32List && result.isNotEmpty) return result;
      if (result is Uint8List && result.isNotEmpty) {
        if (_isWavFormat(result)) {
          final pcm = _parseWavToMonoFloat32(result);
          if (pcm != null && pcm.isNotEmpty) return pcm;
        }
      }
      if (result is List<double> && result.isNotEmpty) {
        return Float32List.fromList(result);
      }
      if (result is List && result.isNotEmpty && result.first is num) {
        return Float32List.fromList(result.map((e) => (e as num).toDouble()).toList());
      }
    } catch (_) {
      // Fall through to CLI / system tools fallback
    }

    // 3. Desktop / CLI fallback: decode via afconvert (macOS built-in) or ffmpeg
    try {
      final wavBytes = await AudioDecoderCliHelper.convertToWav(audioBytes, targetSampleRate);
      if (wavBytes != null && wavBytes.isNotEmpty) {
        final pcm = _parseWavToMonoFloat32(wavBytes);
        if (pcm != null && pcm.isNotEmpty) return pcm;
      }
    } catch (_) {}

    // 4. If input is a recognized compressed audio stream (AAC, MP3, M4A, OGG, FLAC) and decoding failed,
    // do NOT treat it as raw linear PCM (which produces loud white noise and bogus notes)!
    if (_isCompressedFormat(audioBytes)) {
      throw const FormatException(
        'Не удалось декодировать сжатый аудиофайл (AAC/MP3/M4A). '
        'Убедитесь, что аудиофайл не повреждён.',
      );
    }

    // 5. Last resort fallback: treat as raw 16-bit PCM mono (only for raw uncompressed streams)
    return _parseRawPcm16(audioBytes);
  }

  /// Checks if bytes start with signatures of known compressed audio formats.
  static bool _isCompressedFormat(Uint8List bytes) {
    if (bytes.length < 4) return false;
    // AAC ADTS frame sync (0xFF 0xF0..0xFF)
    if (bytes[0] == 0xFF && (bytes[1] & 0xF0) == 0xF0) return true;
    // ID3 tag
    if (bytes[0] == 0x49 && bytes[1] == 0x44 && bytes[2] == 0x33) return true;
    // MP3 frame sync (11 bits = 0xFFE0 mask)
    if (bytes[0] == 0xFF && (bytes[1] & 0xE0) == 0xE0) return true;
    // M4A / MP4 / MOV ftyp box
    if (bytes.length >= 8 &&
        bytes[4] == 0x66 && bytes[5] == 0x74 && bytes[6] == 0x79 && bytes[7] == 0x70) {
      return true;
    }
    // FLAC magic
    if (bytes[0] == 0x66 && bytes[1] == 0x4C && bytes[2] == 0x61 && bytes[3] == 0x43) return true;
    // OGG container
    if (bytes[0] == 0x4F && bytes[1] == 0x67 && bytes[2] == 0x67 && bytes[3] == 0x53) return true;
    return false;
  }

  static bool _isWavFormat(Uint8List bytes) {
    if (bytes.length < 12) return false;
    final riff = String.fromCharCodes(bytes.sublist(0, 4));
    final wave = String.fromCharCodes(bytes.sublist(8, 12));
    return riff == 'RIFF' && wave == 'WAVE';
  }

  /// Parses 16-bit/24-bit/32-bit PCM/Float WAV data to mono Float32List at 22050Hz.
  static Float32List? _parseWavToMonoFloat32(Uint8List bytes) {
    try {
      final bdata = ByteData.view(bytes.buffer, bytes.offsetInBytes, bytes.lengthInBytes);
      int offset = 12; // Skip RIFF header

      int audioFormat = 1;
      int numChannels = 1;
      int sampleRate = 44100;
      int bitsPerSample = 16;
      int dataOffset = -1;
      int dataSize = 0;

      while (offset + 8 <= bytes.length) {
        final chunkId = String.fromCharCodes(bytes.sublist(offset, offset + 4));
        final chunkSize = bdata.getUint32(offset + 4, Endian.little);
        offset += 8;

        if (chunkId == 'fmt ') {
          audioFormat = bdata.getUint16(offset, Endian.little);
          numChannels = bdata.getUint16(offset + 2, Endian.little);
          sampleRate = bdata.getUint32(offset + 4, Endian.little);
          bitsPerSample = bdata.getUint16(offset + 14, Endian.little);
        } else if (chunkId == 'data') {
          dataOffset = offset;
          dataSize = chunkSize;
          break;
        }

        offset += chunkSize;
      }

      if (dataOffset == -1 || dataSize <= 0) return null;

      final bytesPerSample = bitsPerSample ~/ 8;
      if (bytesPerSample <= 0) return null;
      final totalFrames = dataSize ~/ (numChannels * bytesPerSample);
      final rawSamples = Float32List(totalFrames);

      for (int i = 0; i < totalFrames; i++) {
        double frameSum = 0.0;
        for (int ch = 0; ch < numChannels; ch++) {
          final sampleOffset = dataOffset + (i * numChannels + ch) * bytesPerSample;
          if (sampleOffset + bytesPerSample > bytes.length) break;

          double s = 0.0;
          if (audioFormat == 1) {
            // Integer PCM
            if (bitsPerSample == 16) {
              s = bdata.getInt16(sampleOffset, Endian.little) / 32768.0;
            } else if (bitsPerSample == 8) {
              s = (bytes[sampleOffset] - 128) / 128.0;
            } else if (bitsPerSample == 24) {
              final b0 = bytes[sampleOffset];
              final b1 = bytes[sampleOffset + 1];
              final b2 = bytes[sampleOffset + 2];
              int val = (b2 << 24) | (b1 << 16) | (b0 << 8);
              s = (val >> 8) / 8388608.0;
            }
          } else if (audioFormat == 3) {
            // Float PCM
            if (bitsPerSample == 32) {
              s = bdata.getFloat32(sampleOffset, Endian.little);
            }
          }
          frameSum += s;
        }
        rawSamples[i] = (frameSum / numChannels).clamp(-1.0, 1.0);
      }

      // Resample to targetSampleRate (22050 Hz) if needed
      if (sampleRate == targetSampleRate) {
        return rawSamples;
      } else {
        return _resampleLinear(rawSamples, sampleRate, targetSampleRate);
      }
    } catch (_) {
      return null;
    }
  }

  static Float32List _resampleLinear(Float32List source, int srcRate, int dstRate) {
    if (srcRate == dstRate || source.isEmpty) return source;

    final ratio = dstRate / srcRate.toDouble();
    final dstLength = (source.length * ratio).round();
    final result = Float32List(dstLength);

    for (int i = 0; i < dstLength; i++) {
      final srcIndex = i / ratio;
      final indexFloor = srcIndex.floor();
      final frac = srcIndex - indexFloor;

      if (indexFloor >= source.length - 1) {
        result[i] = source[source.length - 1];
      } else {
        final s0 = source[indexFloor];
        final s1 = source[indexFloor + 1];
        result[i] = s0 + frac * (s1 - s0);
      }
    }

    return result;
  }

  static Float32List _parseRawPcm16(Uint8List bytes) {
    final numSamples = bytes.length ~/ 2;
    final bdata = ByteData.view(bytes.buffer, bytes.offsetInBytes, bytes.lengthInBytes);
    final result = Float32List(numSamples);
    for (int i = 0; i < numSamples; i++) {
      result[i] = (bdata.getInt16(i * 2, Endian.little) / 32768.0).clamp(-1.0, 1.0);
    }
    return result;
  }

  /// Extracts pitch track and note candidates using McLeod Pitch Method (MPM)
  /// and RMS energy onset detection.
  static List<_DetectedNoteCandidate> _extractNotesFromAudio(
    Float32List samples,
    int sampleRate, {
    double speedMultiplier = 1.0,
    void Function(double progress)? onProgress,
  }) {
    final windowSize = 1024;
    final hopSize = 256;
    final totalFrames = math.max(0, (samples.length - windowSize) ~/ hopSize);

    if (totalFrames == 0) return [];

    final framePitches = <double>[];
    final frameConfidences = <double>[];
    final frameEnergies = <double>[];

    // Precompute Hann window to prevent spectral leakage & edge artifacts
    final hannWindow = Float32List(windowSize);
    for (int i = 0; i < windowSize; i++) {
      hannWindow[i] = 0.5 * (1.0 - math.cos(2.0 * math.pi * i / (windowSize - 1)));
    }

    final windowBuffer = Float32List(windowSize);
    final windowedBuffer = Float32List(windowSize);

    for (int f = 0; f < totalFrames; f++) {
      final startIdx = f * hopSize;
      windowBuffer.setRange(0, windowSize, samples, startIdx);

      // Compute RMS Energy & apply Hann window
      double sumSquares = 0.0;
      for (int i = 0; i < windowSize; i++) {
        final w = windowBuffer[i];
        sumSquares += w * w;
        windowedBuffer[i] = w * hannWindow[i];
      }
      final rms = math.sqrt(sumSquares / windowSize);
      frameEnergies.add(rms);

      // Pitch detection via McLeod Pitch Method (MPM) on windowed buffer
      if (rms < 0.008) {
        framePitches.add(0.0);
        frameConfidences.add(0.0);
      } else {
        final (pitchHz, confidence) = _detectPitchMpm(windowedBuffer, sampleRate);
        framePitches.add(pitchHz);
        frameConfidences.add(confidence);
      }

      if (f % 100 == 0 && onProgress != null) {
        onProgress(f / totalFrames);
      }
    }

    // 5-frame running median filter to eliminate single-frame outliers and vibrato jitter
    final smoothedPitches = List<double>.filled(totalFrames, 0.0);
    for (int f = 0; f < totalFrames; f++) {
      if (framePitches[f] <= 0) {
        smoothedPitches[f] = 0.0;
        continue;
      }
      final window = <double>[];
      for (int w = -2; w <= 2; w++) {
        final idx = f + w;
        if (idx >= 0 && idx < totalFrames && framePitches[idx] > 0) {
          window.add(framePitches[idx]);
        }
      }
      if (window.isEmpty) {
        smoothedPitches[f] = framePitches[f];
      } else {
        window.sort();
        smoothedPitches[f] = window[window.length ~/ 2];
      }
    }

    // Detect Onset Peaks using Energy Flux
    final onsetFrames = _detectOnsetFrames(frameEnergies, totalFrames);

    // Segment frames into notes with semitone hysteresis
    final noteCandidates = <_DetectedNoteCandidate>[];
    _DetectedNoteCandidate? currentCandidate;
    int hangoverFrames = 0;

    final frameMs = (hopSize / sampleRate) * 1000.0; // ~11.61ms per frame

    for (int f = 0; f < totalFrames; f++) {
      final pitchHz = smoothedPitches[f];
      final confidence = frameConfidences[f];
      final energy = frameEnergies[f];
      final isOnset = onsetFrames.contains(f);

      final rawMidi = (pitchHz > 0 && confidence >= 0.42) ? MusicTheory.hzToMidi(pitchHz) : 0.0;
      int midi = rawMidi > 0 ? rawMidi.round() : 0;

      // Hysteresis: retain current note if pitch is within 65 cents of active note (accommodates wide acoustic vibrato)
      if (currentCandidate != null && midi != 0) {
        final currentTargetHz = MusicTheory.midiToHz(currentCandidate.midiNote);
        final centsDiff = MusicTheory.calculateCents(pitchHz, currentTargetHz).abs();
        if (centsDiff <= 65.0) {
          midi = currentCandidate.midiNote;
        }
      }

      final isValidViolinNote = midi >= minViolinMidi && midi <= maxViolinMidi;
      final currentMs = (f * frameMs).round();

      if (isValidViolinNote && energy >= 0.010) {
        hangoverFrames = 0;
        if (currentCandidate == null) {
          currentCandidate = _DetectedNoteCandidate(
            midiNote: midi,
            startTimeMs: currentMs,
            endTimeMs: currentMs + frameMs.round(),
            confidence: confidence,
          );
        } else if (currentCandidate.midiNote == midi) {
          // Same pitch: split ONLY on authentic sharp onset attacks
          if (isOnset && (currentMs - currentCandidate.startTimeMs) > 120) {
            noteCandidates.add(currentCandidate);
            currentCandidate = _DetectedNoteCandidate(
              midiNote: midi,
              startTimeMs: currentMs,
              endTimeMs: currentMs + frameMs.round(),
              confidence: confidence,
            );
          } else {
            currentCandidate.endTimeMs = currentMs + frameMs.round();
            currentCandidate.confidence = math.max(currentCandidate.confidence, confidence);
          }
        } else {
          // Pitch changed: end current note and start new note
          noteCandidates.add(currentCandidate);
          currentCandidate = _DetectedNoteCandidate(
            midiNote: midi,
            startTimeMs: currentMs,
            endTimeMs: currentMs + frameMs.round(),
            confidence: confidence,
          );
        }
      } else {
        // Frame is below threshold or invalid: bridge micro silence up to 2 frames (~23ms)
        if (currentCandidate != null) {
          hangoverFrames++;
          if (hangoverFrames > 2) {
            noteCandidates.add(currentCandidate);
            currentCandidate = null;
            hangoverFrames = 0;
          }
        }
      }
    }

    if (currentCandidate != null) {
      noteCandidates.add(currentCandidate);
    }

    return noteCandidates;
  }

  /// McLeod Pitch Method (MPM) core pitch detection.
  static (double, double) _detectPitchMpm(Float32List buffer, int sampleRate) {
    final n = buffer.length;
    final maxTau = n ~/ 2;
    final nsdf = Float32List(maxTau);

    // Normalized Square Difference Function (NSDF)
    for (int tau = 0; tau < maxTau; tau++) {
      double acf = 0.0;
      double m = 0.0;
      for (int i = 0; i < n - tau; i++) {
        final x = buffer[i];
        final y = buffer[i + tau];
        acf += x * y;
        m += x * x + y * y;
      }
      nsdf[tau] = (m > 1e-6) ? (2.0 * acf / m) : 0.0;
    }

    // Find key maxima
    final keyMaxima = <int>[];
    double maxKeyMax = 0.0;
    for (int tau = 1; tau < maxTau - 1; tau++) {
      if (nsdf[tau] > nsdf[tau - 1] && nsdf[tau] >= nsdf[tau + 1]) {
        if (nsdf[tau] > 0.30) {
          keyMaxima.add(tau);
          if (nsdf[tau] > maxKeyMax) {
            maxKeyMax = nsdf[tau];
          }
        }
      }
    }

    if (keyMaxima.isEmpty || maxKeyMax < 0.38) {
      return (0.0, 0.0);
    }

    // Standard McLeod Pitch Method (MPM):
    // Choose the FIRST peak that exceeds (cutoff = 0.82 * maxKeyMax)
    // to strictly prevent octave errors (octave-down / subharmonic trapping)
    final cutoff = maxKeyMax * 0.82;
    int bestTau = keyMaxima.first;
    for (final tau in keyMaxima) {
      if (nsdf[tau] >= cutoff) {
        bestTau = tau;
        break;
      }
    }

    // Parabolic interpolation around bestTau
    double refinedTau = bestTau.toDouble();
    if (bestTau > 0 && bestTau < maxTau - 1) {
      final y0 = nsdf[bestTau - 1];
      final y1 = nsdf[bestTau];
      final y2 = nsdf[bestTau + 1];
      final denom = (2 * (2 * y1 - y0 - y2));
      if (denom.abs() > 1e-6) {
        final delta = (y2 - y0) / denom;
        refinedTau = bestTau + delta;
      }
    }

    if (refinedTau <= 0) return (0.0, 0.0);

    final pitchHz = sampleRate / refinedTau;
    final confidence = nsdf[bestTau].clamp(0.0, 1.0);

    return (pitchHz, confidence);
  }

  /// Detects rapid volume/energy attack onsets across audio frames.
  static Set<int> _detectOnsetFrames(List<double> energies, int totalFrames) {
    final onsetFrames = <int>{};
    if (totalFrames < 3) return onsetFrames;

    for (int i = 1; i < totalFrames - 1; i++) {
      final prev = energies[i - 1];
      final cur = energies[i];
      final next = energies[i + 1];

      // Energy rise threshold: requires steep absolute rise AND significant relative jump (>50%)
      // to eliminate false onsets from vibrato modulation while catching genuine bow strikes.
      final delta = cur - prev;
      final relRise = (prev > 1e-4) ? (cur / prev) : 10.0;
      if (delta > 0.045 && cur > next && cur > 0.05 && relRise > 1.50) {
        onsetFrames.add(i);
      }
    }

    return onsetFrames;
  }

  /// Strictly enforces monophony, filters spurious micro-glitches (< 20ms),
  /// scales note timestamps/durations according to [speedMultiplier], and maps to violin fingering.
  static List<SongNote> _enforceMonophony(
    List<_DetectedNoteCandidate> candidates, {
    double speedMultiplier = 1.0,
  }) {
    // 1. Filter out notes shorter than 20ms (acoustic glissando / bow transit noise)
    final filtered = candidates.where((n) => (n.endTimeMs - n.startTimeMs) >= 20).toList();
    if (filtered.isEmpty) return [];

    // 2. Merge contiguous notes of identical pitch separated by <= 25ms micro-gaps
    final merged = <_DetectedNoteCandidate>[];
    for (final note in filtered) {
      if (merged.isEmpty) {
        merged.add(note);
      } else {
        final prev = merged.last;
        final gapMs = note.startTimeMs - prev.endTimeMs;
        if (gapMs <= 25 && prev.midiNote == note.midiNote) {
          prev.endTimeMs = note.endTimeMs;
          prev.confidence = math.max(prev.confidence, note.confidence);
        } else {
          merged.add(note);
        }
      }
    }

    // 3. Strictly enforce non-overlapping time intervals and scale back to original speed
    final resultNotes = <SongNote>[];
    int lastEndMs = 0;

    for (int i = 0; i < merged.length; i++) {
      final cur = merged[i];

      var startMs = (cur.startTimeMs * speedMultiplier).round();
      var durationMs = ((cur.endTimeMs - cur.startTimeMs) * speedMultiplier).round();

      if (startMs < lastEndMs) {
        startMs = lastEndMs;
      }

      // Note cannot extend past start of the next note
      if (i + 1 < merged.length) {
        final nextStartMs = (merged[i + 1].startTimeMs * speedMultiplier).round();
        if (nextStartMs > startMs) {
          if (startMs + durationMs > nextStartMs) {
            durationMs = nextStartMs - startMs;
          }
        }
      }

      // Minimum audible note duration: 15ms (1/32 note at high tempo)
      durationMs = math.max(15, durationMs);
      lastEndMs = startMs + durationMs;

      int finalMidi = cur.midiNote;
      // If note was below violin's open G (MIDI 55), fold up by octaves into violin playable range
      while (finalMidi < 55) {
        finalMidi += 12;
      }

      final (vString, finger) = MidiParser.mapMidiToViolin(finalMidi);
      final noteName = MusicTheory.midiToNoteName(finalMidi);

      resultNotes.add(SongNote(
        midiNote: finalMidi,
        startTimeMs: startMs,
        durationMs: durationMs,
        noteName: noteName,
        string: vString,
        finger: finger,
      ));
    }

    return resultNotes;
  }

  /// Estimates BPM by analyzing inter-onset intervals (IOI) of detected notes.
  static int _estimateBpm(List<SongNote> notes) {
    if (notes.length < 2) return 100;

    final intervals = <int>[];
    for (int i = 0; i < notes.length - 1; i++) {
      final ioi = notes[i + 1].startTimeMs - notes[i].startTimeMs;
      if (ioi >= 100 && ioi <= 2000) {
        intervals.add(ioi);
      }
    }

    if (intervals.isEmpty) return 100;

    intervals.sort();
    final medianIoi = intervals[intervals.length ~/ 2];

    double beatMs = medianIoi.toDouble();
    while (beatMs < 300) { beatMs *= 2.0; }
    while (beatMs > 900) { beatMs /= 2.0; }

    final bpm = (60000.0 / beatMs).round().clamp(50, 220);
    return bpm;
  }

  /// Estimates likely musical key signature from pitch class distribution.
  static String _estimateKeySignature(List<SongNote> notes) {
    if (notes.isEmpty) return "A Major";

    final pitchCounts = <int, int>{};
    for (final n in notes) {
      final pc = n.midiNote % 12;
      pitchCounts[pc] = (pitchCounts[pc] ?? 0) + 1;
    }

    int bestRoot = 9; // A
    bool bestIsMajor = true;
    double bestScore = -1.0;

    // Krumhansl-Schmuckler Key Profiles
    const majorProfile = [6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88];
    const minorProfile = [6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17];

    for (int root = 0; root < 12; root++) {
      double majScore = 0.0;
      double minScore = 0.0;

      for (int i = 0; i < 12; i++) {
        final pc = (root + i) % 12;
        final count = (pitchCounts[pc] ?? 0).toDouble();
        majScore += count * majorProfile[i];
        minScore += count * minorProfile[i];
      }

      if (majScore > bestScore) {
        bestScore = majScore;
        bestRoot = root;
        bestIsMajor = true;
      }
      if (minScore > bestScore) {
        bestScore = minScore;
        bestRoot = root;
        bestIsMajor = false;
      }
    }

    final rootNames = ["C", "C#", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B"];
    return "${rootNames[bestRoot]} ${bestIsMajor ? 'Major' : 'Minor'}";
  }
}

class _DetectedNoteCandidate {
  final int midiNote;
  final int startTimeMs;
  int endTimeMs;
  double confidence;

  _DetectedNoteCandidate({
    required this.midiNote,
    required this.startTimeMs,
    required this.endTimeMs,
    required this.confidence,
  });
}
