import 'package:flutter/foundation.dart';
import '../models/score_editor_contracts.dart';
import '../models/song_model.dart';
import '../music_theory.dart';
import 'fingering_optimizer.dart';

/// Controller that manages interactive editing of a Song score,
/// its measure partitions, loop boundaries, and undo/redo history.
class ScoreEditController extends ChangeNotifier {
  Song _song;
  final List<Song> _undoStack = [];
  final List<Song> _redoStack = [];
  static const int _maxHistory = 30;

  ScoreLoopRange _loopRange = const ScoreLoopRange.disabled();
  List<ScoreMeasure> _cachedMeasures = [];

  int? _selectedNoteIndex;
  int? _selectedMeasureIndex;

  ScoreEditController({required Song initialSong}) : _song = initialSong {
    _recomputeMeasures();
  }

  Song get song => _song;
  ScoreLoopRange get loopRange => _loopRange;
  List<ScoreMeasure> get measures => _cachedMeasures;
  int? get selectedNoteIndex => _selectedNoteIndex;
  int? get selectedMeasureIndex => _selectedMeasureIndex;

  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;

  void selectNote(int? index) {
    if (_selectedNoteIndex != index) {
      _selectedNoteIndex = index;
      notifyListeners();
    }
  }

  void selectMeasure(int? index) {
    if (_selectedMeasureIndex != index) {
      _selectedMeasureIndex = index;
      notifyListeners();
    }
  }

  void _pushUndo() {
    _undoStack.add(_song);
    if (_undoStack.length > _maxHistory) {
      _undoStack.removeAt(0);
    }
    _redoStack.clear();
  }

  void undo() {
    if (!canUndo) return;
    _redoStack.add(_song);
    _song = _undoStack.removeLast();
    _recomputeMeasures();
    notifyListeners();
  }

  void redo() {
    if (!canRedo) return;
    _undoStack.add(_song);
    _song = _redoStack.removeLast();
    _recomputeMeasures();
    notifyListeners();
  }

  void _recomputeMeasures() {
    _cachedMeasures = ScoreMeasurePartitioner.partitionSong(_song);
  }

  void setSong(Song newSong) {
    _pushUndo();
    _song = newSong;
    _selectedNoteIndex = null;
    _selectedMeasureIndex = null;
    _recomputeMeasures();
    notifyListeners();
  }

  static (ViolinString, ViolinFinger, int) _getPreferredPosition(int midi) {
    return FingeringOptimizer.getBestSingleNoteFingering(midi);
  }

  // --- Measure & Loop Control ---

  void setLoopRange(int startMeasure, int endMeasure, {bool isEnabled = true}) {
    final maxM = _cachedMeasures.isEmpty ? 1 : _cachedMeasures.length;
    final s = startMeasure.clamp(1, maxM);
    final e = endMeasure.clamp(s, maxM);
    _loopRange = ScoreLoopRange(
      startMeasure: s,
      endMeasure: e,
      isEnabled: isEnabled,
    );
    notifyListeners();
  }

  void toggleLoop() {
    _loopRange = _loopRange.copyWith(isEnabled: !_loopRange.isEnabled);
    notifyListeners();
  }

  void clearLoop() {
    _loopRange = const ScoreLoopRange.disabled();
    notifyListeners();
  }

  void selectMeasureForLoop(int measureNumber) {
    if (!_loopRange.isEnabled || _loopRange.startMeasure != _loopRange.endMeasure) {
      // Single measure loop
      setLoopRange(measureNumber, measureNumber, isEnabled: true);
    } else {
      // Extend loop to range
      if (measureNumber < _loopRange.startMeasure) {
        setLoopRange(measureNumber, _loopRange.endMeasure, isEnabled: true);
      } else {
        setLoopRange(_loopRange.startMeasure, measureNumber, isEnabled: true);
      }
    }
  }

  // --- Note Editing ---

  void modifyNotePitch(int noteIndex, int newMidiNote) {
    if (noteIndex < 0 || noteIndex >= _song.notes.length) return;
    _pushUndo();

    final old = _song.notes[noteIndex];
    final noteName = MusicTheory.midiToNoteName(newMidiNote);
    final (str, fgr, pos) = _getPreferredPosition(newMidiNote);

    final updated = old.copyWith(
      midiNote: newMidiNote,
      noteName: noteName,
      string: str,
      finger: fgr,
      position: pos,
    );

    final newNotes = List<SongNote>.from(_song.notes);
    newNotes[noteIndex] = updated;

    _song = Song(
      id: _song.id,
      title: _song.title,
      composer: _song.composer,
      tempoBpm: _song.tempoBpm,
      notes: newNotes,
    );

    _recomputeMeasures();
    notifyListeners();
  }

  void modifyNoteFingering(
    int noteIndex, {
    ViolinString? string,
    ViolinFinger? finger,
    int? position,
  }) {
    if (noteIndex < 0 || noteIndex >= _song.notes.length) return;
    _pushUndo();

    final old = _song.notes[noteIndex];
    final updated = old.copyWith(
      string: string,
      finger: finger,
      position: position,
    );

    final newNotes = List<SongNote>.from(_song.notes);
    newNotes[noteIndex] = updated;

    _song = Song(
      id: _song.id,
      title: _song.title,
      composer: _song.composer,
      tempoBpm: _song.tempoBpm,
      notes: newNotes,
    );

    _recomputeMeasures();
    notifyListeners();
  }

  void autoOptimizeFingering({
    FingeringPreference preference = FingeringPreference.balanced,
    int maxPosition = 3,
  }) {
    if (_song.notes.isEmpty) return;
    _pushUndo();

    final optimizedNotes = FingeringOptimizer.optimizeNotes(
      _song.notes,
      preference: preference,
      maxPosition: maxPosition,
    );

    _song = Song(
      id: _song.id,
      title: _song.title,
      composer: _song.composer,
      tempoBpm: _song.tempoBpm,
      notes: optimizedNotes,
    );

    _recomputeMeasures();
    notifyListeners();
  }

  void transposeSelectedNote(int semitones) {
    if (_selectedNoteIndex == null) return;
    final note = _song.notes[_selectedNoteIndex!];
    final newMidi = (note.midiNote + semitones).clamp(55, 100); // G3 to E7
    modifyNotePitch(_selectedNoteIndex!, newMidi);
  }

  void toggleBowDirection(int noteIndex) {
    if (noteIndex < 0 || noteIndex >= _song.notes.length) return;
    _pushUndo();

    final old = _song.notes[noteIndex];
    BowDirection? nextDir;
    if (old.bowDirection == null) {
      nextDir = BowDirection.down;
    } else if (old.bowDirection == BowDirection.down) {
      nextDir = BowDirection.up;
    } else {
      nextDir = null;
    }

    final updated = old.copyWith(
      bowDirection: nextDir,
    );

    final newNotes = List<SongNote>.from(_song.notes);
    newNotes[noteIndex] = updated;

    _song = Song(
      id: _song.id,
      title: _song.title,
      composer: _song.composer,
      tempoBpm: _song.tempoBpm,
      notes: newNotes,
    );

    _recomputeMeasures();
    notifyListeners();
  }

  // --- Slurs & Legato Editing ---

  void addSlur(int startNoteIndex, int endNoteIndex) {
    if (startNoteIndex < 0 ||
        endNoteIndex >= _song.notes.length ||
        startNoteIndex >= endNoteIndex) {
      return;
    }
    _pushUndo();

    // Generate unique slurGroupId
    int maxGroupId = 0;
    for (final n in _song.notes) {
      if (n.slurGroupId != null && n.slurGroupId! > maxGroupId) {
        maxGroupId = n.slurGroupId!;
      }
    }
    final newGroupId = maxGroupId + 1;

    final newNotes = List<SongNote>.from(_song.notes);
    for (int i = startNoteIndex; i <= endNoteIndex; i++) {
      final old = newNotes[i];
      newNotes[i] = old.copyWith(
        isSlurStart: i == startNoteIndex,
        isSlurEnd: i == endNoteIndex,
        slurGroupId: newGroupId,
        bowDirection: old.bowDirection ?? newNotes[startNoteIndex].bowDirection,
      );
    }

    _song = Song(
      id: _song.id,
      title: _song.title,
      composer: _song.composer,
      tempoBpm: _song.tempoBpm,
      notes: newNotes,
    );

    _recomputeMeasures();
    notifyListeners();
  }

  void removeSlur(int noteIndex) {
    if (noteIndex < 0 || noteIndex >= _song.notes.length) return;
    final target = _song.notes[noteIndex];
    if (target.slurGroupId == null) return;
    _pushUndo();

    final groupId = target.slurGroupId;
    final newNotes = List<SongNote>.from(_song.notes);
    for (int i = 0; i < newNotes.length; i++) {
      if (newNotes[i].slurGroupId == groupId) {
        final old = newNotes[i];
        newNotes[i] = SongNote(
          midiNote: old.midiNote,
          startTimeMs: old.startTimeMs,
          durationMs: old.durationMs,
          noteName: old.noteName,
          string: old.string,
          finger: old.finger,
          position: old.position,
          isSlurStart: false,
          isSlurEnd: false,
          slurGroupId: null,
          bowDirection: old.bowDirection,
          isHit: old.isHit,
        );
      }
    }

    _song = Song(
      id: _song.id,
      title: _song.title,
      composer: _song.composer,
      tempoBpm: _song.tempoBpm,
      notes: newNotes,
    );

    _recomputeMeasures();
    notifyListeners();
  }

  void deleteNote(int noteIndex) {
    if (noteIndex < 0 || noteIndex >= _song.notes.length) return;
    _pushUndo();

    final newNotes = List<SongNote>.from(_song.notes)..removeAt(noteIndex);
    _song = Song(
      id: _song.id,
      title: _song.title,
      composer: _song.composer,
      tempoBpm: _song.tempoBpm,
      notes: newNotes,
    );

    if (_selectedNoteIndex != null) {
      if (_selectedNoteIndex == noteIndex) {
        _selectedNoteIndex = null;
      } else if (_selectedNoteIndex! > noteIndex) {
        _selectedNoteIndex = _selectedNoteIndex! - 1;
      }
    }

    _recomputeMeasures();
    notifyListeners();
  }
}
