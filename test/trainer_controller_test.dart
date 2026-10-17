import 'package:flutter_test/flutter_test.dart';
import 'package:easy_violin/controllers/trainer_controller.dart';
import 'package:easy_violin/music_theory.dart';

void main() {
  group('TrainerController Tests', () {
    test('Initializes with default scale (D Major)', () {
      final controller = TrainerController();
      expect(controller.currentScale.name, contains('D'));
      expect(controller.currentStepIndex, 0);
      expect(controller.currentStep.russianNote, 'Ре');
      expect(controller.holdProgress, 0.0);
      expect(controller.streak, 0);
      expect(controller.trainMode, 'fixed');
    });

    test('Navigates scale steps correctly', () {
      final controller = TrainerController();
      final totalSteps = controller.currentScale.steps.length;

      controller.nextStep();
      expect(controller.currentStepIndex, 1);

      controller.prevStep();
      expect(controller.currentStepIndex, 0);

      controller.prevStep();
      expect(controller.currentStepIndex, totalSteps - 1);
    });

    test('Scale selection updates scale and resets step index', () {
      final controller = TrainerController();
      controller.nextStep();
      expect(controller.currentStepIndex, 1);

      // Select G Major (pos1)
      const gMajor = TonalityDef(position: CirclePosition.pos1, mode: TonalityMode.major);
      controller.selectTonality(gMajor);

      expect(controller.selectedTonality, gMajor);
      expect(controller.currentStepIndex, 0);
      expect(controller.currentStep.russianNote, 'Соль');
    });

    test('Evaluating matching note increments hold progress and streak', () {
      final controller = TrainerController();
      final targetStep = controller.currentStep;

      final matchNote = DetectedNoteInfo(
        rawHz: targetStep.targetHz,
        targetHz: targetStep.targetHz,
        cents: 0.0,
        noteName: MusicTheory.midiToNoteName(targetStep.midiNote),
        midiNote: targetStep.midiNote,
        isInTune: true,
        isScratching: false,
        confidence: 0.95,
        pegAction: PegAction.inTune,
        chevronCount: 0,
      );

      // 13 ticks of +0.08 will reach 1.0 (0.96 + 0.08 = 1.04 >= 1.0)
      for (int i = 0; i < 13; i++) {
        controller.processTick(matchNote);
      }

      // Should have advanced step and increased streak!
      expect(controller.streak, 1);
      expect(controller.currentStepIndex, 1);
    });

    test('Evaluating silent note decays hold progress', () {
      final controller = TrainerController();
      final targetStep = controller.currentStep;

      final matchNote = DetectedNoteInfo(
        rawHz: targetStep.targetHz,
        targetHz: targetStep.targetHz,
        cents: 0.0,
        noteName: MusicTheory.midiToNoteName(targetStep.midiNote),
        midiNote: targetStep.midiNote,
        isInTune: true,
        isScratching: false,
        confidence: 0.95,
        pegAction: PegAction.inTune,
        chevronCount: 0,
      );

      controller.processTick(matchNote);
      expect(controller.holdProgress, greaterThan(0.0));

      final initialProgress = controller.holdProgress;
      controller.processTick(null);
      expect(controller.holdProgress, lessThan(initialProgress));
    });

    test('Toggle circle of fifths and modes', () {
      final controller = TrainerController();
      expect(controller.showCircleOfFifths, isFalse);

      controller.toggleCircleOfFifths();
      expect(controller.showCircleOfFifths, isTrue);

      controller.setTrainMode('accel');
      expect(controller.trainMode, 'accel');
    });
  });
}
