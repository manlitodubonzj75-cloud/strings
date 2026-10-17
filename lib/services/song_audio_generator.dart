import 'dart:math' as math;
import 'dart:typed_data';
import '../models/song_model.dart';
import '../music_theory.dart';

/// Second-order IIR Biquad filter for violin body formants & DC block.
class _ViolinBiquad {
  double b0 = 1.0, b1 = 0.0, b2 = 0.0, a1 = 0.0, a2 = 0.0;
  double x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0;

  void setPeaking(double sampleRate, double freq, double gainDb, double q) {
    final w0 = 2.0 * math.pi * (freq / sampleRate);
    final cosW0 = math.cos(w0);
    final sinW0 = math.sin(w0);
    final alpha = sinW0 / (2.0 * q);
    final a = math.pow(10.0, gainDb / 40.0).toDouble();

    final b0Unnorm = 1.0 + alpha * a;
    final b1Unnorm = -2.0 * cosW0;
    final b2Unnorm = 1.0 - alpha * a;
    final a0Unnorm = 1.0 + alpha / a;
    final a1Unnorm = -2.0 * cosW0;
    final a2Unnorm = 1.0 - alpha / a;

    b0 = b0Unnorm / a0Unnorm;
    b1 = b1Unnorm / a0Unnorm;
    b2 = b2Unnorm / a0Unnorm;
    a1 = a1Unnorm / a0Unnorm;
    a2 = a2Unnorm / a0Unnorm;
  }

  void setLowpass(double sampleRate, double cutoff, [double q = 0.7071]) {
    final w0 = 2.0 * math.pi * (cutoff / sampleRate);
    final cosW0 = math.cos(w0);
    final sinW0 = math.sin(w0);
    final alpha = sinW0 / (2.0 * q);

    final b0Unnorm = (1.0 - cosW0) / 2.0;
    final b1Unnorm = 1.0 - cosW0;
    final b2Unnorm = (1.0 - cosW0) / 2.0;
    final a0Unnorm = 1.0 + alpha;
    final a1Unnorm = -2.0 * cosW0;
    final a2Unnorm = 1.0 - alpha;

    b0 = b0Unnorm / a0Unnorm;
    b1 = b1Unnorm / a0Unnorm;
    b2 = b2Unnorm / a0Unnorm;
    a1 = a1Unnorm / a0Unnorm;
    a2 = a2Unnorm / a0Unnorm;
  }

  @pragma('vm:prefer-inline')
  double process(double inVal) {
    final out = b0 * inVal + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2;
    x2 = x1;
    x1 = inVal;
    y2 = y1;
    y1 = out;
    return out;
  }

  void reset() {
    x1 = 0.0;
    x2 = 0.0;
    y1 = 0.0;
    y2 = 0.0;
  }
}

/// Stradivarius / Guarneri wooden violin body acoustic filter bank.
/// Models the physical resonances of an Italian master violin:
/// - A0 (Air cavity / f-holes Helmholtz resonance): ~280 Hz
/// - T1 / C3 (Main wooden corpus resonance): ~470 Hz
/// - B1+ (Upper bout soundboard resonance): ~580 Hz
/// - Nasal / reed dip (Anti-resonance notch): ~1500 Hz
/// - Bridge Hill (Acoustic projection & singer's formant): ~2800 Hz
/// - Wood absorption (Warm high-frequency rolloff): ~6800 Hz
class _ViolinBodyFilterBank {
  final _ViolinBiquad _airCavity = _ViolinBiquad();
  final _ViolinBiquad _woodCorpus = _ViolinBiquad();
  final _ViolinBiquad _upperBout = _ViolinBiquad();
  final _ViolinBiquad _nasalNotch = _ViolinBiquad();
  final _ViolinBiquad _bridgeHill = _ViolinBiquad();
  final _ViolinBiquad _woodDamping = _ViolinBiquad();

  _ViolinBodyFilterBank(double sampleRate) {
    // Warm Italian Stradivari/Guarneri acoustic balance:
    // Boost wooden corpus depth, tame high-mid bridge hill, smooth warm lowpass rolloff
    _airCavity.setPeaking(sampleRate, 280.0, 3.2, 2.0);
    _woodCorpus.setPeaking(sampleRate, 470.0, 3.6, 2.0);
    _upperBout.setPeaking(sampleRate, 580.0, 2.0, 1.6);
    _nasalNotch.setPeaking(sampleRate, 1500.0, -2.4, 1.4);
    _bridgeHill.setPeaking(sampleRate, 2600.0, 1.2, 1.2);
    _woodDamping.setLowpass(sampleRate, 4800.0, 0.7071);
  }

  void reset() {
    _airCavity.reset();
    _woodCorpus.reset();
    _upperBout.reset();
    _nasalNotch.reset();
    _bridgeHill.reset();
    _woodDamping.reset();
  }

  @pragma('vm:prefer-inline')
  double process(double sample) {
    var s = _airCavity.process(sample);
    s = _woodCorpus.process(s);
    s = _upperBout.process(s);
    s = _nasalNotch.process(s);
    s = _bridgeHill.process(s);
    s = _woodDamping.process(s);

    // Warm wooden soundboard soft saturation:
    final x = s * 0.45;
    final sat = x / (1.0 + x.abs());
    return sat * 0.90;
  }
}

/// High-performance audio synthesizer that converts any Song or single pitch
/// into warm, authentic acoustic violin audio (Stradivarius / Guarneri acoustic model).
///
/// Features:
/// 1. Helmholtz bowed-string stick-slip excitation with up to 28 phase-dispersed partials.
/// 2. Multi-stage Stradivarius wooden body resonator filter bank (Air cavity, Wood corpus, Bridge hill).
/// 3. Continuous inter-note phase and decay continuity (zero clicks, zero artificial dropouts).
/// 4. Fast, authentic bow bite and quick onset (notes sound immediately and clearly).
/// 5. Subtle, natural musical vibrato (5.4 Hz pitch modulation with natural onset ramp).
/// 6. Seeking/scrubbing support (`startFromMs`) for instant seamless playback.
/// 7. Monophonic acoustic fidelity without unnatural cutting of note duration.
/// 8. Master peak normalization and soft-limiting for consistent, stable playback volume.
class SongAudioGenerator {
  static const int defaultSampleRate = 44100;

  static const int _kSinTableSize = 4096;
  static const int _kSinTableMask = _kSinTableSize - 1;
  static final Float64List _sinTable = () {
    final t = Float64List(_kSinTableSize);
    final step = (2.0 * math.pi) / _kSinTableSize;
    for (int i = 0; i < _kSinTableSize; i++) {
      t[i] = math.sin(i * step);
    }
    return t;
  }();

  /// Synthesizes a standalone, warm Stradivarius violin note PCM buffer.
  /// Directly streamable to hardware via [AudioEngine.playPcmBuffer].
  static Float32List generateSingleNotePcm(
    double frequencyHz,
    double durationSec, {
    int sampleRate = defaultSampleRate,
    bool addVibrato = true,
  }) {
    if (frequencyHz <= 20.0 || durationSec <= 0.0) {
      return Float32List(0);
    }
    final midi = MusicTheory.hzToMidi(frequencyHz).round();
    final note = SongNote(
      midiNote: midi,
      noteName: MusicTheory.midiToNoteName(midi),
      startTimeMs: 0,
      durationMs: (durationSec * 1000).round(),
      string: ViolinString.a,
      finger: ViolinFinger.open,
    );
    final song = Song(
      id: 'single_note',
      title: 'Reference Note',
      composer: 'Acoustic Synthesizer',
      tempoBpm: 100,
      notes: [note],
    );
    return generatePcm(
      song,
      sampleRate: sampleRate,
      addHarmonics: true,
      addVibrato: addVibrato,
      addMeasureDynamics: false,
    );
  }

  /// Synthesizes high-fidelity 44.1kHz mono Float32 audio samples from a Song.
  ///
  /// Directly streamable to hardware via [AudioEngine.playPcmBuffer].
  static Float32List generatePcm(
    Song song, {
    int sampleRate = defaultSampleRate,
    double speedMultiplier = 1.0,
    bool addHarmonics = true,
    bool addVibrato = true,
    bool addMeasureDynamics = true,
    int startFromMs = 0,
  }) {
    if (song.notes.isEmpty) {
      return Float32List(0);
    }

    final timeDilation = 1.0 / speedMultiplier.clamp(0.1, 4.0);
    final clampedFromMs = math.max(0, startFromMs);

    final lastNote = song.notes.last;
    if (clampedFromMs >= lastNote.endTimeMs) {
      return Float32List(0);
    }

    final totalRemainingMs = math.max(0, lastNote.endTimeMs - clampedFromMs);
    final totalDurationSec = (totalRemainingMs * timeDilation) / 1000.0 + 0.35; // 350ms natural acoustic decay
    final totalSamples = (totalDurationSec * sampleRate).ceil();

    final samples = Float32List(totalSamples);
    final twoPi = 2.0 * math.pi;

    // Stradivarius body formant resonator filter bank (lives across entire piece)
    final bodyFilter = _ViolinBodyFilterBank(sampleRate.toDouble());

    // Pre-calculate Helmholtz bowed-string harmonic series weights (1/n slope, subtle odd-harmonic preference)
    const maxPartials = 28;
    final partialWeights = Float64List(maxPartials);
    final partialPhases = Float64List(maxPartials);
    for (int n = 1; n <= maxPartials; n++) {
      if (addHarmonics) {
        final oddBonus = (n % 2 == 1) ? 1.06 : 0.94;
        // Warm 1/(n^1.18) rolloff eliminates shrill synthetic harmonics while preserving rich acoustic body
        final rollOff = 1.0 / math.pow(n, 1.18);
        partialWeights[n - 1] = rollOff * oddBonus;
        partialPhases[n - 1] = (n * n * 0.015) % twoPi; // subtle string dispersion
      } else {
        partialWeights[n - 1] = (n == 1) ? 1.0 : 0.0;
        partialPhases[n - 1] = 0.0;
      }
    }

    // Measure duration for subtle 4/4 phrasing dynamics
    final effectiveBpm = song.tempoBpm > 0 ? song.tempoBpm : 100;
    final quarterMs = (60000.0 / effectiveBpm).round();
    final measureMs = quarterMs * 4;

    // Rosin noise PRNG seed and band-limiting 1-pole state
    int rosinSeed = 0x982345;
    double rosinNoiseFiltered = 0.0;

    // Continuous string phase accumulator across consecutive notes (eliminates waveform jump clicks!)
    double phase = 0.0;

    for (int i = 0; i < song.notes.length; i++) {
      final note = song.notes[i];

      // Skip notes that already ended before startFromMs
      if (note.endTimeMs <= clampedFromMs) continue;

      final freqHz = MusicTheory.midiToHz(note.midiNote);

      // Relative note start and duration
      final effectiveStartMs = math.max(note.startTimeMs, clampedFromMs);
      final relStartMs = effectiveStartMs - clampedFromMs;
      final startSec = (relStartMs * timeDilation) / 1000.0;

      final effectiveEndMs = note.endTimeMs;
      var durSec = ((effectiveEndMs - effectiveStartMs) * timeDilation) / 1000.0;

      // Determine next note start time
      double? nextStartSec;
      bool isSlurredToNext = false;
      bool isSamePitchAsNext = false;

      if (i + 1 < song.notes.length) {
        final nextNote = song.notes[i + 1];
        if (nextNote.endTimeMs > clampedFromMs) {
          final nextEffStartMs = math.max(nextNote.startTimeMs, clampedFromMs);
          nextStartSec = ((nextEffStartMs - clampedFromMs) * timeDilation) / 1000.0;
          isSlurredToNext = note.isSlurred && nextNote.isSlurred && (note.slurGroupId == nextNote.slurGroupId);
          isSamePitchAsNext = (note.midiNote == nextNote.midiNote);
        }
      }

      // Enforce zero overlap: note ends before or at next note start
      if (nextStartSec != null && startSec + durSec > nextStartSec) {
        durSec = math.max(0.015, nextStartSec - startSec);
      }

      // Natural acoustic violin articulation:
      // In real violin playing, the bow does NOT stop into prolonged silence on every note!
      // - Consecutive melodic notes (different pitches): 0 gap (continuous bowing / legato)
      // - Repeated notes of same pitch: subtle 5-8ms bow reversal turnaround
      // - Slurred notes: 0 gap
      final double gapSec;
      final bool isContiguous = (nextStartSec != null && (nextStartSec - (startSec + durSec)).abs() <= 0.015);

      if (isSlurredToNext || (isContiguous && !isSamePitchAsNext)) {
        gapSec = 0.0;
      } else if (isSamePitchAsNext) {
        gapSec = math.min(0.008, durSec * 0.08);
      } else {
        gapSec = math.min(0.006, durSec * 0.06);
      }

      final activeSoundDurSec = math.max(0.015, durSec - gapSec);

      final startSample = (startSec * sampleRate).round();
      final numSoundSamples = (activeSoundDurSec * sampleRate).round();

      if (startSample >= totalSamples) break;
      final endSample = math.min(totalSamples, startSample + numSoundSamples);

      // Subtle musical measure dynamics: beat 1 accent (+4%), never crushing other notes
      double dynamicScale = 1.0;
      if (addMeasureDynamics && measureMs > 0) {
        final posInMeasure = (note.startTimeMs % measureMs) / measureMs;
        if (posInMeasure < 0.25) {
          dynamicScale = 1.04;
        } else if (posInMeasure >= 0.50 && posInMeasure < 0.75) {
          dynamicScale = 1.02;
        } else {
          dynamicScale = 0.98;
        }
      }

      // Fast, immediate bow attack so the note speaks promptly (8-12ms)
      final double attackTimeSec = math.min(0.012, activeSoundDurSec * 0.12);
      final double releaseTimeSec = math.min(0.012, activeSoundDurSec * 0.12);
      final attackSamples = math.max(1, (attackTimeSec * sampleRate).round());
      final releaseSamples = math.max(1, (releaseTimeSec * sampleRate).round());

      final nyquist = sampleRate * 0.46;
      final radToTable = _kSinTableSize / twoPi;

      for (int s = startSample; s < endSample; s++) {
        final relSample = s - startSample;
        final t = relSample / sampleRate.toDouble();

        // Amplitude envelope (smooth raised-cosine at boundaries)
        double env = 1.0;
        if (relSample < attackSamples) {
          final p = relSample / attackSamples;
          env = 0.5 * (1.0 - math.cos(math.pi * p)); // smooth 0->1
        } else if (relSample >= numSoundSamples - releaseSamples) {
          final p = (numSoundSamples - relSample) / releaseSamples;
          env = 0.5 * (1.0 - math.cos(math.pi * p)); // smooth 1->0
        }

        // Natural violin vibrato: 5.4 Hz modulation ramping in after 70ms (~14 cents depth)
        double currentFreq = freqHz;
        if (addVibrato && activeSoundDurSec >= 0.20) {
          final vibRamp = math.min(1.0, math.max(0.0, (t - 0.07) / 0.12));
          final vibMod = 0.0085 * vibRamp * math.sin(twoPi * 5.4 * t);
          currentFreq = freqHz * (1.0 + vibMod);
        }

        phase += twoPi * currentFreq / sampleRate;
        if (phase >= twoPi) phase -= twoPi;

        // Sum Helmholtz partials with band-limited cutoff (L1 cache-friendly wavetable lookup)
        double excitation = 0.0;
        for (int h = 0; h < maxPartials; h++) {
          final harmonicFreq = currentFreq * (h + 1);
          if (harmonicFreq >= nyquist) break;
          final ph = (h + 1) * phase + partialPhases[h];
          final tableIdx = (ph * radToTable).toInt() & _kSinTableMask;
          excitation += partialWeights[h] * _sinTable[tableIdx];
        }

        // Add band-limited horsehair rosin friction noise
        rosinSeed = (rosinSeed * 1664525 + 1013904223) & 0xFFFFFFFF;
        final rawNoise = (rosinSeed.toSigned(32) / 2147483648.0);
        rosinNoiseFiltered = rosinNoiseFiltered * 0.80 + rawNoise * 0.20;
        excitation += rosinNoiseFiltered * 0.0012;

        // Shape physical excitation before resonator body
        final shapedExcitation = excitation * env * dynamicScale;

        // Process through Stradivarius wooden body resonator
        final violinSample = bodyFilter.process(shapedExcitation);

        // Accumulate smoothly
        samples[s] += violinSample;
      }
    }

    // Master Peak Normalization and Soft Limiter:
    // Guarantees stable, consistent loudness across all pieces and prevents digital clipping
    double maxPeak = 0.0;
    for (int i = 0; i < totalSamples; i++) {
      final a = samples[i].abs();
      if (a > maxPeak) maxPeak = a;
    }

    if (maxPeak > 1e-5) {
      const targetPeak = 0.88; // -1.1 dBFS
      final normScale = targetPeak / maxPeak;
      for (int i = 0; i < totalSamples; i++) {
        final scaled = samples[i] * normScale;
        // Soft-knee limiter: absolutely transparent below 0.80, smoothly rounding peaks above 0.80
        if (scaled > 0.80) {
          final diff = (scaled - 0.80) / 0.15;
          samples[i] = 0.80 + 0.15 * (diff / (1.0 + diff.abs()));
        } else if (scaled < -0.80) {
          final diff = (-scaled - 0.80) / 0.15;
          samples[i] = -0.80 - 0.15 * (diff / (1.0 + diff.abs()));
        } else {
          samples[i] = scaled;
        }
      }
    }

    return samples;
  }

  /// Synthesizes canonical 16-bit mono RIFF WAV audio bytes from a Song.
  static Uint8List generateWav(
    Song song, {
    int sampleRate = defaultSampleRate,
    double speedMultiplier = 1.0,
    bool addHarmonics = true,
    bool addVibrato = true,
  }) {
    final floatSamples = generatePcm(
      song,
      sampleRate: sampleRate,
      speedMultiplier: speedMultiplier,
      addHarmonics: addHarmonics,
      addVibrato: addVibrato,
      addMeasureDynamics: true,
    );

    final numSamples = floatSamples.length;
    final dataSize = numSamples * 2;
    final buffer = Uint8List(44 + dataSize);
    final bdata = ByteData.view(buffer.buffer);

    // RIFF chunk descriptor
    buffer.setRange(0, 4, 'RIFF'.codeUnits);
    bdata.setUint32(4, 36 + dataSize, Endian.little);
    buffer.setRange(8, 12, 'WAVE'.codeUnits);

    // 'fmt ' sub-chunk
    buffer.setRange(12, 16, 'fmt '.codeUnits);
    bdata.setUint32(16, 16, Endian.little); // Subchunk1Size (16 for PCM)
    bdata.setUint16(20, 1, Endian.little); // AudioFormat (1 = PCM)
    bdata.setUint16(22, 1, Endian.little); // NumChannels (1 = Mono)
    bdata.setUint32(24, sampleRate, Endian.little);
    bdata.setUint32(28, sampleRate * 2, Endian.little); // ByteRate = SampleRate * NumChannels * BitsPerSample/8
    bdata.setUint16(32, 2, Endian.little); // BlockAlign = NumChannels * BitsPerSample/8
    bdata.setUint16(34, 16, Endian.little); // BitsPerSample = 16

    // 'data' sub-chunk
    buffer.setRange(36, 40, 'data'.codeUnits);
    bdata.setUint32(40, dataSize, Endian.little);

    // Convert Float32 samples (-1.0 .. 1.0) to 16-bit signed PCM
    for (int i = 0; i < numSamples; i++) {
      final sample = (floatSamples[i].clamp(-1.0, 1.0) * 32767.0).round();
      bdata.setInt16(44 + i * 2, sample, Endian.little);
    }

    return buffer;
  }
}
