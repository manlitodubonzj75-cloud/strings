import 'package:flutter/material.dart';
import '../../models/song_model.dart';
import '../../music_theory.dart';
import '../../services/score_edit_controller.dart';
import '../../services/fingering_optimizer.dart';

/// Contextual toolbar for score editing and measure looping.
class ScoreEditorToolbar extends StatelessWidget {
  final ScoreEditController controller;
  final VoidCallback? onPlayLoop;

  const ScoreEditorToolbar({
    super.key,
    required this.controller,
    this.onPlayLoop,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final selectedNoteIdx = controller.selectedNoteIndex;
        final selectedMeasureIdx = controller.selectedMeasureIndex;
        final loopRange = controller.loopRange;

        final SongNote? selectedNote = (selectedNoteIdx != null &&
                selectedNoteIdx >= 0 &&
                selectedNoteIdx < controller.song.notes.length)
            ? controller.song.notes[selectedNoteIdx]
            : null;

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF11141C),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Top Bar: Selection status & Loop controls
              Row(
                children: [
                  const Icon(
                    Icons.tune_rounded,
                    size: 16,
                    color: Color(0xFFD4FF00),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      selectedNote != null
                          ? 'Нота ${selectedNote.noteName} • ${selectedNote.string.name.toUpperCase()} (${selectedNote.finger.label}, ${MusicTheory.positionToRoman(selectedNote.position)} поз.)'
                          : selectedMeasureIdx != null
                              ? 'Такт $selectedMeasureIdx'
                              : 'Тапните по ноте или такту',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  // Undo / Redo
                  IconButton(
                    icon: const Icon(Icons.undo, size: 18),
                    color: controller.canUndo ? Colors.white : Colors.white24,
                    tooltip: 'Отменить',
                    visualDensity: VisualDensity.compact,
                    onPressed: controller.canUndo ? controller.undo : null,
                  ),
                  IconButton(
                    icon: const Icon(Icons.redo, size: 18),
                    color: controller.canRedo ? Colors.white : Colors.white24,
                    tooltip: 'Повторить',
                    visualDensity: VisualDensity.compact,
                    onPressed: controller.canRedo ? controller.redo : null,
                  ),
                ],
              ),
              const Divider(color: Colors.white12, height: 12),
              // Action Buttons Row
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                child: Row(
                  children: [
                    // Global Auto-optimize fingering button
                    _ToolButton(
                      icon: Icons.auto_awesome,
                      label: 'Авто-аппликатура',
                      color: const Color(0xFFD4FF00),
                      onTap: () {
                        controller.autoOptimizeFingering(preference: FingeringPreference.balanced);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Аппликатура и позиции 1-3 оптимизированы!'),
                            duration: Duration(seconds: 1),
                          ),
                        );
                      },
                    ),
                    const SizedBox(width: 6),

                    // --- Loop Controls ---
                    if (selectedMeasureIdx != null) ...[
                      _ToolButton(
                        icon: Icons.repeat,
                        label: 'Зациклить такт $selectedMeasureIdx',
                        color: const Color(0xFFD4FF00),
                        onTap: () {
                          controller.selectMeasureForLoop(selectedMeasureIdx);
                          onPlayLoop?.call();
                        },
                      ),
                      const SizedBox(width: 6),
                    ],
                    if (loopRange.isEnabled) ...[
                      _ToolButton(
                        icon: Icons.close,
                        label: 'Сброс лупа (${loopRange.startMeasure}–${loopRange.endMeasure})',
                        color: Colors.white60,
                        onTap: controller.clearLoop,
                      ),
                      const SizedBox(width: 6),
                    ],

                    // --- Note Controls (if note selected) ---
                    if (selectedNoteIdx != null && selectedNote != null) ...[
                      // Position cycling button (I -> II -> III -> I)
                      _ToolButton(
                        icon: Icons.pan_tool_alt_rounded,
                        label: 'Позиция: ${MusicTheory.positionToRoman(selectedNote.position)}',
                        color: const Color(0xFF60A5FA),
                        onTap: () {
                          final nextPos = (selectedNote.position % 3) + 1;
                          final candidates = MusicTheory.getCandidatesForMidi(selectedNote.midiNote, maxPosition: 3);
                          final match = candidates.firstWhere(
                            (c) => c.position == nextPos,
                            orElse: () => candidates.first,
                          );
                          controller.modifyNoteFingering(
                            selectedNoteIdx,
                            string: match.string,
                            finger: match.finger,
                            position: match.position,
                          );
                        },
                      ),
                      const SizedBox(width: 6),
                      _ToolButton(
                        icon: Icons.arrow_upward,
                        label: '+1 полутон (♯)',
                        color: const Color(0xFF2563EB),
                        onTap: () => controller.transposeSelectedNote(1),
                      ),
                      const SizedBox(width: 6),
                      _ToolButton(
                        icon: Icons.arrow_downward,
                        label: '-1 полутон (♭)',
                        color: const Color(0xFF2563EB),
                        onTap: () => controller.transposeSelectedNote(-1),
                      ),
                      const SizedBox(width: 6),
                      // Slur button
                      _ToolButton(
                        icon: Icons.all_inclusive,
                        label: selectedNote.isSlurred ? 'Убрать лигу' : 'Лига (с сос.)',
                        color: selectedNote.isSlurred
                            ? const Color(0xFFFF2A55)
                            : const Color(0xFF10B981),
                        onTap: () {
                          if (selectedNote.isSlurred) {
                            controller.removeSlur(selectedNoteIdx);
                          } else if (selectedNoteIdx < controller.song.notes.length - 1) {
                            controller.addSlur(selectedNoteIdx, selectedNoteIdx + 1);
                          }
                        },
                      ),
                      const SizedBox(width: 6),
                      // Bow direction button
                      _ToolButton(
                        icon: Icons.swap_vert,
                        label: selectedNote.bowDirection == null
                            ? 'Штрих: —'
                            : 'Штрих: ${selectedNote.bowDirection!.label}',
                        color: const Color(0xFFD4FF00),
                        onTap: () => controller.toggleBowDirection(selectedNoteIdx),
                      ),
                      const SizedBox(width: 6),
                      // Delete note
                      _ToolButton(
                        icon: Icons.delete_outline,
                        label: 'Удалить',
                        color: const Color(0xFFFF2A55),
                        onTap: () => controller.deleteNote(selectedNoteIdx),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ToolButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ToolButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
