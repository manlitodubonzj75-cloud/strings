import 'package:flutter_test/flutter_test.dart';
import 'package:easy_violin/controllers/song_practice_controller.dart';
import 'package:easy_violin/models/song_model.dart';
import 'package:easy_violin/music_theory.dart';

void main() {
  group('SongPracticeController Tests', () {
    test('Initialization defaults', () {
      final controller = SongPracticeController();
      expect(controller.currentSong.notes, isNotEmpty);
      expect(controller.practiceMode, PracticeMode.waitNote);
      expect(controller.isPlaying, isFalse);
      expect(controller.isDemoPlaying, isFalse);
      expect(controller.score, 0);
      expect(controller.streak, 0);
      expect(controller.playbackSpeed, 1.0);
    });

    test('Cycle playback speed works across options', () {
      final controller = SongPracticeController();
      expect(controller.playbackSpeed, 1.0);

      controller.cyclePlaybackSpeed();
      expect(controller.playbackSpeed, 1.25);

      controller.cyclePlaybackSpeed();
      expect(controller.playbackSpeed, 1.5);

      controller.cyclePlaybackSpeed();
      expect(controller.playbackSpeed, 2.0);

      controller.cyclePlaybackSpeed();
      expect(controller.playbackSpeed, 0.5);
    });

    test('Practice mode switching and accompaniment toggle', () {
      final controller = SongPracticeController();
      expect(controller.isAccompanimentOn, isTrue);

      controller.toggleAccompaniment();
      expect(controller.isAccompanimentOn, isFalse);

      controller.setPracticeMode(PracticeMode.playAlong);
      expect(controller.practiceMode, PracticeMode.playAlong);
    });

    test('Evaluating correct note advances currentNoteIndex and awards points', () {
      final testNote = SongNote(
        midiNote: 69, // A4
        startTimeMs: 0,
        durationMs: 500,
        noteName: 'A4',
        string: ViolinString.a,
        finger: ViolinFinger.open,
      );
      final testSong = Song(
        id: 'test_song',
        title: 'Test Song',
        composer: 'Composer',
        tempoBpm: 120,
        notes: [
          testNote,
          SongNote(
            midiNote: 71, // B4
            startTimeMs: 500,
            durationMs: 500,
            noteName: 'B4',
            string: ViolinString.a,
            finger: ViolinFinger.first,
          ),
        ],
      );

      final controller = SongPracticeController(initialSong: testSong);
      controller.startPlayback();
      expect(controller.isPlaying, isTrue);
      expect(controller.currentNoteIndex, 0);

      final matchingNote = DetectedNoteInfo(
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

      controller.checkIncomingNote(matchingNote);

      expect(controller.score, 100);
      expect(controller.streak, 1);
      expect(controller.currentNoteIndex, 1);
      expect(controller.isSoundError, isFalse);
    });

    test('Evaluating scratching note halts score and marks sound error', () {
      final testSong = Song(
        id: 'test_song',
        title: 'Test Song',
        composer: 'Composer',
        tempoBpm: 120,
        notes: [
          SongNote(
            midiNote: 69,
            startTimeMs: 0,
            durationMs: 500,
            noteName: 'A4',
            string: ViolinString.a,
            finger: ViolinFinger.open,
          ),
        ],
      );

      final controller = SongPracticeController(initialSong: testSong);
      controller.startPlayback();

      final scratchNote = DetectedNoteInfo(
        rawHz: 440.0,
        targetHz: 440.0,
        cents: 0.0,
        noteName: 'A4',
        midiNote: 69,
        isInTune: false,
        isScratching: true,
        confidence: 0.50,
        pegAction: PegAction.inTune,
        chevronCount: 0,
      );

      controller.checkIncomingNote(scratchNote);
      expect(controller.isSoundError, isTrue);
      expect(controller.soundErrorMessage, contains('Скрип смычка'));
      expect(controller.score, 0);
      expect(controller.currentNoteIndex, 0);
    });
  });
}
