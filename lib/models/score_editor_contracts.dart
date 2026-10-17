import '../music_theory.dart';
import 'song_model.dart';

/// Represents a single musical measure (bar) calculated from tempo and time signature.
class ScoreMeasure {
  final int index; // 1-based index (Measure 1, 2, ...)
  final int startTimeMs;
  final int endTimeMs;
  final List<SongNote> notes;

  const ScoreMeasure({
    required this.index,
    required this.startTimeMs,
    required this.endTimeMs,
    required this.notes,
  });

  int get durationMs => endTimeMs - startTimeMs;

  bool containsTime(int timeMs) => timeMs >= startTimeMs && timeMs < endTimeMs;
}

/// Loop range specifying which measures are selected for loop playback.
class ScoreLoopRange {
  final int startMeasure; // 1-based
  final int endMeasure;   // 1-based (inclusive)
  final bool isEnabled;

  const ScoreLoopRange({
    required this.startMeasure,
    required this.endMeasure,
    this.isEnabled = true,
  });

  const ScoreLoopRange.disabled()
      : startMeasure = 1,
        endMeasure = 1,
        isEnabled = false;

  ScoreLoopRange copyWith({
    int? startMeasure,
    int? endMeasure,
    bool? isEnabled,
  }) {
    return ScoreLoopRange(
      startMeasure: startMeasure ?? this.startMeasure,
      endMeasure: endMeasure ?? this.endMeasure,
      isEnabled: isEnabled ?? this.isEnabled,
    );
  }

  bool containsMeasure(int measureIndex) {
    if (!isEnabled) return true;
    return measureIndex >= startMeasure && measureIndex <= endMeasure;
  }

  bool containsTime(int timeMs, List<ScoreMeasure> measures) {
    if (!isEnabled || measures.isEmpty) return true;
    final startIdx = (startMeasure - 1).clamp(0, measures.length - 1);
    final endIdx = (endMeasure - 1).clamp(0, measures.length - 1);
    final loopStartMs = measures[startIdx].startTimeMs;
    final loopEndMs = measures[endIdx].endTimeMs;
    return timeMs >= loopStartMs && timeMs <= loopEndMs;
  }

  int getStartTimeMs(List<ScoreMeasure> measures) {
    if (measures.isEmpty) return 0;
    final startIdx = (startMeasure - 1).clamp(0, measures.length - 1);
    return measures[startIdx].startTimeMs;
  }

  int getEndTimeMs(List<ScoreMeasure> measures) {
    if (measures.isEmpty) return 0;
    final endIdx = (endMeasure - 1).clamp(0, measures.length - 1);
    return measures[endIdx].endTimeMs;
  }
}

/// Partition helper that splits Song notes into discrete measures.
class ScoreMeasurePartitioner {
  static List<ScoreMeasure> partitionSong(
    Song song, {
    int beatsPerMeasure = 4,
    int beatUnit = 4,
  }) {
    if (song.notes.isEmpty) return [];

    final bpm = song.tempoBpm > 0 ? song.tempoBpm : 120;
    final beatDurationMs = (60000.0 / bpm).round();
    final measureDurationMs = beatDurationMs * beatsPerMeasure;

    final totalDuration = song.totalDurationMs;
    final measureCount = ((totalDuration / measureDurationMs).ceil()).clamp(1, 9999);

    final List<List<SongNote>> bucket = List.generate(measureCount, (_) => []);

    for (final note in song.notes) {
      final measureIdx = (note.startTimeMs ~/ measureDurationMs).clamp(0, measureCount - 1);
      bucket[measureIdx].add(note);
    }

    return List.generate(measureCount, (i) {
      final start = i * measureDurationMs;
      final end = start + measureDurationMs;
      return ScoreMeasure(
        index: i + 1,
        startTimeMs: start,
        endTimeMs: end,
        notes: bucket[i],
      );
    });
  }
}

/// Evaluation result for a played note against the current score target.
class NoteEvaluationResult {
  final int targetMidi;
  final int? playedMidi;
  final double centsDeviation;
  final bool isInTune;
  final bool isScratching;
  final bool isBowDirectionCorrect;
  final String message;

  const NoteEvaluationResult({
    required this.targetMidi,
    this.playedMidi,
    required this.centsDeviation,
    required this.isInTune,
    this.isScratching = false,
    this.isBowDirectionCorrect = true,
    required this.message,
  });

  static NoteEvaluationResult evaluate({
    required SongNote target,
    required int? playedMidi,
    required double? detectedPitchHz,
    required bool isScratching,
    BowDirection? currentBowDirection,
    double toleranceCents = 25.0,
  }) {
    if (isScratching) {
      return NoteEvaluationResult(
        targetMidi: target.midiNote,
        playedMidi: playedMidi,
        centsDeviation: 0.0,
        isInTune: false,
        isScratching: true,
        message: 'Скрип смычка (scratch noise)! Ослабьте нажим смычка.',
      );
    }

    if (playedMidi == null || detectedPitchHz == null || detectedPitchHz <= 0) {
      return NoteEvaluationResult(
        targetMidi: target.midiNote,
        centsDeviation: 0.0,
        isInTune: false,
        message: 'Ожидание ноты...',
      );
    }

    final targetFreq = MusicTheory.midiToHz(target.midiNote);
    final cents = MusicTheory.calculateCents(detectedPitchHz, targetFreq);
    final inTune = playedMidi == target.midiNote && cents.abs() <= toleranceCents;

    final bowCorrect = target.bowDirection == null ||
        currentBowDirection == null ||
        target.bowDirection == currentBowDirection;

    String msg;
    if (inTune && bowCorrect) {
      msg = 'Идеально! (${cents > 0 ? "+${cents.toStringAsFixed(1)}" : cents.toStringAsFixed(1)} центов)';
    } else if (playedMidi == target.midiNote) {
      if (!bowCorrect) {
        msg = 'Штрих смычка не совпадает! Нужен ${target.bowDirection?.label ?? ""}';
      } else {
        msg = cents > 0 ? 'Высит (+${cents.toStringAsFixed(1)}c)' : 'Низит (${cents.toStringAsFixed(1)}c)';
      }
    } else {
      msg = 'Неверная нота (сыграно $playedMidi, нужно ${target.midiNote})';
    }

    return NoteEvaluationResult(
      targetMidi: target.midiNote,
      playedMidi: playedMidi,
      centsDeviation: cents,
      isInTune: inTune && bowCorrect,
      isScratching: false,
      isBowDirectionCorrect: bowCorrect,
      message: msg,
    );
  }
}
