import 'package:flutter_test/flutter_test.dart';
import 'package:easy_violin/models/score_editor_contracts.dart';
import 'package:easy_violin/models/song_model.dart';
import 'package:easy_violin/music_theory.dart';
import 'package:easy_violin/services/score_edit_controller.dart';

void main() {
  group('Score System Acceptance Tests', () {
    late Song testSong;

    setUp(() {
      // 4 quarter notes at 120 BPM = 1 measure of 2000ms (500ms per beat)
      // Followed by 4 notes in Measure 2 (2000ms to 4000ms)
      testSong = Song(
        id: 'test_song',
        title: 'Test Sonata',
        composer: 'Vivaldi',
        tempoBpm: 120,
        notes: [
          // Measure 1
          SongNote(
            midiNote: 69, // A4
            startTimeMs: 0,
            durationMs: 500,
            noteName: 'A4',
            string: ViolinString.a,
            finger: ViolinFinger.open,
          ),
          SongNote(
            midiNote: 71, // B4
            startTimeMs: 500,
            durationMs: 500,
            noteName: 'B4',
            string: ViolinString.a,
            finger: ViolinFinger.first,
          ),
          SongNote(
            midiNote: 73, // C#5
            startTimeMs: 1000,
            durationMs: 500,
            noteName: 'C#5',
            string: ViolinString.a,
            finger: ViolinFinger.highSecond,
          ),
          SongNote(
            midiNote: 74, // D5
            startTimeMs: 1500,
            durationMs: 500,
            noteName: 'D5',
            string: ViolinString.a,
            finger: ViolinFinger.third,
          ),
          // Measure 2
          SongNote(
            midiNote: 76, // E5
            startTimeMs: 2000,
            durationMs: 500,
            noteName: 'E5',
            string: ViolinString.e,
            finger: ViolinFinger.open,
          ),
          SongNote(
            midiNote: 78, // F#5
            startTimeMs: 2500,
            durationMs: 500,
            noteName: 'F#5',
            string: ViolinString.e,
            finger: ViolinFinger.first,
          ),
          SongNote(
            midiNote: 80, // G#5
            startTimeMs: 3000,
            durationMs: 500,
            noteName: 'G#5',
            string: ViolinString.e,
            finger: ViolinFinger.highSecond,
          ),
          SongNote(
            midiNote: 81, // A5
            startTimeMs: 3500,
            durationMs: 500,
            noteName: 'A5',
            string: ViolinString.e,
            finger: ViolinFinger.third,
          ),
        ],
      );
    });

    test('1. ScoreMeasurePartitioner correctly divides song into measures', () {
      final measures = ScoreMeasurePartitioner.partitionSong(testSong);
      expect(measures.length, greaterThanOrEqualTo(2));

      // Measure 1
      expect(measures[0].index, equals(1));
      expect(measures[0].startTimeMs, equals(0));
      expect(measures[0].endTimeMs, equals(2000));
      expect(measures[0].notes.length, equals(4));
      expect(measures[0].notes.first.noteName, equals('A4'));

      // Measure 2
      expect(measures[1].index, equals(2));
      expect(measures[1].startTimeMs, equals(2000));
      expect(measures[1].endTimeMs, equals(4000));
      expect(measures[1].notes.length, equals(4));
      expect(measures[1].notes.first.noteName, equals('E5'));
    });

    test('2. ScoreLoopRange enforces measure-based looping and boundary checks', () {
      final controller = ScoreEditController(initialSong: testSong);
      expect(controller.loopRange.isEnabled, isFalse);

      // Select Measure 2 only
      controller.setLoopRange(2, 2, isEnabled: true);
      expect(controller.loopRange.isEnabled, isTrue);
      expect(controller.loopRange.containsMeasure(1), isFalse);
      expect(controller.loopRange.containsMeasure(2), isTrue);
      expect(controller.loopRange.containsMeasure(3), isFalse);

      // Time checks (Measure 2 is 2000ms .. 4000ms)
      expect(controller.loopRange.containsTime(1500, controller.measures), isFalse);
      expect(controller.loopRange.containsTime(2500, controller.measures), isTrue);
      expect(controller.loopRange.getStartTimeMs(controller.measures), equals(2000));
      expect(controller.loopRange.getEndTimeMs(controller.measures), equals(4000));

      // Extend to Measure 1-2
      controller.setLoopRange(1, 2);
      expect(controller.loopRange.containsMeasure(1), isTrue);
      expect(controller.loopRange.containsMeasure(2), isTrue);
    });

    test('3. Note Editing & Pitch Transpose with Undo/Redo', () {
      final controller = ScoreEditController(initialSong: testSong);

      // Select note 0 (A4, midi 69) and transpose up by 2 semitones to B4 (71)
      controller.selectNote(0);
      controller.transposeSelectedNote(2);

      expect(controller.song.notes[0].midiNote, equals(71));
      expect(controller.song.notes[0].noteName, equals('B4'));
      expect(controller.canUndo, isTrue);

      // Undo
      controller.undo();
      expect(controller.song.notes[0].midiNote, equals(69));
      expect(controller.song.notes[0].noteName, equals('A4'));

      // Redo
      controller.redo();
      expect(controller.song.notes[0].midiNote, equals(71));
    });

    test('4. Slur / Legato creation, removal, and bow direction editing', () {
      final controller = ScoreEditController(initialSong: testSong);

      // Create a slur connecting notes 0, 1, 2
      controller.addSlur(0, 2);

      final n0 = controller.song.notes[0];
      final n1 = controller.song.notes[1];
      final n2 = controller.song.notes[2];

      expect(n0.isSlurred, isTrue);
      expect(n0.isSlurStart, isTrue);
      expect(n0.isSlurEnd, isFalse);

      expect(n1.isSlurred, isTrue);
      expect(n1.isSlurStart, isFalse);
      expect(n1.isSlurEnd, isFalse);

      expect(n2.isSlurred, isTrue);
      expect(n2.isSlurStart, isFalse);
      expect(n2.isSlurEnd, isTrue);

      expect(n0.slurGroupId, equals(n1.slurGroupId));
      expect(n1.slurGroupId, equals(n2.slurGroupId));

      // Toggle bow direction on note 0 (null -> down -> up -> null)
      controller.toggleBowDirection(0);
      expect(controller.song.notes[0].bowDirection, equals(BowDirection.down));
      controller.toggleBowDirection(0);
      expect(controller.song.notes[0].bowDirection, equals(BowDirection.up));

      // Remove slur
      controller.removeSlur(1);
      expect(controller.song.notes[0].isSlurred, isFalse);
      expect(controller.song.notes[1].isSlurred, isFalse);
      expect(controller.song.notes[2].isSlurred, isFalse);
    });

    test('5. NoteEvaluationResult checks pitch accuracy, cents, and scratch noise', () {
      final targetNote = testSong.notes[0]; // A4 (440.0 Hz, midi 69)

      // Test 1: Exact pitch
      final inTuneResult = NoteEvaluationResult.evaluate(
        target: targetNote,
        playedMidi: 69,
        detectedPitchHz: 440.0,
        isScratching: false,
      );
      expect(inTuneResult.isInTune, isTrue);
      expect(inTuneResult.centsDeviation.abs(), lessThan(1.0));
      expect(inTuneResult.isScratching, isFalse);

      // Test 2: Slightly sharp (+15 cents, within 25 cents tolerance)
      final sharpResult = NoteEvaluationResult.evaluate(
        target: targetNote,
        playedMidi: 69,
        detectedPitchHz: 443.8, // ~+15 cents
        isScratching: false,
      );
      expect(sharpResult.isInTune, isTrue);
      expect(sharpResult.centsDeviation, greaterThan(10.0));

      // Test 3: Very flat (-35 cents, out of tune)
      final flatResult = NoteEvaluationResult.evaluate(
        target: targetNote,
        playedMidi: 69,
        detectedPitchHz: 431.2, // ~-35 cents
        isScratching: false,
      );
      expect(flatResult.isInTune, isFalse);

      // Test 4: Scratch noise from bow
      final scratchResult = NoteEvaluationResult.evaluate(
        target: targetNote,
        playedMidi: 69,
        detectedPitchHz: 440.0,
        isScratching: true,
      );
      expect(scratchResult.isInTune, isFalse);
      expect(scratchResult.isScratching, isTrue);
    });
  });
}
