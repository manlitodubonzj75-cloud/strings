import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../models/score_editor_contracts.dart';
import '../../models/song_model.dart';
import '../../music_theory.dart';

/// Interactive multi-measure score view rendered natively on Canvas.
/// Supports measure partitioning, continuous cursor tracking, loop highlights,
/// beautiful slur arcs, violin bow symbols, automatic violin fingering, position labels,
/// and tap selection for notes & measures.
class MultiMeasureScoreView extends StatefulWidget {
  final List<ScoreMeasure> measures;
  final ScoreLoopRange loopRange;
  final int? currentNoteIndex;
  final int? targetMidi;
  final int? playedMidi;
  final bool isInTune;
  final bool isScratching;
  final int? selectedNoteIndex;
  final int? selectedMeasureIndex;
  final Function(int noteIndex)? onNoteTapped;
  final Function(int measureNumber)? onMeasureTapped;
  final double staffHeight;
  final double measureWidth;
  final bool showFingering;
  final bool showPositions;

  const MultiMeasureScoreView({
    super.key,
    required this.measures,
    required this.loopRange,
    this.currentNoteIndex,
    this.targetMidi,
    this.playedMidi,
    this.isInTune = false,
    this.isScratching = false,
    this.selectedNoteIndex,
    this.selectedMeasureIndex,
    this.onNoteTapped,
    this.onMeasureTapped,
    this.staffHeight = 160.0,
    this.measureWidth = 240.0,
    this.showFingering = true,
    this.showPositions = true,
  });

  @override
  State<MultiMeasureScoreView> createState() => _MultiMeasureScoreViewState();
}

class _MultiMeasureScoreViewState extends State<MultiMeasureScoreView> {
  final ScrollController _scrollController = ScrollController();

  @override
  void didUpdateWidget(MultiMeasureScoreView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Auto-scroll to follow cursor
    if (widget.currentNoteIndex != null &&
        widget.currentNoteIndex != oldWidget.currentNoteIndex) {
      _scrollToCurrentNote();
    }
  }

  void _scrollToCurrentNote() {
    if (widget.currentNoteIndex == null || widget.measures.isEmpty) return;
    int noteAccum = 0;
    int targetMeasureIdx = 0;

    for (int m = 0; m < widget.measures.length; m++) {
      final mNotes = widget.measures[m].notes;
      if (widget.currentNoteIndex! >= noteAccum &&
          widget.currentNoteIndex! < noteAccum + mNotes.length) {
        targetMeasureIdx = m;
        break;
      }
      noteAccum += mNotes.length;
    }

    final targetOffset = (targetMeasureIdx * widget.measureWidth) - 80.0;
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        targetOffset.clamp(0.0, _scrollController.position.maxScrollExtent),
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final totalWidth = math.max(
      MediaQuery.of(context).size.width,
      widget.measures.length * widget.measureWidth + 60.0,
    );

    return Container(
      height: widget.staffHeight,
      decoration: BoxDecoration(
        color: const Color(0xFF0B0D13),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: SingleChildScrollView(
          controller: _scrollController,
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: GestureDetector(
            onTapUp: (details) {
              final x = details.localPosition.dx;
              final measureIdx = (x / widget.measureWidth).floor() + 1;
              if (measureIdx >= 1 && measureIdx <= widget.measures.length) {
                widget.onMeasureTapped?.call(measureIdx);
              }
            },
            child: CustomPaint(
              size: Size(totalWidth, widget.staffHeight),
              painter: MultiMeasureStaffPainter(
                measures: widget.measures,
                loopRange: widget.loopRange,
                currentNoteIndex: widget.currentNoteIndex,
                targetMidi: widget.targetMidi,
                playedMidi: widget.playedMidi,
                isInTune: widget.isInTune,
                isScratching: widget.isScratching,
                selectedNoteIndex: widget.selectedNoteIndex,
                selectedMeasureIndex: widget.selectedMeasureIndex,
                measureWidth: widget.measureWidth,
                showFingering: widget.showFingering,
                showPositions: widget.showPositions,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class MultiMeasureStaffPainter extends CustomPainter {
  final List<ScoreMeasure> measures;
  final ScoreLoopRange loopRange;
  final int? currentNoteIndex;
  final int? targetMidi;
  final int? playedMidi;
  final bool isInTune;
  final bool isScratching;
  final int? selectedNoteIndex;
  final int? selectedMeasureIndex;
  final double measureWidth;
  final bool showFingering;
  final bool showPositions;

  MultiMeasureStaffPainter({
    required this.measures,
    required this.loopRange,
    required this.currentNoteIndex,
    required this.targetMidi,
    required this.playedMidi,
    required this.isInTune,
    required this.isScratching,
    required this.selectedNoteIndex,
    required this.selectedMeasureIndex,
    required this.measureWidth,
    this.showFingering = true,
    this.showPositions = true,
  });

  static const List<(int, bool)> _semitoneMap = [
    (0, false), // C
    (0, true),  // C#
    (1, false), // D
    (1, true),  // D#
    (2, false), // E
    (3, false), // F
    (3, true),  // F#
    (4, false), // G
    (4, true),  // G#
    (5, false), // A
    (5, true),  // A#
    (6, false), // B
  ];

  static (int step, bool isSharp) _getDiatonicStep(int midi) {
    final noteInOct = midi % 12;
    final octave = (midi ~/ 12) - 1;
    final (baseStep, isSharp) = _semitoneMap[noteInOct];
    final totalStep = (octave - 4) * 7 + baseStep;
    return (totalStep, isSharp);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (measures.isEmpty) return;

    final height = size.height;
    final lineSpacing = 10.0;
    final staffCenterY = height * 0.54;
    final line3Y = staffCenterY; // B4 line
    final line1Y = line3Y + lineSpacing * 2.0; // E4 line
    final line5Y = line1Y - lineSpacing * 4.0; // F5 line

    final totalWidth = size.width;

    // 1. Draw Loop Background Highlight if active
    if (loopRange.isEnabled) {
      final startX = (loopRange.startMeasure - 1) * measureWidth;
      final endX = loopRange.endMeasure * measureWidth;
      final loopRect = Rect.fromLTRB(startX, 10, endX, height - 10);

      final loopPaint = Paint()
        ..color = const Color(0xFFD4FF00).withValues(alpha: 0.08)
        ..style = PaintingStyle.fill;
      canvas.drawRRect(RRect.fromRectAndRadius(loopRect, const Radius.circular(8)), loopPaint);

      final borderPaint = Paint()
        ..color = const Color(0xFFD4FF00).withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      canvas.drawRRect(RRect.fromRectAndRadius(loopRect, const Radius.circular(8)), borderPaint);

      // Loop Banner Header
      final textPainter = TextPainter(
        text: TextSpan(
          text: '🔁 LOOP: ТАКТЫ ${loopRange.startMeasure}–${loopRange.endMeasure}',
          style: const TextStyle(
            color: Color(0xFFD4FF00),
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.0,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      textPainter.paint(canvas, Offset(startX + 8, 14));
    }

    // 2. Draw 5 Staff lines across entire score
    final staffPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.25)
      ..strokeWidth = 1.2;

    for (int i = 0; i < 5; i++) {
      final y = line1Y - (i * lineSpacing);
      canvas.drawLine(Offset(0, y), Offset(totalWidth, y), staffPaint);
    }

    // 3. Draw Treble Clef at start
    _drawTrebleClef(canvas, line3Y, lineSpacing);

    // Track all note coordinates for drawing slurs across notes
    final Map<int, Offset> notePositions = {};
    int globalNoteIndex = 0;
    int lastPosition = 1;

    // 4. Draw each Measure
    for (int m = 0; m < measures.length; m++) {
      final measure = measures[m];
      final measureStartX = m * measureWidth;
      final measureEndX = measureStartX + measureWidth;

      // Draw Measure Barline
      final barlinePaint = Paint()
        ..color = (m + 1 == selectedMeasureIndex)
            ? const Color(0xFF2563EB)
            : Colors.white.withValues(alpha: 0.35)
        ..strokeWidth = (m + 1 == selectedMeasureIndex) ? 2.5 : 1.2;
      canvas.drawLine(Offset(measureEndX, line5Y), Offset(measureEndX, line1Y), barlinePaint);

      // Measure Number label
      final mNumberPainter = TextPainter(
        text: TextSpan(
          text: '${measure.index}',
          style: TextStyle(
            color: (m + 1 == selectedMeasureIndex)
                ? const Color(0xFF2563EB)
                : Colors.white38,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      mNumberPainter.paint(canvas, Offset(measureStartX + 12, line5Y - 22));

      // Draw Notes inside measure
      final notes = measure.notes;
      if (notes.isNotEmpty) {
        final slotWidth = (measureWidth - 36.0) / notes.length;
        for (int n = 0; n < notes.length; n++) {
          final note = notes[n];
          final noteX = measureStartX + 26.0 + (n * slotWidth) + (slotWidth / 2.0);
          final (step, isSharp) = _getDiatonicStep(note.midiNote);
          final noteY = line1Y - ((step - 2) * (lineSpacing / 2.0));

          notePositions[globalNoteIndex] = Offset(noteX, noteY);

          final bool isCurrent = (globalNoteIndex == currentNoteIndex);
          final bool isSelected = (globalNoteIndex == selectedNoteIndex);

          // Color calculation
          Color noteColor = Colors.white70;
          if (isCurrent) {
            if (isScratching) {
              noteColor = const Color(0xFFFF2A55); // Scratch
            } else if (isInTune) {
              noteColor = const Color(0xFF10B981); // Emerald In Tune
            } else {
              noteColor = const Color(0xFFD4FF00); // High-voltage yellow active target
            }
          } else if (note.isHit) {
            noteColor = const Color(0xFF10B981);
          } else if (isSelected) {
            noteColor = const Color(0xFF2563EB);
          }

          // Position shift check
          final bool isPositionShift = (globalNoteIndex == 0 && note.position > 1) ||
              (globalNoteIndex > 0 && note.position != lastPosition);
          lastPosition = note.position;

          // Draw Note
          _drawScoreNote(
            canvas: canvas,
            x: noteX,
            y: noteY,
            step: step,
            isSharp: isSharp,
            lineSpacing: lineSpacing,
            line1Y: line1Y,
            line5Y: line5Y,
            color: noteColor,
            isCurrent: isCurrent,
            isSelected: isSelected,
            label: note.noteName,
            bowDirection: note.bowDirection,
            finger: note.finger,
            position: note.position,
            showPositionBadge: showPositions && isPositionShift,
            showFingering: showFingering,
          );

          // Draw Cursor highlight if current
          if (isCurrent) {
            final cursorPaint = Paint()
              ..color = noteColor.withValues(alpha: 0.3)
              ..style = PaintingStyle.fill;
            canvas.drawRRect(
              RRect.fromRectAndRadius(
                Rect.fromCenter(center: Offset(noteX, staffCenterY), width: 28, height: height - 30),
                const Radius.circular(8),
              ),
              cursorPaint,
            );
          }

          globalNoteIndex++;
        }
      }
    }

    // 5. Draw Slurs (Legato curves connecting notes in slur groups)
    _drawSlurs(canvas, notePositions, lineSpacing);
  }

  void _drawSlurs(Canvas canvas, Map<int, Offset> notePositions, double lineSpacing) {
    final Map<int, List<int>> groups = {};

    int idx = 0;
    for (final measure in measures) {
      for (final note in measure.notes) {
        if (note.slurGroupId != null) {
          groups.putIfAbsent(note.slurGroupId!, () => []).add(idx);
        }
        idx++;
      }
    }

    final slurPaint = Paint()
      ..color = const Color(0xFFD4FF00).withValues(alpha: 0.85)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    for (final noteIndices in groups.values) {
      if (noteIndices.length < 2) continue;
      final startPos = notePositions[noteIndices.first];
      final endPos = notePositions[noteIndices.last];

      if (startPos != null && endPos != null) {
        final path = Path();
        path.moveTo(startPos.dx, startPos.dy - 12);

        final midX = (startPos.dx + endPos.dx) / 2.0;
        final arcHeight = math.min(startPos.dy, endPos.dy) - 22.0;

        path.quadraticBezierTo(midX, arcHeight, endPos.dx, endPos.dy - 12);
        canvas.drawPath(path, slurPaint);
      }
    }
  }

  void _drawScoreNote({
    required Canvas canvas,
    required double x,
    required double y,
    required int step,
    required bool isSharp,
    required double lineSpacing,
    required double line1Y,
    required double line5Y,
    required Color color,
    required bool isCurrent,
    required bool isSelected,
    required String label,
    BowDirection? bowDirection,
    ViolinFinger? finger,
    int? position,
    bool showPositionBadge = false,
    bool showFingering = true,
  }) {
    // 1. Ledger lines
    final ledgerPaint = Paint()
      ..color = Colors.white38
      ..strokeWidth = 1.2;

    if (y > line1Y + lineSpacing * 0.5) {
      double curY = line1Y + lineSpacing;
      while (curY <= y + 1.0) {
        canvas.drawLine(Offset(x - 12, curY), Offset(x + 12, curY), ledgerPaint);
        curY += lineSpacing;
      }
    } else if (y < line5Y - lineSpacing * 0.5) {
      double curY = line5Y - lineSpacing;
      while (curY >= y - 1.0) {
        canvas.drawLine(Offset(x - 12, curY), Offset(x + 12, curY), ledgerPaint);
        curY -= lineSpacing;
      }
    }

    // 2. Note Head
    final headRadiusX = lineSpacing * 0.65;
    final headRadiusY = lineSpacing * 0.48;

    canvas.save();
    canvas.translate(x, y);
    canvas.rotate(-0.35); // Classic notation tilt

    final headPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: headRadiusX * 2, height: headRadiusY * 2), headPaint);

    if (isSelected) {
      final ringPaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;
      canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: headRadiusX * 2 + 6, height: headRadiusY * 2 + 6), ringPaint);
    }
    canvas.restore();

    // 3. Stem (Up if below middle line B4, down if on/above middle line)
    final isStemUp = y > (line1Y - 2 * lineSpacing);
    final stemHeight = lineSpacing * 3.2;
    final stemX = isStemUp ? x + headRadiusX - 1.0 : x - headRadiusX + 1.0;
    final stemStartY = y;
    final stemEndY = isStemUp ? y - stemHeight : y + stemHeight;

    final stemPaint = Paint()
      ..color = color
      ..strokeWidth = 1.6;
    canvas.drawLine(Offset(stemX, stemStartY), Offset(stemX, stemEndY), stemPaint);

    // 4. Sharp symbol (♯)
    if (isSharp) {
      final sharpPainter = TextPainter(
        text: TextSpan(
          text: '♯',
          style: TextStyle(
            color: color,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      sharpPainter.paint(canvas, Offset(x - 18, y - 10));
    }

    // 5. Bow Direction symbol (⊓ Down-bow or ∨ Up-bow)
    if (bowDirection != null) {
      final bowText = bowDirection == BowDirection.down ? '⊓' : '∨';
      final bowPainter = TextPainter(
        text: TextSpan(
          text: bowText,
          style: const TextStyle(
            color: Color(0xFFD4FF00),
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      bowPainter.paint(canvas, Offset(x - 5, line5Y - 24));
    }

    // 6. Violin Fingering Number (0, 1, 2, 3, 4)
    if (showFingering && finger != null) {
      final fingerY = isStemUp ? (y - stemHeight - 13.0) : (y - headRadiusY - 13.0);
      final fingerPainter = TextPainter(
        text: TextSpan(
          text: '${finger.number}',
          style: TextStyle(
            color: isCurrent
                ? color
                : (isSelected ? const Color(0xFF60A5FA) : Colors.white.withValues(alpha: 0.85)),
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      fingerPainter.paint(canvas, Offset(x - (fingerPainter.width / 2), fingerY));
    }

    // 7. Violin Position Badge (e.g. "III поз.")
    if (showPositionBadge && position != null && position > 1) {
      final posStr = '${MusicTheory.positionToRoman(position)} поз.';
      final posPainter = TextPainter(
        text: TextSpan(
          text: posStr,
          style: const TextStyle(
            color: Color(0xFF60A5FA),
            fontSize: 9,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.3,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      posPainter.paint(canvas, Offset(x - (posPainter.width / 2), line5Y - 38));
    }

    // 8. Note Label below
    final labelPainter = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: isCurrent ? color : Colors.white54,
          fontSize: 10,
          fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    labelPainter.paint(canvas, Offset(x - (labelPainter.width / 2), line1Y + 16));
  }

  void _drawTrebleClef(Canvas canvas, double centerY, double spacing) {
    final textPainter = TextPainter(
      text: const TextSpan(
        text: '𝄞',
        style: TextStyle(
          color: Colors.white70,
          fontSize: 44,
          fontFamily: 'serif',
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    textPainter.paint(canvas, Offset(10, centerY - spacing * 3.1));
  }

  @override
  bool shouldRepaint(covariant MultiMeasureStaffPainter oldDelegate) {
    return oldDelegate.currentNoteIndex != currentNoteIndex ||
        oldDelegate.targetMidi != targetMidi ||
        oldDelegate.playedMidi != playedMidi ||
        oldDelegate.isInTune != isInTune ||
        oldDelegate.isScratching != isScratching ||
        oldDelegate.selectedNoteIndex != selectedNoteIndex ||
        oldDelegate.selectedMeasureIndex != selectedMeasureIndex ||
        oldDelegate.loopRange != loopRange ||
        oldDelegate.showFingering != showFingering ||
        oldDelegate.showPositions != showPositions ||
        oldDelegate.measures != measures;
  }
}
