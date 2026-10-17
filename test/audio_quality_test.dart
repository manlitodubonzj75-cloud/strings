// ignore_for_file: avoid_print
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:easy_violin/models/song_model.dart';
import 'package:easy_violin/music_theory.dart';
import 'package:easy_violin/services/ddsp_violin_synthesizer.dart';
import 'package:easy_violin/services/song_audio_generator.dart';

void _saveWav(String path, Float32List floatSamples, int sampleRate) {
  final numSamples = floatSamples.length;
  final dataSize = numSamples * 2;
  final buffer = Uint8List(44 + dataSize);
  final bdata = ByteData.view(buffer.buffer);

  buffer.setRange(0, 4, 'RIFF'.codeUnits);
  bdata.setUint32(4, 36 + dataSize, Endian.little);
  buffer.setRange(8, 12, 'WAVE'.codeUnits);
  buffer.setRange(12, 16, 'fmt '.codeUnits);
  bdata.setUint32(16, 16, Endian.little);
  bdata.setUint16(20, 1, Endian.little);
  bdata.setUint16(22, 1, Endian.little);
  bdata.setUint32(24, sampleRate, Endian.little);
  bdata.setUint32(28, sampleRate * 2, Endian.little);
  bdata.setUint16(32, 2, Endian.little);
  bdata.setUint16(34, 16, Endian.little);
  buffer.setRange(36, 40, 'data'.codeUnits);
  bdata.setUint32(40, dataSize, Endian.little);

  for (int i = 0; i < numSamples; i++) {
    final sample = (floatSamples[i].clamp(-1.0, 1.0) * 32767.0).round();
    bdata.setInt16(44 + i * 2, sample, Endian.little);
  }
  File(path).writeAsBytesSync(buffer);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Verify DDSP and SongAudioGenerator produce rich, consistent, crackle-free audio', () async {
    final notes = <SongNote>[
      SongNote(
        midiNote: 69, // A4
        startTimeMs: 0,
        durationMs: 350,
        noteName: 'A4',
        string: ViolinString.a,
        finger: ViolinFinger.open,
      ),
      SongNote(
        midiNote: 71, // B4
        startTimeMs: 380,
        durationMs: 180,
        noteName: 'B4',
        string: ViolinString.a,
        finger: ViolinFinger.first,
      ),
      SongNote(
        midiNote: 73, // C#5
        startTimeMs: 580,
        durationMs: 180,
        noteName: 'C#5',
        string: ViolinString.a,
        finger: ViolinFinger.highSecond,
      ),
      SongNote(
        midiNote: 74, // D5
        startTimeMs: 780,
        durationMs: 400,
        noteName: 'D5',
        string: ViolinString.a,
        finger: ViolinFinger.third,
      ),
      // Fast runs (1/16 notes: 110ms each)
      SongNote(
        midiNote: 76, // E5
        startTimeMs: 1200,
        durationMs: 110,
        noteName: 'E5',
        string: ViolinString.e,
        finger: ViolinFinger.open,
      ),
      SongNote(
        midiNote: 74, // D5
        startTimeMs: 1320,
        durationMs: 110,
        noteName: 'D5',
        string: ViolinString.a,
        finger: ViolinFinger.third,
      ),
      SongNote(
        midiNote: 73, // C#5
        startTimeMs: 1440,
        durationMs: 110,
        noteName: 'C#5',
        string: ViolinString.a,
        finger: ViolinFinger.highSecond,
      ),
      SongNote(
        midiNote: 71, // B4
        startTimeMs: 1560,
        durationMs: 250,
        noteName: 'B4',
        string: ViolinString.a,
        finger: ViolinFinger.first,
      ),
    ];

    final song = Song(
      id: 'final_verification_v3',
      title: 'Verification Piece',
      composer: 'EasyViolin Audio Engine',
      tempoBpm: 120,
      notes: notes,
    );

    // 1. DDSP Synthesis
    final ddspPcm = await DdspViolinSynthesizer.synthesizeSong(song, outputSampleRate: 44100);
    _saveWav('/tmp/verified_ddsp.wav', ddspPcm, 44100);

    // 2. SongAudioGenerator Synthesis
    final genPcm = SongAudioGenerator.generatePcm(song, sampleRate: 44100);
    _saveWav('/tmp/verified_gen.wav', genPcm, 44100);

    print('\n================== FINAL AUDIO QUALITY REPORT ==================');
    print('DDSP Audio: ${ddspPcm.length} samples (${(ddspPcm.length / 44100).toStringAsFixed(2)}s)');
    print('GEN Audio:  ${genPcm.length} samples (${(genPcm.length / 44100).toStringAsFixed(2)}s)');

    // Verify DDSP note audibility
    print('\n--- DDSP Note-by-Note Energy ---');
    for (final n in notes) {
      final sIdx = (n.startTimeMs * 44100 / 1000).round();
      final eIdx = (n.endTimeMs * 44100 / 1000).round().clamp(0, ddspPcm.length);
      double sum = 0.0;
      double nPeak = 0.0;
      for (int i = sIdx; i < eIdx; i++) {
        final val = ddspPcm[i];
        final a = val.abs();
        if (a > nPeak) nPeak = a;
        sum += val * val;
      }
      final rms = math.sqrt(sum / (eIdx - sIdx));
      print('  Note ${n.noteName.padRight(4)} (${n.startTimeMs.toString().padLeft(4)}-${n.endTimeMs.toString().padLeft(4)}ms): RMS=${rms.toStringAsFixed(4)}, Peak=${nPeak.toStringAsFixed(4)}');
      expect(rms, greaterThan(0.04), reason: 'Every DDSP note must be clearly audible and fully formed!');
    }

    // Verify GEN note audibility
    print('\n--- Generator Note-by-Note Energy ---');
    for (final n in notes) {
      final sIdx = (n.startTimeMs * 44100 / 1000).round();
      final eIdx = (n.endTimeMs * 44100 / 1000).round().clamp(0, genPcm.length);
      double sum = 0.0;
      double nPeak = 0.0;
      for (int i = sIdx; i < eIdx; i++) {
        final val = genPcm[i];
        final a = val.abs();
        if (a > nPeak) nPeak = a;
        sum += val * val;
      }
      final rms = math.sqrt(sum / (eIdx - sIdx));
      print('  Note ${n.noteName.padRight(4)} (${n.startTimeMs.toString().padLeft(4)}-${n.endTimeMs.toString().padLeft(4)}ms): RMS=${rms.toStringAsFixed(4)}, Peak=${nPeak.toStringAsFixed(4)}');
      expect(rms, greaterThan(0.04), reason: 'Every Generator note must be clearly audible and fully formed!');
    }

    print('================================================================\n');
  });
}
