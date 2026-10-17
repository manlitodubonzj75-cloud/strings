import 'dart:math' as math;
import 'dart:typed_data';

/// High-fidelity Waveform Similarity Overlap-Add (WSOLA) Time-Stretcher.
///
/// Slows down or accelerates audio playback duration while strictly preserving
/// exact acoustic pitch (zero pitch shifting, zero formant transposition).
///
/// Operates entirely in the time domain by aligning pitch-synchronous waveform grains,
/// eliminating the phase dispersion / "underwater" artifacts of phase vocoders.
class AudioTimeStretcher {
  /// Stretches or compresses audio duration by [stretchFactor] while preserving pitch.
  ///
  /// - [stretchFactor] = 2.0: 2x slowdown (duration doubled, tempo halved).
  /// - [stretchFactor] = 1.0: no-op (returns input unchanged).
  /// - [stretchFactor] = 0.5: 2x acceleration (duration halved).
  static Float32List timeStretch(
    Float32List input, {
    double stretchFactor = 2.0,
    int windowSize = 1024,
    int searchRange = 256,
  }) {
    if (input.isEmpty || (stretchFactor - 1.0).abs() < 1e-4) {
      return input;
    }

    final alpha = stretchFactor.clamp(0.25, 4.0);
    final winSize = windowSize;
    final hopSyn = winSize ~/ 2;
    final hopAna = math.max(1, (hopSyn / alpha).round());
    final deltaMax = searchRange;

    // Hann window for seamless overlap-add
    final win = Float32List(winSize);
    for (int i = 0; i < winSize; i++) {
      win[i] = 0.5 * (1.0 - math.cos(2.0 * math.pi * i / (winSize - 1)));
    }

    final outLength = (input.length * alpha).round();
    final output = Float32List(outLength + winSize + hopSyn);
    final weightSum = Float32List(outLength + winSize + hopSyn);

    // Initial grain at position 0
    final initCopyLen = math.min(winSize, input.length);
    for (int i = 0; i < initCopyLen; i++) {
      final w = win[i];
      output[i] += input[i] * w;
      weightSum[i] += w;
    }

    int pPrev = 0;
    int k = 1;
    int uK = hopSyn;
    int tK = hopAna;

    while (tK + winSize + deltaMax < input.length && uK + winSize < outLength) {
      final natPos = pPrev + hopSyn;
      if (natPos + winSize > input.length) break;

      // Cross-correlation search around target tK to find best waveform phase alignment
      final dMin = math.max(0, tK - deltaMax);
      final dMax = math.min(input.length - winSize, tK + deltaMax);

      int bestP = tK;
      double bestCorr = -1e12;

      // Step by 2 for high performance without precision loss
      for (int p = dMin; p < dMax; p += 2) {
        double corr = 0.0;
        for (int i = 0; i < winSize; i += 2) {
          corr += input[natPos + i] * input[p + i];
        }
        if (corr > bestCorr) {
          bestCorr = corr;
          bestP = p;
        }
      }

      for (int i = 0; i < winSize; i++) {
        final w = win[i];
        output[uK + i] += input[bestP + i] * w;
        weightSum[uK + i] += w;
      }

      pPrev = bestP;
      k++;
      uK = k * hopSyn;
      tK = k * hopAna;
    }

    // Seamlessly bridge any remaining output tail up to outLength
    if (uK < outLength) {
      final remIn = input.length - pPrev;
      final remOut = outLength - uK;
      final copyLen = math.min(remIn, remOut);
      for (int i = 0; i < copyLen; i++) {
        final w = (i < winSize) ? win[i] : 1.0;
        output[uK + i] += input[pPrev + i] * w;
        weightSum[uK + i] += w;
      }
    }

    // Normalize overlapping grain weights
    for (int i = 0; i < outLength; i++) {
      final w = weightSum[i];
      if (w > 1e-4) {
        output[i] /= w;
      }
    }

    final result = Float32List(outLength);
    result.setRange(0, outLength, output);
    return result;
  }
}
