import 'dart:math' as math;
import '../models/song_model.dart';
import '../music_theory.dart';

/// User preference for violin fingering and position calculation
enum FingeringPreference {
  /// Strictly 1st position (for beginners), only shifting when note exceeds 1st position range
  firstPositionOnly('1-я позиция (для начинающих)'),

  /// Intelligent balance between string crossings and ergonomic hand shifts (1st, 2nd, 3rd positions)
  balanced('Сбалансированный (1, 2, 3 поз.)'),

  /// Expressive violin cantilena: prefers stopped fingers and 3rd position for rich vibrato over open strings
  cantilena('Кантилена (вибрато, 3-я поз.)');

  final String label;
  const FingeringPreference(this.label);
}

/// Candidate state for a single note in the Viterbi fingering graph
class _FingeringState {
  final ViolinString string;
  final ViolinFinger finger;
  final int position;
  final double nodeCost;

  const _FingeringState({
    required this.string,
    required this.finger,
    required this.position,
    required this.nodeCost,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _FingeringState &&
          string == other.string &&
          finger == other.finger &&
          position == other.position;

  @override
  int get hashCode => Object.hash(string, finger, position);
}

/// Advanced algorithmic solver for violin fingering and left-hand position optimization.
/// Uses dynamic programming (Viterbi path search) to minimize shifts, awkward string crossings,
/// and unergonomic finger combinations according to Russian and European violin pedagogy.
class FingeringOptimizer {
  /// Optimizes fingering and positions for a list of notes
  static List<SongNote> optimizeNotes(
    List<SongNote> notes, {
    FingeringPreference preference = FingeringPreference.balanced,
    int maxPosition = 3,
  }) {
    if (notes.isEmpty) return notes;

    // Generate candidate states for each note
    final List<List<_FingeringState>> layers = [];

    for (int i = 0; i < notes.length; i++) {
      final note = notes[i];
      final candidates = _getCandidatesForNote(note.midiNote, preference, maxPosition);
      layers.add(candidates);
    }

    // Dynamic programming: Viterbi search
    // costTable[step][candidateIdx] = minimum accumulated cost to reach this state
    // backpointers[step][candidateIdx] = index in previous layer that gave min cost
    final List<List<double>> costTable = [];
    final List<List<int>> backpointers = [];

    // Initialize first layer
    final firstLayer = layers.first;
    final firstCosts = <double>[];
    for (final state in firstLayer) {
      firstCosts.add(state.nodeCost);
    }
    costTable.add(firstCosts);
    backpointers.add(List.filled(firstLayer.length, -1));

    // Forward pass
    for (int step = 1; step < notes.length; step++) {
      final prevNote = notes[step - 1];
      final curNote = notes[step];
      final prevLayer = layers[step - 1];
      final curLayer = layers[step];

      final currentCosts = List<double>.filled(curLayer.length, double.infinity);
      final currentBack = List<int>.filled(curLayer.length, 0);

      final timeGap = curNote.startTimeMs - prevNote.endTimeMs;
      final isSameSlur = curNote.isSlurred &&
          prevNote.isSlurred &&
          curNote.slurGroupId == prevNote.slurGroupId;

      for (int c = 0; c < curLayer.length; c++) {
        final curState = curLayer[c];
        double bestTotalCost = double.infinity;
        int bestPrevIdx = 0;

        for (int p = 0; p < prevLayer.length; p++) {
          final prevState = prevLayer[p];
          final prevCost = costTable[step - 1][p];

          final transitionCost = _calcTransitionCost(
            prevState,
            curState,
            timeGap: timeGap,
            isSameSlur: isSameSlur,
            prevNoteMidi: prevNote.midiNote,
            curNoteMidi: curNote.midiNote,
          );

          final total = prevCost + transitionCost + curState.nodeCost;
          if (total < bestTotalCost) {
            bestTotalCost = total;
            bestPrevIdx = p;
          }
        }

        currentCosts[c] = bestTotalCost;
        currentBack[c] = bestPrevIdx;
      }

      costTable.add(currentCosts);
      backpointers.add(currentBack);
    }

    // Find best final state
    int bestFinalIdx = 0;
    double minFinalCost = double.infinity;
    final lastCosts = costTable.last;
    for (int c = 0; c < lastCosts.length; c++) {
      if (lastCosts[c] < minFinalCost) {
        minFinalCost = lastCosts[c];
        bestFinalIdx = c;
      }
    }

    // Backtrack path
    final List<_FingeringState> optimalPath = List.filled(notes.length, layers.last[bestFinalIdx]);
    int currentIdx = bestFinalIdx;
    for (int step = notes.length - 1; step >= 0; step--) {
      optimalPath[step] = layers[step][currentIdx];
      if (step > 0) {
        currentIdx = backpointers[step][currentIdx];
      }
    }

    // Build optimized notes
    final result = <SongNote>[];
    for (int i = 0; i < notes.length; i++) {
      final orig = notes[i];
      final state = optimalPath[i];

      result.add(orig.copyWith(
        string: state.string,
        finger: state.finger,
        position: state.position,
      ));
    }

    return result;
  }

  /// Optimizes all notes inside a Song
  static Song optimizeSong(
    Song song, {
    FingeringPreference preference = FingeringPreference.balanced,
    int maxPosition = 3,
  }) {
    final optimized = optimizeNotes(song.notes, preference: preference, maxPosition: maxPosition);
    return Song(
      id: song.id,
      title: song.title,
      composer: song.composer,
      tempoBpm: song.tempoBpm,
      notes: optimized,
    );
  }

  /// Finds the best single-note fingering option without sequential context
  static (ViolinString, ViolinFinger, int) getBestSingleNoteFingering(
    int midiNote, {
    int preferredPosition = 1,
  }) {
    final candidates = MusicTheory.getCandidatesForMidi(midiNote, maxPosition: 3);
    if (candidates.isEmpty) {
      return (ViolinString.a, ViolinFinger.first, 1);
    }

    // Prefer candidate matching preferredPosition
    for (final c in candidates) {
      if (c.position == preferredPosition) {
        return (c.string, c.finger, c.position);
      }
    }

    // Default to first available candidate (sorted by position)
    candidates.sort((a, b) => a.position.compareTo(b.position));
    final best = candidates.first;
    return (best.string, best.finger, best.position);
  }

  // --- Private Helpers ---

  static List<_FingeringState> _getCandidatesForNote(
    int midiNote,
    FingeringPreference preference,
    int maxPosition,
  ) {
    final rawCandidates = MusicTheory.getCandidatesForMidi(midiNote, maxPosition: maxPosition);
    final states = <_FingeringState>[];

    final isHighNote = midiNote > 83; // Above B5 (requires pos 3+)

    for (final c in rawCandidates) {
      // If user strictly requested 1st position only, discard pos > 1 unless note is too high
      if (preference == FingeringPreference.firstPositionOnly && !isHighNote && c.position > 1) {
        continue;
      }

      double cost = 0.0;

      // Position bias
      switch (c.position) {
        case 1:
          cost += 0.0;
          break;
        case 3:
          cost += (preference == FingeringPreference.cantilena) ? 0.0 : 1.5;
          break;
        case 2:
          cost += 4.0; // 2nd position used when specifically convenient
          break;
        default:
          cost += 8.0;
      }

      // High register requirements
      if (isHighNote) {
        if (c.position == 1) {
          cost += 80.0; // Heavily penalize 1st position for notes above B5
        } else if (c.position == 3) {
          cost -= 5.0; // Encourage 3rd position for high register
        }
      }

      // Open string vs Stopped finger evaluation
      if (c.finger == ViolinFinger.open) {
        if (preference == FingeringPreference.cantilena && c.string != ViolinString.g) {
          // Open string cannot produce vibrato in cantilena
          cost += 15.0;
        } else {
          cost += 0.5;
        }
      } else if (c.finger == ViolinFinger.fourth) {
        if (preference == FingeringPreference.cantilena) {
          cost += 0.0; // 4th finger allows vibrato, good for cantilena
        } else {
          cost += 1.0; // Pinky is slightly weaker in 1st position
        }
      }

      states.add(_FingeringState(
        string: c.string,
        finger: c.finger,
        position: c.position,
        nodeCost: cost,
      ));
    }

    if (states.isEmpty) {
      // Failsafe fallback
      states.add(const _FingeringState(
        string: ViolinString.e,
        finger: ViolinFinger.first,
        position: 1,
        nodeCost: 100.0,
      ));
    }

    return states;
  }

  static double _calcTransitionCost(
    _FingeringState prev,
    _FingeringState cur, {
    required int timeGap,
    required bool isSameSlur,
    required int prevNoteMidi,
    required int curNoteMidi,
  }) {
    double cost = 0.0;

    // 1. Shift Cost (Changing left-hand position)
    final shiftDistance = (cur.position - prev.position).abs();
    if (shiftDistance > 0) {
      double baseShift = shiftDistance * 12.0;

      // Shifts between I and III are idiomatic and natural (heel pivot)
      if ((prev.position == 1 && cur.position == 3) ||
          (prev.position == 3 && cur.position == 1)) {
        baseShift *= 0.8;
      }

      // Open string shift discount: during an open string, the hand is completely free to shift
      if (prev.finger == ViolinFinger.open) {
        baseShift *= 0.2; // 80% discount
      } else if (timeGap >= 180) {
        // Generous pause/rest allows clean hand repositioning
        baseShift *= 0.4; // 60% discount
      }

      // Shifting under a legato slur is penalized (causes audible unwanted portamento)
      if (isSameSlur) {
        baseShift += 15.0;
      }

      cost += baseShift;
    }

    // 2. String Crossing Cost (Right-hand bow level change)
    final stringGap = (cur.string.order - prev.string.order).abs();
    switch (stringGap) {
      case 0:
        // Staying on same string is rewarded under slur
        if (isSameSlur) {
          cost -= 4.0;
        }
        break;
      case 1:
        // Adjacent string crossing is normal
        cost += isSameSlur ? 4.0 : 2.0;
        break;
      case 2:
        // Skipping a string (e.g. G to A, or D to E) is awkward
        cost += isSameSlur ? 20.0 : 12.0;
        break;
      case 3:
      default:
        // Skipping 2 strings (e.g. G to E) is very abrupt
        cost += 35.0;
        break;
    }

    // 3. Left-hand ergonomics & finger transitions
    if (prev.string == cur.string) {
      if (prev.finger == cur.finger && prev.position != cur.position) {
        // Sliding the same finger along the same string is clumsy
        cost += 18.0;
      }

      // Natural finger order for stepwise melodic movement
      if (curNoteMidi > prevNoteMidi && cur.finger.number > prev.finger.number) {
        cost -= 1.5; // Upward scalar motion with consecutive fingers
      } else if (curNoteMidi < prevNoteMidi && cur.finger.number < prev.finger.number) {
        cost -= 1.5; // Downward scalar motion with consecutive fingers
      }
    }

    return math.max(0.0, cost);
  }
}
