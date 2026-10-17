import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import '../audio_engine.dart';
import '../music_theory.dart';

/// Controller managing scale selection, practice progression, note hold matching,
/// reference tone playback, and streak tracking for the violin scale trainer.
class TrainerController extends ChangeNotifier {
  static final List<ViolinScaleDef> allScales = ScaleGenerator.all24Scales;

  final AudioEngine _audioEngine;

  TonalityDef _selectedTonality;
  late ViolinScaleDef _currentScale;
  int _selectedScaleIndex = 0;
  int _currentStepIndex = 0;

  double _holdProgress = 0.0;
  int _streak = 0;
  String _trainMode = 'fixed';
  bool _showCircleOfFifths = false;

  bool _isReferencePlaying = false;
  Timer? _referenceTimer;
  bool _isFullScalePlaying = false;
  Timer? _fullScaleTimer;
  Timer? _tickTimer;

  TrainerController({
    AudioEngine? audioEngine,
    TonalityDef initialTonality = const TonalityDef(
      position: CirclePosition.pos2, // D Major
      mode: TonalityMode.major,
    ),
    int initialStreak = 0,
  })  : _audioEngine = audioEngine ?? AudioEngine(),
        _selectedTonality = initialTonality,
        _streak = initialStreak {
    _currentScale = ScaleGenerator.generateScale(_selectedTonality);
    _selectedScaleIndex = allScales.indexWhere((s) => s.tonality == _selectedTonality);
    if (_selectedScaleIndex < 0) _selectedScaleIndex = 0;
  }

  // --- Getters ---

  AudioEngine get audioEngine => _audioEngine;
  TonalityDef get selectedTonality => _selectedTonality;
  ViolinScaleDef get currentScale => _currentScale;
  int get selectedScaleIndex => _selectedScaleIndex;
  int get currentStepIndex => _currentStepIndex;
  ScaleNoteStep get currentStep => _currentScale.steps[_currentStepIndex];

  double get holdProgress => _holdProgress;
  int get streak => _streak;
  String get trainMode => _trainMode;
  bool get showCircleOfFifths => _showCircleOfFifths;
  bool get isReferencePlaying => _isReferencePlaying;
  bool get isFullScalePlaying => _isFullScalePlaying;

  /// Starts periodic tick loop to evaluate user note input (50ms interval).
  void startProgressTracking(ValueNotifier<DetectedNoteInfo?>? noteNotifier, [DetectedNoteInfo? Function()? noteGetter]) {
    _tickTimer?.cancel();
    _tickTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      final note = noteNotifier?.value ?? noteGetter?.call();
      processTick(note);
    });
  }

  /// Stops periodic tick evaluation.
  void stopProgressTracking() {
    _tickTimer?.cancel();
    _tickTimer = null;
  }

  /// Evaluates an incoming audio note against the current target step in the scale.
  void processTick(DetectedNoteInfo? note) {
    if (_isReferencePlaying || _isFullScalePlaying) {
      return;
    }

    if (note == null) {
      if (_holdProgress > 0) {
        _holdProgress = math.max(0.0, _holdProgress - 0.04);
        notifyListeners();
      }
      return;
    }

    final isCorrectNote = note.midiNote == currentStep.midiNote;
    final isCleanBowing = !note.isScratching && note.isInTune;

    if (isCorrectNote && isCleanBowing) {
      _holdProgress = math.min(1.0, _holdProgress + 0.08);
      if (_holdProgress >= 1.0) {
        _holdProgress = 0.0;
        _streak++;
        nextStep();
      } else {
        notifyListeners();
      }
    } else {
      if (_holdProgress > 0) {
        _holdProgress = math.max(0.0, _holdProgress - 0.03);
        notifyListeners();
      }
    }
  }

  /// Advances to next scale step.
  void nextStep() {
    _stopFullScale();
    _referenceTimer?.cancel();
    _isReferencePlaying = false;
    _holdProgress = 0.0;
    _currentStepIndex = (_currentStepIndex + 1) % _currentScale.steps.length;
    notifyListeners();
  }

  /// Moves to previous scale step.
  void prevStep() {
    _stopFullScale();
    _referenceTimer?.cancel();
    _isReferencePlaying = false;
    _holdProgress = 0.0;
    _currentStepIndex = (_currentStepIndex - 1 + _currentScale.steps.length) % _currentScale.steps.length;
    notifyListeners();
  }

  /// Sets specific scale step index directly.
  void setStepIndex(int index) {
    if (index >= 0 && index < _currentScale.steps.length && _currentStepIndex != index) {
      _stopFullScale();
      _referenceTimer?.cancel();
      _isReferencePlaying = false;
      _currentStepIndex = index;
      _holdProgress = 0.0;
      notifyListeners();
    }
  }

  /// Plays single reference note for current step.
  void playSingleReference() {
    _stopFullScale();
    _referenceTimer?.cancel();
    _isReferencePlaying = true;
    _holdProgress = 0.0;
    notifyListeners();

    _audioEngine.playTone(currentStep.targetHz, 1.2);
    _referenceTimer = Timer(const Duration(milliseconds: 1350), () {
      _isReferencePlaying = false;
      notifyListeners();
    });
  }

  /// Plays all steps of the scale sequentially.
  void playFullScale() {
    if (_isFullScalePlaying) {
      _stopFullScale();
      return;
    }

    _referenceTimer?.cancel();
    _isReferencePlaying = false;
    _isFullScalePlaying = true;
    _currentStepIndex = 0;
    _holdProgress = 0.0;
    notifyListeners();

    int step = 0;
    const noteDurationMs = 650;

    void playStep() {
      if (!_isFullScalePlaying) return;
      if (step >= _currentScale.steps.length) {
        _stopFullScale();
        return;
      }
      _currentStepIndex = step;
      notifyListeners();

      final note = _currentScale.steps[step];
      _audioEngine.playTone(note.targetHz, 0.60);

      step++;
      _fullScaleTimer = Timer(const Duration(milliseconds: noteDurationMs), playStep);
    }

    playStep();
  }

  void _stopFullScale() {
    _fullScaleTimer?.cancel();
    if (_isFullScalePlaying) {
      _isFullScalePlaying = false;
      notifyListeners();
    }
  }

  /// Selects a new tonality (from Circle of Fifths).
  void selectTonality(TonalityDef tonality) {
    _stopFullScale();
    _referenceTimer?.cancel();
    _isReferencePlaying = false;
    _selectedTonality = tonality;
    _currentScale = ScaleGenerator.generateScale(tonality);
    _selectedScaleIndex = allScales.indexWhere((s) => s.tonality == tonality);
    if (_selectedScaleIndex < 0) _selectedScaleIndex = 0;
    _currentStepIndex = 0;
    _holdProgress = 0.0;
    notifyListeners();
  }

  /// Selects scale by index in allScales list.
  void selectScale(int index) {
    if (index < 0 || index >= allScales.length) return;
    _stopFullScale();
    _referenceTimer?.cancel();
    _isReferencePlaying = false;
    final scale = allScales[index];
    if (scale.tonality != null) {
      selectTonality(scale.tonality!);
    } else {
      _selectedScaleIndex = index;
      _currentScale = scale;
      _currentStepIndex = 0;
      _holdProgress = 0.0;
      notifyListeners();
    }
  }

  /// Sets practice mode (fixed, accel, slur, split, skip, random).
  void setTrainMode(String mode) {
    if (_trainMode != mode) {
      _trainMode = mode;
      notifyListeners();
    }
  }

  /// Toggles visibility of Circle of Fifths picker.
  void toggleCircleOfFifths([bool? show]) {
    _showCircleOfFifths = show ?? !_showCircleOfFifths;
    notifyListeners();
  }

  @override
  void dispose() {
    stopProgressTracking();
    _referenceTimer?.cancel();
    _fullScaleTimer?.cancel();
    super.dispose();
  }
}
