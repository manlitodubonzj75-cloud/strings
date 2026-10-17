import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import '../audio_engine.dart';
import '../models/song_model.dart';
import '../services/midi_parser.dart';
import '../music_theory.dart';
import '../services/ddsp_violin_synthesizer.dart';
import '../services/score_edit_controller.dart';
import '../services/song_audio_generator.dart';

enum PracticeMode {
  waitNote,
  playAlong,
}

enum RepertoireCategory {
  all,
  classical,
  suzuki,
  custom,
}

/// Controller managing song practice, real-time intonation evaluation,
/// DDSP neural demo playback, scoring, and rehearsal loops.
class SongPracticeController extends ChangeNotifier {
  final AudioEngine _audioEngine;
  late ScoreEditController _scoreController;

  List<Song> _availableSongs;
  late Song _currentSong;
  RepertoireCategory _selectedCategory = RepertoireCategory.all;

  PracticeMode _practiceMode = PracticeMode.waitNote;
  bool _isPlaying = false;
  bool _isSoundError = false;
  String _soundErrorMessage = '';
  String? _legatoFeedback;
  bool _isAccompanimentOn = true;

  double _playbackSpeed = 1.0;
  static const List<double> speedOptions = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

  int _currentNoteIndex = 0;
  int _playbackTimeMs = 0;
  Timer? _playbackTimer;

  bool _isDemoPlaying = false;
  bool _isDemoPaused = false;
  Timer? _demoTimer;
  Stopwatch? _demoStopwatch;
  int _demoFromMs = 0;
  int _nextNoteIndex = 0;

  bool _isRenderingDdsp = false;
  String _ddspStatus = '';
  double _ddspProgress = 0.0;
  Float32List? _cachedDdspPcm;
  String? _cachedDdspSongId;
  double? _cachedDdspSpeed;

  int _score = 0;
  int _streak = 0;
  int _bestStreak = 0;
  DateTime _lastHitTime = DateTime.fromMillisecondsSinceEpoch(0);

  SongPracticeController({
    AudioEngine? audioEngine,
    ScoreEditController? scoreController,
    List<Song>? availableSongs,
    Song? initialSong,
  })  : _audioEngine = audioEngine ?? AudioEngine(),
        _availableSongs = availableSongs ?? SongLibrary.builtinSongs {
    _currentSong = initialSong ?? (_availableSongs.isNotEmpty ? _availableSongs.first : SongLibrary.builtinSongs.first);
    _scoreController = scoreController ?? ScoreEditController(initialSong: _currentSong);
    _scoreController.addListener(_onScoreControllerChanged);
  }

  // --- Getters ---

  AudioEngine get audioEngine => _audioEngine;
  ScoreEditController get scoreController => _scoreController;
  List<Song> get availableSongs => _availableSongs;
  Song get currentSong => _currentSong;
  RepertoireCategory get selectedCategory => _selectedCategory;
  PracticeMode get practiceMode => _practiceMode;
  bool get isPlaying => _isPlaying;
  bool get isDemoPlaying => _isDemoPlaying;
  bool get isDemoPaused => _isDemoPaused;
  bool get isSoundError => _isSoundError;
  String get soundErrorMessage => _soundErrorMessage;
  String? get legatoFeedback => _legatoFeedback;
  bool get isAccompanimentOn => _isAccompanimentOn;
  double get playbackSpeed => _playbackSpeed;

  int get currentNoteIndex => _currentNoteIndex;
  int get playbackTimeMs => _playbackTimeMs;
  int get score => _score;
  int get streak => _streak;
  int get bestStreak => _bestStreak;

  bool get isRenderingDdsp => _isRenderingDdsp;
  String get ddspStatus => _ddspStatus;
  double get ddspProgress => _ddspProgress;

  void _onScoreControllerChanged() {
    if (_currentSong != _scoreController.song) {
      _currentSong = _scoreController.song;
      _cachedDdspPcm = null;
      notifyListeners();
    }
  }

  /// Sets practice mode (waitNote or playAlong).
  void setPracticeMode(PracticeMode mode) {
    if (_practiceMode != mode) {
      _practiceMode = mode;
      resetPractice();
    }
  }

  /// Toggles accompaniment flag.
  void toggleAccompaniment() {
    _isAccompanimentOn = !_isAccompanimentOn;
    notifyListeners();
  }

  /// Cycles playback speed (0.5x -> 0.75x -> 1.0x -> 1.25x -> 1.5x -> 2.0x).
  void cyclePlaybackSpeed() {
    final idx = speedOptions.indexOf(_playbackSpeed);
    final nextIdx = (idx + 1) % speedOptions.length;
    _playbackSpeed = speedOptions[nextIdx];
    if (_isDemoPlaying && !_isDemoPaused) {
      resumeDemo();
    } else {
      notifyListeners();
    }
  }

  /// Selects a song and re-initializes practice score.
  void selectSong(Song song) {
    _currentSong = song;
    _scoreController.setSong(song);
    _cachedDdspPcm = null;
    resetPractice();
  }

  /// Sets repertoire category filter.
  void selectCategory(RepertoireCategory category) {
    if (_selectedCategory != category) {
      _selectedCategory = category;
      notifyListeners();
    }
  }

  /// Updates available song list.
  void setAvailableSongs(List<Song> songs) {
    _availableSongs = songs;
    notifyListeners();
  }

  /// Resets practice state and stops timers.
  void resetPractice() {
    _playbackTimer?.cancel();
    _demoTimer?.cancel();
    _demoStopwatch?.stop();
    _audioEngine.stopTone();
    _cachedDdspPcm = null;

    _isDemoPlaying = false;
    _isDemoPaused = false;
    _isPlaying = false;
    _isSoundError = false;
    _soundErrorMessage = '';
    _legatoFeedback = null;
    _currentNoteIndex = 0;
    _playbackTimeMs = 0;
    _score = 0;
    _streak = 0;
    _lastHitTime = DateTime.fromMillisecondsSinceEpoch(0);
    for (final n in _currentSong.notes) {
      n.isHit = false;
    }
    notifyListeners();
  }

  /// Starts live practice playback (student plays into microphone).
  void startPlayback({VoidCallback? onComplete}) {
    _demoTimer?.cancel();
    _isDemoPlaying = false;
    _isPlaying = true;
    _isSoundError = false;
    _legatoFeedback = null;
    notifyListeners();

    if (_practiceMode == PracticeMode.playAlong) {
      _playbackTimer = Timer.periodic(const Duration(milliseconds: 20), (_) {
        if (!_isSoundError) {
          _playbackTimeMs += (20 * _playbackSpeed).round();

          if (_scoreController.loopRange.isEnabled) {
            final loopEnd = _scoreController.loopRange.getEndTimeMs(_scoreController.measures);
            final loopStart = _scoreController.loopRange.getStartTimeMs(_scoreController.measures);
            if (_playbackTimeMs >= loopEnd) {
              _playbackTimeMs = loopStart;
              int idx = 0;
              while (idx < _currentSong.notes.length && _currentSong.notes[idx].startTimeMs < loopStart) {
                idx++;
              }
              _currentNoteIndex = idx.clamp(0, _currentSong.notes.length - 1);
            }
          }

          // Advance note cursor dynamically with playback time so high-tempo notes are never lagged
          while (_currentNoteIndex < _currentSong.notes.length - 1 &&
              _playbackTimeMs >= _currentSong.notes[_currentNoteIndex].startTimeMs + _currentSong.notes[_currentNoteIndex].durationMs) {
            _currentNoteIndex++;
          }

          if (_playbackTimeMs >= _currentSong.totalDurationMs) {
            _playbackTimer?.cancel();
            _isPlaying = false;
            onComplete?.call();
          }

          notifyListeners();
        }
      });
    }
  }

  void pausePlayback() {
    _playbackTimer?.cancel();
    _isPlaying = false;
    notifyListeners();
  }

  // --- Neural DDSP Synthesized Demo Playback ---

  Future<void> startDemo({int fromMs = 0}) async {
    if (_isRenderingDdsp) return;

    _playbackTimer?.cancel();
    _demoTimer?.cancel();
    _demoStopwatch?.stop();
    _audioEngine.stopTone();

    final clampedFromMs = fromMs.clamp(0, _currentSong.totalDurationMs);
    _demoFromMs = clampedFromMs;

    // Pre-render entire score using Neural DDSP
    if (_cachedDdspPcm == null ||
        _cachedDdspSongId != _currentSong.id ||
        _cachedDdspSpeed != _playbackSpeed) {
      _isRenderingDdsp = true;
      _ddspProgress = 0.05;
      _ddspStatus = 'Загрузка ИИ-нейросети DDSP (Bach Violin)...';
      notifyListeners();

      try {
        final pcm = await DdspViolinSynthesizer.synthesizeSong(
          _currentSong,
          speedMultiplier: _playbackSpeed,
          onProgress: (p, s) {
            _ddspProgress = p;
            _ddspStatus = s;
            notifyListeners();
          },
        );
        _cachedDdspPcm = pcm;
        _cachedDdspSongId = _currentSong.id;
        _cachedDdspSpeed = _playbackSpeed;
      } catch (_) {
        _cachedDdspPcm = SongAudioGenerator.generatePcm(
          _currentSong,
          sampleRate: 44100,
          speedMultiplier: _playbackSpeed,
          addHarmonics: true,
          addVibrato: true,
          addMeasureDynamics: true,
        );
        _cachedDdspSongId = _currentSong.id;
        _cachedDdspSpeed = _playbackSpeed;
      } finally {
        _isRenderingDdsp = false;
        notifyListeners();
      }
    }

    final fullPcm = _cachedDdspPcm!;
    final timeDilation = 1.0 / _playbackSpeed.clamp(0.1, 4.0);
    final startSec = (clampedFromMs * timeDilation) / 1000.0;
    final startSample = (startSec * 44100).round().clamp(0, fullPcm.length);
    final pcmSamples = (startSample == 0)
        ? fullPcm
        : Float32List.sublistView(fullPcm, startSample);

    _audioEngine.playPcmBuffer(pcmSamples);
    _demoStopwatch = Stopwatch()..start();

    _nextNoteIndex = 0;
    while (_nextNoteIndex < _currentSong.notes.length &&
        _currentSong.notes[_nextNoteIndex].startTimeMs < clampedFromMs) {
      _nextNoteIndex++;
    }

    int initialActiveIdx = 0;
    for (int i = 0; i < _currentSong.notes.length; i++) {
      final n = _currentSong.notes[i];
      if (clampedFromMs >= n.startTimeMs && clampedFromMs < n.startTimeMs + n.durationMs) {
        initialActiveIdx = i;
        break;
      }
    }

    _isPlaying = false;
    _isDemoPlaying = true;
    _isDemoPaused = false;
    _isSoundError = false;
    _soundErrorMessage = '';
    _currentNoteIndex = initialActiveIdx;
    _playbackTimeMs = clampedFromMs;
    notifyListeners();

    _demoTimer = Timer.periodic(const Duration(milliseconds: 16), (timer) {
      if (!_isDemoPlaying) {
        timer.cancel();
        return;
      }
      if (_isDemoPaused) return;

      final elapsedMs = _demoStopwatch?.elapsedMilliseconds ?? 0;
      final currentTime = _demoFromMs + (elapsedMs * _playbackSpeed).round();

      if (_scoreController.loopRange.isEnabled) {
        final loopEnd = _scoreController.loopRange.getEndTimeMs(_scoreController.measures);
        final loopStart = _scoreController.loopRange.getStartTimeMs(_scoreController.measures);
        if (currentTime >= loopEnd) {
          startDemo(fromMs: loopStart);
          return;
        }
      }

      while (_nextNoteIndex < _currentSong.notes.length) {
        final note = _currentSong.notes[_nextNoteIndex];
        if (note.startTimeMs <= currentTime) {
          _currentNoteIndex = _nextNoteIndex;
          _nextNoteIndex++;
        } else {
          break;
        }
      }

      _playbackTimeMs = currentTime;
      if (_playbackTimeMs >= _currentSong.totalDurationMs + 400) {
        stopDemo();
      } else {
        notifyListeners();
      }
    });
  }

  void pauseDemo() {
    _demoTimer?.cancel();
    _demoStopwatch?.stop();
    _audioEngine.stopTone();
    _isDemoPaused = true;
    notifyListeners();
  }

  void resumeDemo() {
    startDemo(fromMs: _playbackTimeMs);
  }

  void seekDemo(int targetMs) {
    _audioEngine.stopTone();
    final clamped = targetMs.clamp(0, _currentSong.totalDurationMs);
    if (_isDemoPlaying) {
      startDemo(fromMs: clamped);
    } else {
      _playbackTimeMs = clamped;
      for (int i = 0; i < _currentSong.notes.length; i++) {
        final n = _currentSong.notes[i];
        if (clamped >= n.startTimeMs && clamped < n.startTimeMs + n.durationMs) {
          _currentNoteIndex = i;
          break;
        }
      }
      notifyListeners();
    }
  }

  void stopDemo() {
    _demoTimer?.cancel();
    _demoStopwatch?.stop();
    _audioEngine.stopTone();
    _isDemoPlaying = false;
    _isDemoPaused = false;
    _playbackTimeMs = 0;
    _currentNoteIndex = 0;
    notifyListeners();
  }

  // --- Note Recognition & Scoring ---

  /// Evaluates student's note from microphone.
  void checkIncomingNote(
    DetectedNoteInfo note, {
    PitchResult? lastPitchResult,
    VoidCallback? onComplete,
  }) {
    if (!_isPlaying || _isDemoPlaying) return;

    if (_practiceMode == PracticeMode.waitNote) {
      if (_currentNoteIndex < _currentSong.notes.length) {
        _checkWaitNoteHit(
          _currentSong.notes[_currentNoteIndex],
          note,
          lastPitchResult: lastPitchResult,
          onComplete: onComplete,
        );
      }
    } else if (_practiceMode == PracticeMode.playAlong) {
      _checkPlayAlongHit(note, lastPitchResult: lastPitchResult);
    }
  }

  void _checkWaitNoteHit(
    SongNote targetNote,
    DetectedNoteInfo note, {
    PitchResult? lastPitchResult,
    VoidCallback? onComplete,
  }) {
    if (note.isScratching) {
      _isSoundError = true;
      _soundErrorMessage = '⚠️ Скрип смычка: звук заблокирован. Ослабьте нажим смычка!';
      _streak = 0;
      notifyListeners();
      return;
    }

    final semitoneDiff = (note.midiNote - targetNote.midiNote).abs();
    final isPitchClassMatch = (semitoneDiff % 12) == 0;

    final targetHz = MusicTheory.midiToHz(targetNote.midiNote);
    final rawCents = MusicTheory.calculateCents(note.rawHz, targetHz);
    final octaveOffset = (rawCents / 1200.0).round();
    final intonationCents = rawCents - (octaveOffset * 1200.0);

    if (!isPitchClassMatch) {
      final semitoneMod = (note.midiNote - targetNote.midiNote) % 12;
      final isNearHalfStep = (semitoneMod == 1 || semitoneMod == 11);
      final isFlat = (semitoneMod == 11);
      _isSoundError = true;
      _soundErrorMessage = isNearHalfStep
          ? (isFlat ? "Палец низит на полутон" : "Палец высит на полутон")
          : "Неверная нота (${note.solfegeName} вместо ${MusicTheory.midiToSolfege(targetNote.midiNote)})";
      notifyListeners();
      return;
    }

    if (intonationCents.abs() > 35.0) {
      final isFlat = intonationCents < 0;
      _isSoundError = true;
      _soundErrorMessage = isFlat
          ? "Палец низит (${intonationCents.toStringAsFixed(0)}¢). Сдвиньте к подставке"
          : "Палец высит (+${intonationCents.toStringAsFixed(0)}¢). Сдвиньте к колкам";
      notifyListeners();
      return;
    }

    final now = DateTime.now();
    // Fast 40ms debounce prevents double-triggers without eating rapid sixteenth/thirty-second notes
    if (now.difference(_lastHitTime).inMilliseconds < 40) return;
    _lastHitTime = now;

    int bonus = 100;
    String? slurMsg;

    if (targetNote.isSlurred && (lastPitchResult?.isLegato == true || _audioEngine.lastPitchResult?.isLegato == true)) {
      bonus += 250;
      slurMsg = '✨ Чистое легато на один смычок! (+250)';
    }

    _isSoundError = false;
    _soundErrorMessage = '';
    _legatoFeedback = slurMsg;
    targetNote.isHit = true;
    _score += bonus;
    _streak++;
    if (_streak > _bestStreak) _bestStreak = _streak;

    if (_scoreController.loopRange.isEnabled) {
      final loopEnd = _scoreController.loopRange.getEndTimeMs(_scoreController.measures);
      final loopStart = _scoreController.loopRange.getStartTimeMs(_scoreController.measures);
      if (_currentNoteIndex < _currentSong.notes.length - 1) {
        final nextNote = _currentSong.notes[_currentNoteIndex + 1];
        if (nextNote.startTimeMs >= loopEnd) {
          int firstNote = 0;
          while (firstNote < _currentSong.notes.length &&
              _currentSong.notes[firstNote].startTimeMs < loopStart) {
            firstNote++;
          }
          _currentNoteIndex = firstNote.clamp(0, _currentSong.notes.length - 1);
        } else {
          _currentNoteIndex++;
        }
      } else {
        onComplete?.call();
      }
    } else {
      if (_currentNoteIndex < _currentSong.notes.length - 1) {
        _currentNoteIndex++;
      } else {
        onComplete?.call();
      }
    }

    notifyListeners();
  }

  void _checkPlayAlongHit(
    DetectedNoteInfo note, {
    PitchResult? lastPitchResult,
  }) {
    if (_currentNoteIndex >= _currentSong.notes.length) return;
    final targetNote = _currentSong.notes[_currentNoteIndex];

    if (_playbackTimeMs >= targetNote.startTimeMs + targetNote.durationMs) {
      if (_currentNoteIndex < _currentSong.notes.length - 1) {
        _currentNoteIndex++;
        _isSoundError = false;
        _soundErrorMessage = '';
        _legatoFeedback = null;
        notifyListeners();
      }
      return;
    }

    if (note.isScratching) {
      _isSoundError = true;
      _soundErrorMessage = '⚠️ Скрип канифоли! Пьеса приостановлена.';
      notifyListeners();
      return;
    }

    final semitoneDiff = (note.midiNote - targetNote.midiNote).abs();
    final isPitchClassMatch = (semitoneDiff % 12) == 0;
    final targetHz = MusicTheory.midiToHz(targetNote.midiNote);
    final rawCents = MusicTheory.calculateCents(note.rawHz, targetHz);
    final octaveOffset = (rawCents / 1200.0).round();
    final intonationCents = rawCents - (octaveOffset * 1200.0);
    final matchesTarget = isPitchClassMatch && (intonationCents.abs() <= 35.0);

    if (matchesTarget) {
      if (!targetNote.isHit) {
        int bonus = 100;
        String? slurMsg;
        if (targetNote.isSlurred && (lastPitchResult?.isLegato == true || _audioEngine.lastPitchResult?.isLegato == true)) {
          bonus += 250;
          slurMsg = '✨ Чистое легато на один смычок!';
        }
        targetNote.isHit = true;
        _score += bonus;
        _streak++;
        _isSoundError = false;
        _soundErrorMessage = '';
        _legatoFeedback = slurMsg;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _playbackTimer?.cancel();
    _demoTimer?.cancel();
    _demoStopwatch?.stop();
    _scoreController.removeListener(_onScoreControllerChanged);
    super.dispose();
  }
}
