import 'dart:io';
import 'dart:typed_data';

class AudioDecoderCliHelper {
  /// Detects real file container extension from magic bytes to prevent afconvert / ffmpeg failures.
  static String detectExtension(Uint8List bytes) {
    if (bytes.length < 12) return 'mp3';
    // 1. RIFF WAVE
    if (bytes[0] == 0x52 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x46 &&
        bytes[8] == 0x57 && bytes[9] == 0x41 && bytes[10] == 0x56 && bytes[11] == 0x45) {
      return 'wav';
    }
    // 2. ID3 or MP3 sync
    if ((bytes[0] == 0x49 && bytes[1] == 0x44 && bytes[2] == 0x33) ||
        (bytes[0] == 0xFF && (bytes[1] & 0xE0) == 0xE0 && (bytes[1] & 0x06) == 0x02)) {
      return 'mp3';
    }
    // 3. AAC ADTS frame sync
    if (bytes[0] == 0xFF && (bytes[1] & 0xF0) == 0xF0) {
      return 'aac';
    }
    // 4. M4A / MP4 / MOV (ftyp)
    if (bytes.length >= 8 &&
        bytes[4] == 0x66 && bytes[5] == 0x74 && bytes[6] == 0x79 && bytes[7] == 0x70) {
      return 'm4a';
    }
    // 5. FLAC
    if (bytes[0] == 0x66 && bytes[1] == 0x4C && bytes[2] == 0x61 && bytes[3] == 0x43) {
      return 'flac';
    }
    // 6. OGG
    if (bytes[0] == 0x4F && bytes[1] == 0x67 && bytes[2] == 0x67 && bytes[3] == 0x53) {
      return 'ogg';
    }
    return 'mp3';
  }

  static Future<Uint8List?> convertToWav(Uint8List audioBytes, int targetSampleRate) async {
    try {
      final ext = detectExtension(audioBytes);
      final tempDir = Directory.systemTemp.createTempSync('easy_violin_dec_');
      final inputFile = File('${tempDir.path}/input.$ext');
      final outputFile = File('${tempDir.path}/output.wav');
      await inputFile.writeAsBytes(audioBytes);

      bool success = false;
      // 1. macOS afconvert (built into all macOS versions, ultra-fast)
      if (Platform.isMacOS && File('/usr/bin/afconvert').existsSync()) {
        final res = await Process.run('/usr/bin/afconvert', [
          '-f', 'WAVE',
          '-d', 'LEF32@$targetSampleRate',
          '-c', '1',
          inputFile.path,
          outputFile.path,
        ]);
        if (res.exitCode == 0 && outputFile.existsSync() && outputFile.lengthSync() > 44) {
          success = true;
        }
      }

      // 2. FFmpeg fallback (macOS / Linux / Windows)
      if (!success) {
        final ffmpeg = _findFfmpeg();
        if (ffmpeg != null) {
          final res = await Process.run(ffmpeg, [
            '-y',
            '-i', inputFile.path,
            '-ar', '$targetSampleRate',
            '-ac', '1',
            '-c:a', 'pcm_f32le',
            outputFile.path,
          ]);
          if (res.exitCode == 0 && outputFile.existsSync() && outputFile.lengthSync() > 44) {
            success = true;
          }
        }
      }

      if (success) {
        final wavBytes = await outputFile.readAsBytes();
        try {
          tempDir.deleteSync(recursive: true);
        } catch (_) {}
        return wavBytes;
      }

      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    } catch (_) {}
    return null;
  }

  static String? _findFfmpeg() {
    if (Platform.isAndroid || Platform.isIOS) return null;
    final candidates = [
      '/usr/local/bin/ffmpeg',
      '/opt/homebrew/bin/ffmpeg',
      '/usr/bin/ffmpeg',
      '${Platform.environment['HOME']}/.local/bin/ffmpeg',
      'ffmpeg',
    ];
    for (final p in candidates) {
      if (p.startsWith('/') && File(p).existsSync()) return p;
    }
    return 'ffmpeg';
  }
}
