// ignore_for_file: avoid_print
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:easy_violin/services/audio_time_stretcher.dart';

void main() {
  test('WSOLA time-stretches audio by 2x while strictly preserving fundamental pitch', () {
    const sr = 22050;
    const durSec = 0.5;
    final totalSamples = (sr * durSec).round();
    final input = Float32List(totalSamples);
    const freqHz = 440.0;

    for (int i = 0; i < totalSamples; i++) {
      final t = i / sr;
      input[i] = math.sin(2.0 * math.pi * freqHz * t);
    }

    final sw = Stopwatch()..start();
    final stretched = AudioTimeStretcher.timeStretch(input, stretchFactor: 2.0);
    sw.stop();

    print('Stretched 0.5s audio to 1.0s in ${sw.elapsedMilliseconds} ms');

    // 1. Duration check (~2x length)
    expect(stretched.length, equals((totalSamples * 2.0).round()));

    // 2. Pitch preservation check via autocorrelation peak
    // For 440 Hz at 22050 Hz, period tau = 22050 / 440 = 50.11 samples
    final startIdx = 2000;
    final testLen = 4096;
    double maxCorr = -1.0;
    int bestTau = 0;
    for (int tau = 30; tau < 80; tau++) {
      double corr = 0.0;
      for (int i = 0; i < testLen; i++) {
        corr += stretched[startIdx + i] * stretched[startIdx + i + tau];
      }
      if (corr > maxCorr) {
        maxCorr = corr;
        bestTau = tau;
      }
    }

    final detectedFreq = sr / bestTau.toDouble();
    print('Autocorrelation best tau: $bestTau, detected freq: ${detectedFreq.toStringAsFixed(1)} Hz');
    expect(detectedFreq, closeTo(freqHz, 6.0));
  });
}
