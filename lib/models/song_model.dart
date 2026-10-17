import '../music_theory.dart';

enum BowDirection {
  down('⊓', 'Вниз смычком'), // Down-bow
  up('∨', 'Вверх смычком');   // Up-bow

  final String symbol;
  final String label;
  const BowDirection(this.symbol, this.label);
}

class SongNote {
  final int midiNote;
  final int startTimeMs;
  final int durationMs;
  final String noteName;
  final ViolinString string;
  final ViolinFinger finger;
  final int position; // 1, 2, 3, etc. (1st position is default)
  final bool isSlurStart;
  final bool isSlurEnd;
  final int? slurGroupId;
  final BowDirection? bowDirection;
  bool isHit;

  SongNote({
    required this.midiNote,
    required this.startTimeMs,
    required this.durationMs,
    required this.noteName,
    required this.string,
    required this.finger,
    this.position = 1,
    this.isSlurStart = false,
    this.isSlurEnd = false,
    this.slurGroupId,
    this.bowDirection,
    this.isHit = false,
  });

  bool get isSlurred => slurGroupId != null;
  int get endTimeMs => startTimeMs + durationMs;

  SongNote copyWith({
    int? midiNote,
    int? startTimeMs,
    int? durationMs,
    String? noteName,
    ViolinString? string,
    ViolinFinger? finger,
    int? position,
    bool? isSlurStart,
    bool? isSlurEnd,
    int? slurGroupId,
    BowDirection? bowDirection,
    bool? isHit,
  }) {
    return SongNote(
      midiNote: midiNote ?? this.midiNote,
      startTimeMs: startTimeMs ?? this.startTimeMs,
      durationMs: durationMs ?? this.durationMs,
      noteName: noteName ?? this.noteName,
      string: string ?? this.string,
      finger: finger ?? this.finger,
      position: position ?? this.position,
      isSlurStart: isSlurStart ?? this.isSlurStart,
      isSlurEnd: isSlurEnd ?? this.isSlurEnd,
      slurGroupId: slurGroupId ?? this.slurGroupId,
      bowDirection: bowDirection ?? this.bowDirection,
      isHit: isHit ?? this.isHit,
    );
  }
}

class Song {
  final String id;
  final String title;
  final String composer;
  final int tempoBpm;
  final List<SongNote> notes;

  const Song({
    required this.id,
    required this.title,
    required this.composer,
    required this.tempoBpm,
    required this.notes,
  });

  int get totalDurationMs {
    if (notes.isEmpty) return 0;
    return notes.last.endTimeMs + 1000;
  }
}
