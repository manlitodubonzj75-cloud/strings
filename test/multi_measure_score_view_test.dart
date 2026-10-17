import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:easy_violin/models/score_editor_contracts.dart';
import 'package:easy_violin/models/song_model.dart';
import 'package:easy_violin/music_theory.dart';
import 'package:easy_violin/services/score_edit_controller.dart';
import 'package:easy_violin/ui/widgets/multi_measure_score_view.dart';
import 'package:easy_violin/ui/widgets/score_editor_toolbar.dart';
import 'package:easy_violin/ui/widgets/intonation_quality_hud.dart';

void main() {
  group('MultiMeasureScoreView & Toolbar Widget Tests', () {
    late Song song;
    late ScoreEditController controller;

    setUp(() {
      song = Song(
        id: 'widget_sonata',
        title: 'Sonata in A',
        composer: 'Corelli',
        tempoBpm: 120,
        notes: [
          SongNote(
            midiNote: 69, // A4
            startTimeMs: 0,
            durationMs: 500,
            noteName: 'A4',
            string: ViolinString.a,
            finger: ViolinFinger.open,
            bowDirection: BowDirection.down,
          ),
          SongNote(
            midiNote: 71, // B4
            startTimeMs: 500,
            durationMs: 500,
            noteName: 'B4',
            string: ViolinString.a,
            finger: ViolinFinger.first,
            bowDirection: BowDirection.down,
            isSlurStart: true,
            slurGroupId: 1,
          ),
          SongNote(
            midiNote: 73, // C#5
            startTimeMs: 1000,
            durationMs: 500,
            noteName: 'C#5',
            string: ViolinString.a,
            finger: ViolinFinger.highSecond,
            bowDirection: BowDirection.down,
            isSlurEnd: true,
            slurGroupId: 1,
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
            bowDirection: BowDirection.up,
          ),
        ],
      );
      controller = ScoreEditController(initialSong: song);
    });

    testWidgets('Renders MultiMeasureScoreView with measures, loop, and notes', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MultiMeasureScoreView(
              measures: controller.measures,
              loopRange: controller.loopRange,
              currentNoteIndex: 0,
              targetMidi: 69,
              playedMidi: 69,
              isInTune: true,
            ),
          ),
        ),
      );

      expect(find.byType(MultiMeasureScoreView), findsOneWidget);
      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets('Renders ScoreEditorToolbar and updates note pitch & loop', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                ScoreEditorToolbar(controller: controller),
              ],
            ),
          ),
        ),
      );

      expect(find.byType(ScoreEditorToolbar), findsOneWidget);

      // Select Note 0
      controller.selectNote(0);
      await tester.pump();

      expect(find.textContaining('Нота A4'), findsOneWidget);
      expect(find.text('+1 полутон (♯)'), findsOneWidget);

      // Tap +1 semitone
      await tester.tap(find.text('+1 полутон (♯)'));
      await tester.pump();

      expect(controller.song.notes[0].midiNote, equals(70)); // A#4 / Bb4
      expect(controller.canUndo, isTrue);

      // Select Measure 2
      controller.selectMeasure(2);
      await tester.pump();

      expect(find.text('Зациклить такт 2'), findsOneWidget);

      // Tap loop measure 2
      await tester.tap(find.text('Зациклить такт 2'));
      await tester.pump();

      expect(controller.loopRange.isEnabled, isTrue);
      expect(controller.loopRange.startMeasure, equals(2));
      expect(controller.loopRange.endMeasure, equals(2));
    });

    testWidgets('Renders IntonationQualityHud with live feedback', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: IntonationQualityHud(
              targetNote: song.notes[0],
              detectedNote: const DetectedNoteInfo(
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
              ),
              isInTune: true,
              cents: 0.0,
              practiceModeLabel: 'Ждать ноту',
            ),
          ),
        ),
      );

      expect(find.byType(IntonationQualityHud), findsOneWidget);
      expect(find.text('В СТРОЮ'), findsOneWidget);
      expect(find.text('A4 (A-0)'), findsOneWidget);
      expect(find.textContaining('440.0 Гц'), findsOneWidget);
    });
  });
}
