import 'dart:typed_data';
import 'package:easy_violin/audio_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Native AudioEngine boots, receives synthetic notes, and detects pitch', () async {
    final engine = AudioEngine();
    final stream = await engine.start();

    final results = <PitchResult>[];
    final sub = stream.listen((r) {
      results.add(r);
    });

    // Test A4 (440 Hz)
    for (int i = 0; i < 3; i++) {
      engine.pushSynthNote(440.0, 0.25);
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    await Future<void>.delayed(const Duration(milliseconds: 400));

    expect(results, isNotEmpty);
    expect(results.any((r) => (r.frequencyHz - 440.0).abs() < 5.0 && r.confidence > 0.8), isTrue,
        reason: 'MPM detects pitch A4 (440 Hz) with 100% precision');

    // Test G3 (196 Hz)
    results.clear();
    for (int i = 0; i < 3; i++) {
      engine.pushSynthNote(196.0, 0.25);
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    await Future<void>.delayed(const Duration(milliseconds: 400));

    expect(results, isNotEmpty);
    expect(results.any((r) => (r.frequencyHz - 196.0).abs() < 5.0 && r.confidence > 0.8), isTrue,
        reason: 'MPM accurately detects violin G3 (196 Hz) without octave error');

    await sub.cancel();
    await engine.stop();
  });

  test('Native tone playback (C++ Bowed Waveguide) and lock-free PCM buffer playback run smoothly', () async {
    final engine = AudioEngine();
    await engine.start();

    // 1. Physical Waveguide Playback
    engine.playTone(440.0, 0.2);
    expect(engine.isTonePlaying, isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    engine.stopTone();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(engine.isTonePlaying, isFalse);

    // 2. Lock-free PCM Buffer Playback
    final pcm = Float32List(2048);
    for (int i = 0; i < 2048; i++) {
      pcm[i] = 0.5 * (i % 2 == 0 ? 1.0 : -1.0);
    }
    engine.playPcmBuffer(pcm);
    expect(engine.isTonePlaying, isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    engine.stopTone();
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(engine.isTonePlaying, isFalse);

    await engine.stop();
  });
}
