import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import '../audio_engine.dart';
import '../music_theory.dart';
import '../services/settings_service.dart';

/// Central controller for real-time violin audio input and pitch tracking.
///
/// Encapsulates:
/// - AudioEngine lifecycle and isolate worker management
/// - Microphone control and OS permission handling
/// - Dynamic concert pitch calibration (A4 = 415..445 Hz)
/// - Logarithmic cents-distance smoothing (absorbs acoustic vibrato without latency on note shifts)
/// - Loopback feedback suppression during reference playback
class AudioRecognitionController extends ChangeNotifier {
  final AudioEngine _audioEngine;
  final SettingsService? _settings;

  StreamSubscription<PitchResult>? _pitchSub;
  final ValueNotifier<DetectedNoteInfo?> _noteNotifier = ValueNotifier<DetectedNoteInfo?>(null);

  bool _isInitialized = false;
  bool _isMicActive = false;
  double _concertA4Hz = 440.0;
  ViolinString? _selectedTunerString;

  DetectedNoteInfo? _currentNote;
  double _smoothedHz = 0.0;
  DateTime _lastNoteTime = DateTime.now();

  AudioRecognitionController({
    AudioEngine? audioEngine,
    SettingsService? settings,
  })  : _audioEngine = audioEngine ?? AudioEngine(),
        _settings = settings {
    if (settings != null) {
      _concertA4Hz = settings.concertA4Hz;
    }
  }

  // --- Public getters ---

  AudioEngine get audioEngine => _audioEngine;
  ValueNotifier<DetectedNoteInfo?> get noteNotifier => _noteNotifier;
  DetectedNoteInfo? get currentNote => _currentNote;
  bool get isMicActive => _isMicActive;
  bool get isInitialized => _isInitialized;
  double get concertA4Hz => _concertA4Hz;
  ViolinString? get selectedTunerString => _selectedTunerString;
  bool get isRunning => _audioEngine.isRunning;
  bool get isTonePlaying => _audioEngine.isTonePlaying;

  /// Initializes the audio engine, subscribes to pitch updates, and starts the microphone.
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      final stream = await _audioEngine.start();
      _pitchSub = stream.listen(_onPitchResult);

      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        await AudioEngine.ensureRecordAudioPermission();
      }

      final micStarted = _audioEngine.startMic();
      _isMicActive = micStarted;
      _isInitialized = true;
      notifyListeners();
    } catch (e) {
      debugPrint('AudioRecognitionController: initialization error: $e');
    }
  }

  /// Sets concert A4 pitch calibration (e.g. 440 Hz standard, 442 Hz European orchestra).
  void setConcertA4Hz(double hz) {
    if ((_concertA4Hz - hz).abs() > 0.01) {
      _concertA4Hz = hz;
      _settings?.setConcertA4Hz(hz);
      notifyListeners();
    }
  }

  /// Locks pitch analysis to an explicit target string for Tuner mode.
  void setSelectedTunerString(ViolinString? string) {
    if (_selectedTunerString != string) {
      _selectedTunerString = string;
      notifyListeners();
    }
  }

  /// Toggles microphone capture on / off.
  Future<bool> toggleMic([bool? enable]) async {
    final targetState = enable ?? !_isMicActive;
    if (targetState) {
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        final hasPermission = await AudioEngine.ensureRecordAudioPermission();
        if (!hasPermission) {
          _isMicActive = false;
          notifyListeners();
          return false;
        }
      }
      final ok = _audioEngine.startMic();
      _isMicActive = ok;
    } else {
      _audioEngine.stopMic();
      _isMicActive = false;
    }
    notifyListeners();
    return _isMicActive;
  }

  /// Plays a reference acoustic violin tone through speaker.
  void playTone(double frequencyHz, [double durationSec = 1.0]) {
    _audioEngine.playTone(frequencyHz, durationSec);
  }

  /// Silences reference tone playback.
  void stopTone() {
    _audioEngine.stopTone();
  }

  /// Plays PCM audio buffer.
  void playPcmBuffer(Float32List samples) {
    _audioEngine.playPcmBuffer(samples);
  }

  /// Internal handler for raw DSP pitch results.
  void _onPitchResult(PitchResult result) {
    // 1. Loopback suppression: do not analyze speaker feedback as student playing
    if (_audioEngine.isTonePlaying) {
      return;
    }

    final now = DateTime.now();

    // 2. Noise Floor & Silence filter:
    if (result.frequencyHz <= 0 || result.confidence < 0.38) {
      if (now.difference(_lastNoteTime).inMilliseconds > 180) {
        if (_currentNote != null || _noteNotifier.value != null) {
          _noteNotifier.value = null;
          _smoothedHz = 0.0;
          _currentNote = null;
          notifyListeners();
        }
      }
      return;
    }

    _lastNoteTime = now;

    // 3. Logarithmic cents distance filter for pitch stabilization:
    // Avoids resetting on small intervals in high registers, while immediately
    // responding to distinct note changes (> 75 cents) or initial onsets.
    double deltaCents = 999.0;
    if (_smoothedHz > 0.0 && result.frequencyHz > 0.0) {
      deltaCents = (1200.0 * (math.log(result.frequencyHz / _smoothedHz) / math.ln2)).abs();
    }

    if (_smoothedHz == 0.0 || deltaCents > 75.0) {
      _smoothedHz = result.frequencyHz;
    } else {
      // Smooth micro-pitch variations (vibrato and bow jitter) within the same note
      _smoothedHz = _smoothedHz * 0.30 + result.frequencyHz * 0.70;
    }

    // 4. Music theoretical analysis
    final note = MusicTheory.analyzePitch(
      _smoothedHz,
      result.confidence,
      result.isScratching,
      targetString: _selectedTunerString,
      concertA4Hz: _concertA4Hz,
    );

    _noteNotifier.value = note;
    _currentNote = note;
    notifyListeners();
  }

  @override
  void dispose() {
    _pitchSub?.cancel();
    _noteNotifier.dispose();
    _audioEngine.dispose();
    super.dispose();
  }
}
