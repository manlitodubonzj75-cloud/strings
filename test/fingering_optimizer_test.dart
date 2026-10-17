import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:easy_violin/models/song_model.dart';
import 'package:easy_violin/music_theory.dart';
import 'package:easy_violin/services/fingering_optimizer.dart';
import 'package:easy_violin/services/score_edit_controller.dart';
import 'package:easy_violin/ui/widgets/multi_measure_score_view.dart';

void main() {
  group('FingeringOptimizer', () {
    test('beginner firstPositionOnly keeps standard notes strictly in 1st position', () {
      // Suzuki Twinkle melody: A4, A4, E5, E5, F#5, F#5, E5
      final rawNotes = [
        SongNote(midiNote: 69, startTimeMs: 0, durationMs: 500, noteName: 'A4', string: ViolinString.a, finger: ViolinFinger.open),
        SongNote(midiNote: 69, startTimeMs: 500, durationMs: 500, noteName: 'A4', string: ViolinString.a, finger: ViolinFinger.open),
        SongNote(midiNote: 76, startTimeMs: 1000, durationMs: 500, noteName: 'E5', string: ViolinString.e, finger: ViolinFinger.open),
        SongNote(midiNote: 76, startTimeMs: 1500, durationMs: 500, noteName: 'E5', string: ViolinString.e, finger: ViolinFinger.open),
        SongNote(midiNote: 78, startTimeMs: 2000, durationMs: 500, noteName: 'F#5', string: ViolinString.e, finger: ViolinFinger.first),
        SongNote(midiNote: 78, startTimeMs: 2500, durationMs: 500, noteName: 'F#5', string: ViolinString.e, finger: ViolinFinger.first),
        SongNote(midiNote: 76, startTimeMs: 3000, durationMs: 1000, noteName: 'E5', string: ViolinString.e, finger: ViolinFinger.open),
      ];

      final optimized = FingeringOptimizer.optimizeNotes(
        rawNotes,
        preference: FingeringPreference.firstPositionOnly,
      );

      for (final note in optimized) {
        expect(note.position, 1, reason: 'All beginner notes should be in 1st position');
      }
    });

    test('automatically shifts to 3rd position for high notes exceeding 1st position (> B5)', () {
      // Notes: A5 (81), B5 (83), C6 (84), D6 (86)
      final rawNotes = [
        SongNote(midiNote: 81, startTimeMs: 0, durationMs: 400, noteName: 'A5', string: ViolinString.e, finger: ViolinFinger.third),
        SongNote(midiNote: 83, startTimeMs: 400, durationMs: 400, noteName: 'B5', string: ViolinString.e, finger: ViolinFinger.fourth),
        SongNote(midiNote: 84, startTimeMs: 800, durationMs: 400, noteName: 'C6', string: ViolinString.e, finger: ViolinFinger.fourth),
        SongNote(midiNote: 86, startTimeMs: 1200, durationMs: 400, noteName: 'D6', string: ViolinString.e, finger: ViolinFinger.fourth),
      ];

      final optimized = FingeringOptimizer.optimizeNotes(
        rawNotes,
        preference: FingeringPreference.balanced,
      );

      // C6 (84) and D6 (86) cannot be played naturally in 1st position
      expect(optimized[2].position, 3, reason: 'C6 should be played in 3rd position');
      expect(optimized[3].position, 3, reason: 'D6 should be played in 3rd position (4th finger on E string)');
      expect(optimized[3].finger, ViolinFinger.fourth);
    });

    test('cantilena preference avoids open strings when stopped finger can provide vibrato', () {
      // Note A4 (69) can be open A string or 4th finger on D string
      final rawNotes = [
        SongNote(midiNote: 62, startTimeMs: 0, durationMs: 500, noteName: 'D4', string: ViolinString.d, finger: ViolinFinger.open),
        SongNote(midiNote: 66, startTimeMs: 500, durationMs: 500, noteName: 'F#4', string: ViolinString.d, finger: ViolinFinger.highSecond),
        SongNote(midiNote: 69, startTimeMs: 1000, durationMs: 1000, noteName: 'A4', string: ViolinString.a, finger: ViolinFinger.open),
      ];

      final optimized = FingeringOptimizer.optimizeNotes(
        rawNotes,
        preference: FingeringPreference.cantilena,
      );

      // In cantilena after D4 and F#4, A4 on D string with 4th finger keeps the phrase on D string with vibrato!
      expect(optimized[2].string, ViolinString.d);
      expect(optimized[2].finger, ViolinFinger.fourth);
    });

    test('preserves notes on the same string under a slur', () {
      // 3 notes under the same slur: D4 (62), E4 (64), F#4 (66)
      final rawNotes = [
        SongNote(midiNote: 62, startTimeMs: 0, durationMs: 300, noteName: 'D4', string: ViolinString.d, finger: ViolinFinger.open, slurGroupId: 1),
        SongNote(midiNote: 64, startTimeMs: 300, durationMs: 300, noteName: 'E4', string: ViolinString.d, finger: ViolinFinger.first, slurGroupId: 1),
        SongNote(midiNote: 66, startTimeMs: 600, durationMs: 300, noteName: 'F#4', string: ViolinString.d, finger: ViolinFinger.highSecond, slurGroupId: 1),
      ];

      final optimized = FingeringOptimizer.optimizeNotes(rawNotes);
      expect(optimized.every((n) => n.string == ViolinString.d), isTrue);
    });

    test('getBestSingleNoteFingering returns sensible default', () {
      final (str, finger, pos) = FingeringOptimizer.getBestSingleNoteFingering(69);
      expect(pos, 1);
      expect(str, ViolinString.a);
      expect(finger, ViolinFinger.open);
    });

    test('MusicTheory roman numeral and candidate resolution', () {
      expect(MusicTheory.positionToRoman(1), 'I');
      expect(MusicTheory.positionToRoman(2), 'II');
      expect(MusicTheory.positionToRoman(3), 'III');

      final candidates = MusicTheory.getCandidatesForMidi(76); // E5
      expect(candidates, isNotEmpty);
      expect(candidates.any((c) => c.string == ViolinString.e && c.finger == ViolinFinger.open), isTrue);
    });

    test('ScoreEditController allows manual fingering and position modification', () {
      final song = Song(
        id: 'test_song',
        title: 'Test',
        composer: 'Test',
        tempoBpm: 120,
        notes: [
          SongNote(midiNote: 69, startTimeMs: 0, durationMs: 500, noteName: 'A4', string: ViolinString.a, finger: ViolinFinger.open),
        ],
      );

      final controller = ScoreEditController(initialSong: song);
      expect(controller.song.notes.first.position, 1);

      // Modify to 3rd position
      controller.modifyNoteFingering(0, position: 3, string: ViolinString.d, finger: ViolinFinger.highSecond);
      expect(controller.song.notes.first.position, 3);
      expect(controller.song.notes.first.string, ViolinString.d);
      expect(controller.song.notes.first.finger, ViolinFinger.highSecond);

      // Undo reverts change
      controller.undo();
      expect(controller.song.notes.first.position, 1);
    });

    testWidgets('MultiMeasureScoreView renders fingering numbers and position badge', (tester) async {
      final song = Song(
        id: 'pos_song',
        title: 'Position Song',
        composer: 'Test',
        tempoBpm: 120,
        notes: [
          SongNote(
            midiNote: 81, // A5
            startTimeMs: 0,
            durationMs: 500,
            noteName: 'A5',
            string: ViolinString.e,
            finger: ViolinFinger.first,
            position: 3, // In 3rd position!
          ),
        ],
      );

      final controller = ScoreEditController(initialSong: song);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MultiMeasureScoreView(
              measures: controller.measures,
              loopRange: controller.loopRange,
              currentNoteIndex: 0,
              showFingering: true,
              showPositions: true,
            ),
          ),
        ),
      );

      expect(find.byType(MultiMeasureScoreView), findsOneWidget);
      expect(find.byType(CustomPaint), findsWidgets);
    });
  });
}
