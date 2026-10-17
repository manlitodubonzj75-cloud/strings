import 'package:flutter_test/flutter_test.dart';
import 'package:easy_violin/controllers/tuner_controller.dart';
import 'package:easy_violin/music_theory.dart';

void main() {
  group('TunerController Tests', () {
    test('Default mode and properties', () {
      final controller = TunerController();
      expect(controller.activeMode, TunerMode.tuner);
      expect(controller.selectedString, isNull);
      expect(controller.concertA4Hz, 440.0);
      expect(controller.effectiveTunerString, ViolinString.a);
      expect(controller.tunerTargetHz, 440.0);
      expect(controller.tunerTargetMidi, 69);
      expect(controller.isTunerInTune, isFalse);
    });

    test('Mode switching and string selection', () {
      final controller = TunerController();

      controller.setActiveMode(TunerMode.accuracy);
      expect(controller.activeMode, TunerMode.accuracy);

      controller.setSelectedString(ViolinString.e);
      expect(controller.selectedString, ViolinString.e);
      expect(controller.effectiveTunerString, ViolinString.e);
      expect(controller.tunerTargetHz, closeTo(659.25, 0.1));

      // Toggle off
      controller.setSelectedString(ViolinString.e, toggle: true);
      expect(controller.selectedString, isNull);
    });

    test('Concert pitch calibration toggle', () {
      final controller = TunerController(initialConcertA4Hz: 440.0);
      controller.toggleConcertA4Pitch();
      expect(controller.concertA4Hz, 442.0);

      controller.toggleConcertA4Pitch();
      expect(controller.concertA4Hz, 440.0);
    });

    test('Physics metrics update on note input', () {
      final controller = TunerController();

      // Clean in-tune note
      final cleanNote = DetectedNoteInfo(
        rawHz: 440.0,
        targetHz: 440.0,
        cents: 0.0,
        noteName: 'A4',
        midiNote: 69,
        isInTune: true,
        isScratching: false,
        confidence: 0.95,
        pegAction: PegAction.inTune,
        chevronCount: 0,
      );

      controller.updateWithNote(cleanNote);
      expect(controller.smoothStability, greaterThan(0.5));
      expect(controller.isTunerInTune, isTrue);
      expect(controller.activeCents, closeTo(0.0, 0.1));

      // Scratching note
      final scratchNote = DetectedNoteInfo(
        rawHz: 440.0,
        targetHz: 440.0,
        cents: 0.0,
        noteName: 'A4',
        midiNote: 69,
        isInTune: false,
        isScratching: true,
        confidence: 0.40,
        pegAction: PegAction.inTune,
        chevronCount: 0,
      );

      controller.updateWithNote(scratchNote);
      expect(controller.smoothBowPressure, greaterThan(0.6));
    });

    test('Harmonic detection finds closest open string accurately', () {
      // 196 Hz -> G string
      expect(TunerController.findClosestOpenString(196.0, 440.0), ViolinString.g);
      // 392 Hz (2nd harmonic of G) -> G string
      expect(TunerController.findClosestOpenString(392.0, 440.0), ViolinString.g);
      // 293.6 Hz -> D string
      expect(TunerController.findClosestOpenString(293.6, 440.0), ViolinString.d);
      // 440 Hz -> A string
      expect(TunerController.findClosestOpenString(440.0, 440.0), ViolinString.a);
      // 659.2 Hz -> E string
      expect(TunerController.findClosestOpenString(659.2, 440.0), ViolinString.e);
    });
  });
}
