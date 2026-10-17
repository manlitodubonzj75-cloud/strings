import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:easy_violin/controllers/audio_recognition_controller.dart';
import 'package:easy_violin/audio_engine.dart';
import 'package:easy_violin/music_theory.dart';

void main() {
  group('AudioRecognitionController Tests', () {
    test('Initialization defaults and parameter setters work cleanly', () {
      final controller = AudioRecognitionController();
      expect(controller.concertA4Hz, 440.0);
      expect(controller.selectedTunerString, isNull);
      expect(controller.isMicActive, isFalse);
      expect(controller.currentNote, isNull);

      controller.setConcertA4Hz(442.0);
      expect(controller.concertA4Hz, 442.0);

      controller.setSelectedTunerString(ViolinString.e);
      expect(controller.selectedTunerString, ViolinString.e);

      controller.dispose();
    });

    test('Notifies listeners on state changes', () {
      final controller = AudioRecognitionController();
      int notifyCount = 0;
      controller.addListener(() {
        notifyCount++;
      });

      controller.setConcertA4Hz(443.0);
      expect(notifyCount, 1);

      controller.setSelectedTunerString(ViolinString.a);
      expect(notifyCount, 2);

      controller.dispose();
    });
  });
}
