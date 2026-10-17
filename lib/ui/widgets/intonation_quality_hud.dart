import 'package:flutter/material.dart';
import '../../models/song_model.dart';
import '../../music_theory.dart';

/// Real-time intonation and performance quality HUD for violin practice.
class IntonationQualityHud extends StatelessWidget {
  final SongNote? targetNote;
  final DetectedNoteInfo? detectedNote;
  final bool isScratching;
  final bool isInTune;
  final double cents;
  final BowDirection? currentBowDirection;
  final String practiceModeLabel;

  const IntonationQualityHud({
    super.key,
    required this.targetNote,
    this.detectedNote,
    this.isScratching = false,
    this.isInTune = false,
    this.cents = 0.0,
    this.currentBowDirection,
    this.practiceModeLabel = 'Ждать ноту',
  });

  @override
  Widget build(BuildContext context) {
    Color statusColor;
    String statusText;

    if (isScratching) {
      statusColor = const Color(0xFFFF2A55);
      statusText = 'СКРИП СМЫЧКА';
    } else if (targetNote != null && detectedNote != null && isInTune) {
      statusColor = const Color(0xFF10B981);
      statusText = 'В СТРОЮ';
    } else if (detectedNote != null && detectedNote!.cents.abs() > 12) {
      statusColor = detectedNote!.cents > 0
          ? const Color(0xFF3B82F6)
          : const Color(0xFFF59E0B);
      statusText = detectedNote!.cents > 0
          ? '+${detectedNote!.cents.toStringAsFixed(0)}¢'
          : '${detectedNote!.cents.toStringAsFixed(0)}¢';
    } else {
      statusColor = Colors.white54;
      statusText = targetNote != null ? 'СЫГРАЙТЕ' : 'ГОТОВ';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF11141C),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: statusColor.withValues(alpha: 0.35),
          width: 1.2,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Row 1: Target vs Detected Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Target Info
              Flexible(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2563EB).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFF2563EB).withValues(alpha: 0.4)),
                        ),
                        child: Text(
                          targetNote != null
                              ? '${targetNote!.noteName} (${targetNote!.string.name.toUpperCase()}-${targetNote!.finger.number})'
                              : 'Партитура',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF60A5FA),
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    if (targetNote?.bowDirection != null) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFD4FF00).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          targetNote!.bowDirection!.symbol,
                          style: const TextStyle(
                            color: Color(0xFFD4FF00),
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(width: 8),

              // Status Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: statusColor.withValues(alpha: 0.5)),
                ),
                child: Text(
                  statusText,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),

          // Row 2: Intonation Cents Meter Bar (-50¢ ... 0 ... +50¢)
          Stack(
            alignment: Alignment.center,
            children: [
              // Background track
              Container(
                height: 8,
                decoration: BoxDecoration(
                  color: Colors.white12,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              // Center in-tune sweet spot zone (-10¢ to +10¢)
              FractionallySizedBox(
                widthFactor: 0.2,
                child: Container(
                  height: 8,
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              // Active needle / indicator
              Align(
                alignment: Alignment(
                  (cents / 50.0).clamp(-1.0, 1.0),
                  0.0,
                ),
                child: Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: statusColor,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: statusColor.withValues(alpha: 0.6),
                        blurRadius: 6,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 6),

          // Row 3: Details & Mode footer
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  detectedNote != null
                      ? '${detectedNote!.noteName} (${detectedNote!.rawHz.toStringAsFixed(1)} Гц)'
                      : 'Слушаю микрофон...',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 11,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                practiceModeLabel,
                style: const TextStyle(
                  color: Color(0xFFD4FF00),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
