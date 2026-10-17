import 'package:flutter/foundation.dart';
import '../audio_engine.dart';
import '../music_theory.dart';

enum TunerMode {
  /// Open string pitch matching and peg tuning instructions
  tuner,

  /// Micro-intonation, chromatic accuracy, and fingerboard position tracking
  accuracy,
}

/// Controller that manages state, physics smoothing, and intonation calculations
/// for the violin tuner and accuracy inspector.
class TunerController extends ChangeNotifier {
  TunerMode _activeMode;
  ViolinString? _selectedString;
  double _concertA4Hz;

  // Smoothing for bow pressure & tone smoothness visualizers
  double _smoothBowPressure = 0.5; // 0.0 = flautando/weak, 0.5 = ideal, 1.0 = scratch
  double _smoothStability = 0.0;   // 0.0 to 1.0 confidence/smoothness

  DetectedNoteInfo? _lastNote;

  TunerController({
    TunerMode initialMode = TunerMode.tuner,
    ViolinString? initialSelectedString,
    double initialConcertA4Hz = 440.0,
  })  : _activeMode = initialMode,
        _selectedString = initialSelectedString,
        _concertA4Hz = initialConcertA4Hz;

  // --- Getters ---

  TunerMode get activeMode => _activeMode;
  ViolinString? get selectedString => _selectedString;
  double get concertA4Hz => _concertA4Hz;
  double get smoothBowPressure => _smoothBowPressure;
  double get smoothStability => _smoothStability;
  DetectedNoteInfo? get lastNote => _lastNote;

  /// Sets the active tuner screen mode.
  void setActiveMode(TunerMode mode) {
    if (_activeMode != mode) {
      _activeMode = mode;
      notifyListeners();
    }
  }

  /// Sets or clears explicit target string.
  /// If [toggle] is true and [string] is already selected, clears to auto.
  void setSelectedString(ViolinString? string, {bool toggle = false}) {
    if (toggle && _selectedString == string) {
      _selectedString = null;
    } else {
      _selectedString = string;
    }
    notifyListeners();
  }

  /// Sets concert pitch calibration (440Hz, 442Hz, etc.).
  void setConcertA4Hz(double hz) {
    if ((_concertA4Hz - hz).abs() > 0.01) {
      _concertA4Hz = hz;
      notifyListeners();
    }
  }

  /// Toggles between standard 440 Hz and European orchestra 442 Hz.
  void toggleConcertA4Pitch() {
    final nextPitch = (_concertA4Hz - 440.0).abs() < 0.1 ? 442.0 : 440.0;
    setConcertA4Hz(nextPitch);
  }

  /// Updates physics metrics and intonation with the latest detected note.
  void updateWithNote(DetectedNoteInfo? note) {
    _lastNote = note;
    final isScratching = note?.isScratching ?? false;

    if (note != null && note.rawHz > 0) {
      if (isScratching) {
        _smoothBowPressure = _smoothBowPressure * 0.3 + 0.95 * 0.7;
      } else if (note.confidence < 0.65) {
        _smoothBowPressure = _smoothBowPressure * 0.5 + 0.25 * 0.5;
      } else {
        _smoothBowPressure = _smoothBowPressure * 0.4 + 0.52 * 0.6;
      }
      _smoothStability = _smoothStability * 0.35 + note.confidence.clamp(0.0, 1.0) * 0.65;
    } else {
      _smoothBowPressure = _smoothBowPressure * 0.85 + 0.40 * 0.15;
      _smoothStability = _smoothStability * 0.8;
    }

    notifyListeners();
  }

  // --- Computed Intonation Properties ---

  /// Effective string being tuned (either explicitly locked or closest open string).
  ViolinString get effectiveTunerString {
    if (_selectedString != null) {
      return _selectedString!;
    }
    final note = _lastNote;
    if (note != null && note.rawHz > 0) {
      return findClosestOpenString(note.rawHz, _concertA4Hz);
    }
    return ViolinString.a; // Standard A4 default
  }

  /// Target frequency for the active string in Tuner mode.
  double get tunerTargetHz => effectiveTunerString.openHz(_concertA4Hz);

  /// Target MIDI note for the active string in Tuner mode.
  int get tunerTargetMidi => effectiveTunerString.openMidi;

  /// Octave-invariant cents deviation relative to the target string.
  double get tunerCents {
    final note = _lastNote;
    if (note != null && note.rawHz > 0) {
      return calculateHarmonicCents(note.rawHz, tunerTargetHz);
    }
    return 0.0;
  }

  /// Whether the violin string is in tune (within ±5 cents tolerance).
  bool get isTunerInTune {
    return _lastNote != null && tunerCents.abs() <= 5.0;
  }

  /// Active cents deviation depending on the current mode.
  double get activeCents {
    return _activeMode == TunerMode.tuner ? tunerCents : (_lastNote?.cents ?? 0.0);
  }

  /// Whether current playing is in tune according to active mode.
  bool get activeInTune {
    return _activeMode == TunerMode.tuner ? isTunerInTune : (_lastNote?.isInTune ?? false);
  }

  /// Target MIDI note for the musical staff view.
  int? get activeStaffTargetMidi {
    return _activeMode == TunerMode.tuner ? tunerTargetMidi : _lastNote?.midiNote;
  }

  /// Played MIDI note for the musical staff view.
  int? get activeStaffPlayedMidi => _lastNote?.midiNote;

  /// Descriptive label for musical staff header.
  String get staffNoteLabel {
    final note = _lastNote;
    if (_activeMode == TunerMode.tuner) {
      if (note != null && note.rawHz > 0) {
        return 'Цель: ${effectiveTunerString.solfegeName} (${effectiveTunerString.name}) • Факт: ${note.rawHz.toStringAsFixed(1)} Hz';
      }
      return 'Цель: Струна ${effectiveTunerString.solfegeName} (${tunerTargetHz.toStringAsFixed(1)} Hz)';
    } else {
      if (note != null && note.rawHz > 0) {
        return '${note.solfegeName} / ${note.noteName} (${note.rawHz.toStringAsFixed(1)} Hz)';
      }
      return 'Сыграйте ноту для отображения на стане';
    }
  }

  /// Plays synthetic reference tone for the active target.
  void playActiveTargetTone(AudioEngine audioEngine) {
    final targetHz = _activeMode == TunerMode.tuner
        ? tunerTargetHz
        : (_lastNote?.targetHz ?? 440.0);
    audioEngine.playSyntheticNote(targetHz, 1.8);
  }

  /// Plays 440 Hz / calibrated A4 pure reference tone.
  void playConcertA4Tone(AudioEngine audioEngine) {
    audioEngine.playSyntheticNote(_concertA4Hz, 1.2);
  }

  // --- Static Mathematical Helpers ---

  /// Finds the closest open violin string allowing for octave harmonics.
  static ViolinString findClosestOpenString(double hz, double concertA4Hz) {
    ViolinString closest = ViolinString.a;
    double minHarmonicDistance = double.infinity;

    for (final str in ViolinString.inOrder) {
      final targetHz = str.openHz(concertA4Hz);
      final cents = calculateHarmonicCents(hz, targetHz).abs();
      if (cents < minHarmonicDistance) {
        minHarmonicDistance = cents;
        closest = str;
      }
    }
    return closest;
  }

  /// Calculates cents distance allowing 2nd and 3rd harmonics to align to fundamental.
  static double calculateHarmonicCents(double hz, double targetHz) {
    if (hz <= 0 || targetHz <= 0) return 0.0;
    double effective = hz;
    final ratio = hz / targetHz;

    if (ratio >= 1.88 && ratio <= 2.12) {
      effective = hz / 2.0; // Octave harmonic
    } else if (ratio >= 2.82 && ratio <= 3.18) {
      effective = hz / 3.0; // Twelfth harmonic
    } else if (ratio >= 0.47 && ratio <= 0.53) {
      effective = hz * 2.0; // Subharmonic
    }

    return MusicTheory.calculateCents(effective, targetHz).clamp(-100.0, 100.0);
  }
}
