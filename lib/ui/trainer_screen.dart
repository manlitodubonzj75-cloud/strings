import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../audio_engine.dart';
import '../controllers/trainer_controller.dart';
import '../music_theory.dart';
import '../theme/apple_violin_theme.dart';
import 'widgets/circle_of_fifths_picker.dart';

class TrainerScreen extends StatefulWidget {
  final AudioEngine audioEngine;
  final DetectedNoteInfo? currentNote;
  final ValueNotifier<DetectedNoteInfo?>? noteNotifier;
  final TrainerController? controller;

  const TrainerScreen({
    super.key,
    required this.audioEngine,
    this.currentNote,
    this.noteNotifier,
    this.controller,
  });

  @override
  State<TrainerScreen> createState() => _TrainerScreenState();
}

class _TrainerScreenState extends State<TrainerScreen>
    with SingleTickerProviderStateMixin {
  /// Train-mode pill row — ♩ Фикс · Ускорение · Лигатура · Дробление · Пропуск · Случайно
  static const List<(String, String)> _trainModes = [
    ('fixed', '♩ Фикс'),
    ('accel', '♩+ Ускорение'),
    ('slur', '🎵 Лигатура'),
    ('split', '✂ Дробление'),
    ('skip', '? Пропуск'),
    ('random', '🌀 Случайно'),
  ];

  late final TrainerController _controller;
  bool _ownsController = false;
  late final AnimationController _pulse;

  ViolinScaleDef get currentScale => _controller.currentScale;
  ScaleNoteStep get currentStep => _controller.currentStep;

  @override
  void initState() {
    super.initState();
    if (widget.controller != null) {
      _controller = widget.controller!;
    } else {
      _controller = TrainerController(
        audioEngine: widget.audioEngine,
        initialStreak: 7,
      );
      _ownsController = true;
    }
    _controller.addListener(_onControllerChanged);
    _controller.startProgressTracking(widget.noteNotifier, () => widget.currentNote);

    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
  }

  void _onControllerChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    _controller.removeListener(_onControllerChanged);
    if (_ownsController) {
      _controller.dispose();
    }
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Small helpers
  // ---------------------------------------------------------------------------

  Widget _micro(String text, {required Color color, double size = 10}) {
    return Text(
      text,
      style: AppleViolinTheme.telemetry.copyWith(color: color, fontSize: size),
    );
  }

  Color _stringColor(ViolinString s) => switch (s) {
        ViolinString.g => AppleViolinTheme.stringG,
        ViolinString.d => AppleViolinTheme.stringD,
        ViolinString.a => AppleViolinTheme.stringA,
        ViolinString.e => AppleViolinTheme.stringE,
      };

  int _accidentalCount(String sig) {
    if (currentScale.tonality != null) {
      return currentScale.tonality!.accidentalCount.abs();
    }
    return '#'.allMatches(sig).length + '♭'.allMatches(sig).length;
  }

  String _scaleChipLabel(ViolinScaleDef s) {
    if (s.tonality != null) {
      return s.tonality!.shortName;
    }
    final base = s.name.split(' (').first;
    return base.replaceFirst('мажор', 'маж').replaceFirst('минор', 'мин');
  }

  String _scaleBadge(ViolinScaleDef s) {
    if (s.tonality != null) {
      return '${s.tonality!.shortName.toUpperCase()} · ${s.tonality!.position.shortKeySignature}';
    }
    final base = s.name.split(' (').first.toUpperCase();
    final n = _accidentalCount(s.keySignature);
    return '$base · ${n > 0 ? '$n#' : '0'}';
  }

  /// Russian feedback line + its accent colour (derived, not stateful).
  (String, Color) _hint(DetectedNoteInfo? note, bool isInTune) {
    if (_controller.isReferencePlaying || _controller.isFullScalePlaying) {
      return (
        '🔊 Звучит эталон (${currentStep.targetHz.toStringAsFixed(1)} Гц) · Послушайте интонацию',
        AppleViolinTheme.highVoltageLime,
      );
    }
    if (note == null || note.midiNote != currentStep.midiNote) {
      return ('Сыграйте ноту смычком: ${currentStep.fingerLabel}', AppleViolinTheme.subtext);
    }
    if (note.isScratching) {
      return ('Скрип: ослабьте нажим смычка', AppleViolinTheme.crimsonScratch);
    }
    if (isInTune) {
      return ('Чистая интонация! Удерживайте смычок...', AppleViolinTheme.hyperEmerald);
    }
    final cents = note.cents;
    if (cents < 0) {
      return ('Низит на ${cents.abs().toStringAsFixed(0)}¢: сдвиньте палец к подставке', AppleViolinTheme.solarAmber);
    }
    return ('Высит на +${cents.toStringAsFixed(0)}¢: сдвиньте палец к колкам', AppleViolinTheme.solarAmber);
  }

  @override
  Widget build(BuildContext context) {
    final note = widget.currentNote ?? widget.noteNotifier?.value;
    final isCorrectNote = note != null && note.midiNote == currentStep.midiNote;
    final isInTune = isCorrectNote && note.isInTune && !note.isScratching;

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(),
          const SizedBox(height: 22),
          _buildScaleSelectorCard(),
          const SizedBox(height: 20),
          _buildHeroCard(isInTune, note),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Editorial header + status pill
  // ---------------------------------------------------------------------------

  Widget _buildHeader() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _micro('ТРЕНИРОВКА', color: AppleViolinTheme.subtext),
              const SizedBox(height: 10),
              RichText(
                text: TextSpan(
                  children: [
                    TextSpan(
                      text: 'Гаммы ',
                      style: TextStyle(
                        fontFamily: AppleViolinTheme.fontDisplay,
                        fontSize: 34,
                        height: 0.98,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -1.2,
                        color: AppleViolinTheme.headline,
                      ),
                    ),
                    TextSpan(
                      text: 'и техника',
                      style: TextStyle(
                        fontFamily: AppleViolinTheme.fontEditorial,
                        fontSize: 34,
                        height: 0.98,
                        fontStyle: FontStyle.italic,
                        fontWeight: FontWeight.w400,
                        letterSpacing: -0.6,
                        color: AppleViolinTheme.subtext,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        _buildStreakPill(),
      ],
    );
  }

  Widget _buildStreakPill() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0x0AFFFFFF),
        borderRadius: AppleViolinTheme.pillRadius,
        border: Border.all(color: AppleViolinTheme.borderSubtle),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _pulse,
            builder: (context, _) {
              return Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppleViolinTheme.highVoltageLime
                      .withValues(alpha: 0.35 + 0.55 * _pulse.value),
                  boxShadow: [
                    BoxShadow(
                      color: AppleViolinTheme.highVoltageLime
                          .withValues(alpha: 0.35 * _pulse.value),
                      blurRadius: 8,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(width: 8),
          Text(
            'СЕРИЯ · ${_controller.streak} НОТ',
            style: AppleViolinTheme.telemetry.copyWith(
              fontSize: 10,
              letterSpacing: 1.1,
              color: const Color(0xFFD4D4D8),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Tonality selector card with Circle of Fifths Toggle
  // ---------------------------------------------------------------------------

  Widget _buildScaleSelectorCard() {
    final scales = TrainerController.allScales;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: AppleViolinTheme.glassDecoration(radius: AppleViolinTheme.bentoRadius),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _micro('ТОНАЛЬНОСТЬ', color: AppleViolinTheme.subtext),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  _controller.toggleCircleOfFifths();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _controller.showCircleOfFifths
                        ? AppleViolinTheme.highVoltageLime.withValues(alpha: 0.15)
                        : const Color(0x0EFFFFFF),
                    borderRadius: AppleViolinTheme.pillRadius,
                    border: Border.all(
                      color: _controller.showCircleOfFifths
                          ? AppleViolinTheme.highVoltageLime
                          : AppleViolinTheme.borderSubtle,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _controller.showCircleOfFifths
                            ? Icons.view_list_rounded
                            : Icons.pie_chart_outline_rounded,
                        size: 13,
                        color: _controller.showCircleOfFifths
                            ? AppleViolinTheme.highVoltageLime
                            : AppleViolinTheme.headline,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        _controller.showCircleOfFifths ? 'Список' : 'Квинтовый круг',
                        style: AppleViolinTheme.telemetry.copyWith(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: _controller.showCircleOfFifths
                              ? AppleViolinTheme.highVoltageLime
                              : AppleViolinTheme.headline,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              Text(
                _scaleBadge(currentScale),
                textAlign: TextAlign.right,
                style: AppleViolinTheme.telemetry.copyWith(
                  fontSize: 10,
                  fontFamily: AppleViolinTheme.fontMono,
                  fontWeight: FontWeight.w700,
                  color: AppleViolinTheme.highVoltageLime,
                ),
              ),
            ],
          ),
          if (_controller.showCircleOfFifths) ...[
            const SizedBox(height: 16),
            CircleOfFifthsPicker(
              size: 270,
              selectedTonality: _controller.selectedTonality,
              onTonalityChanged: (tonality) {
                _controller.selectTonality(tonality);
              },
            ),
            const SizedBox(height: 10),
            Center(
              child: Text(
                '${currentScale.name} · ${currentScale.keySignature}',
                textAlign: TextAlign.center,
                style: AppleViolinTheme.telemetry.copyWith(
                  fontSize: 11,
                  color: AppleViolinTheme.subtext,
                ),
              ),
            ),
          ] else ...[
            const SizedBox(height: 12),
            SizedBox(
              height: 36,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                itemCount: scales.length,
                separatorBuilder: (context, index) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final scale = scales[index];
                  final isSelected = scale.tonality == _controller.selectedTonality ||
                      (scale.tonality == null && index == _controller.selectedScaleIndex);
                  return GestureDetector(
                    onTap: () => _controller.selectScale(index),
                    child: AnimatedContainer(
                      duration: AppleViolinTheme.motionFast,
                      curve: AppleViolinTheme.easeOutExpo,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppleViolinTheme.highVoltageLime
                            : const Color(0x08FFFFFF),
                        borderRadius: AppleViolinTheme.pillRadius,
                        border: Border.all(
                          color: isSelected
                              ? AppleViolinTheme.highVoltageLime
                              : AppleViolinTheme.borderSubtle,
                        ),
                        boxShadow: isSelected ? const [AppleViolinTheme.limeGlow] : null,
                      ),
                      child: Center(
                        child: Text(
                          _scaleChipLabel(scale),
                          style: AppleViolinTheme.telemetry.copyWith(
                            fontSize: 11,
                            letterSpacing: 0.5,
                            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                            color: isSelected
                                ? AppleViolinTheme.voidBg
                                : AppleViolinTheme.subtext,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Scale hero card
  // ---------------------------------------------------------------------------

  Widget _buildHeroCard(bool isInTune, DetectedNoteInfo? note) {
    final bowDown = _controller.currentStepIndex.isEven;

    return Stack(
      children: [
        Positioned(
          top: -90,
          left: -70,
          child: IgnorePointer(
            child: Container(
              width: 320,
              height: 320,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [Color(0x24D4FF00), Color(0x00D4FF00)],
                  stops: [0.0, 0.68],
                ),
              ),
            ),
          ),
        ),
        AnimatedContainer(
          duration: AppleViolinTheme.motion,
          curve: AppleViolinTheme.easeOutExpo,
          padding: const EdgeInsets.all(20),
          decoration: AppleViolinTheme.glassDecoration(
            highlighted: isInTune,
            radius: AppleViolinTheme.bentoRadius,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeroTopRow(bowDown),
              const SizedBox(height: 16),
              _buildStaff(note, isInTune),
              const SizedBox(height: 16),
              _buildSpecBento(),
              const SizedBox(height: 18),
              _buildStepTrail(),
              const SizedBox(height: 18),
              _buildPurityRow(note, isInTune, bowDown),
              const SizedBox(height: 18),
              _buildTrainModes(),
              const SizedBox(height: 18),
              _buildActions(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHeroTopRow(bool bowDown) {
    final step = currentStep;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _micro('СЫГРАЙТЕ НОТУ', color: AppleViolinTheme.subtext),
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    step.russianNote,
                    style: TextStyle(
                      fontFamily: AppleViolinTheme.fontDisplay,
                      fontSize: 48,
                      height: 0.95,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -1.8,
                      color: AppleViolinTheme.headline,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${step.octave}',
                    style: TextStyle(
                      fontFamily: AppleViolinTheme.fontMono,
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      color: AppleViolinTheme.highVoltageLime,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '(${step.fullTitle})',
                    style: TextStyle(
                      fontFamily: AppleViolinTheme.fontMono,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: AppleViolinTheme.subtext,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        _buildBowBadge(bowDown),
      ],
    );
  }

  Widget _buildBowBadge(bool bowDown) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0x08FFFFFF),
        borderRadius: AppleViolinTheme.pillRadius,
        border: Border.all(color: AppleViolinTheme.borderSubtle),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            bowDown ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
            size: 15,
            color: AppleViolinTheme.highVoltageLime,
          ),
          const SizedBox(width: 6),
          Text(
            bowDown ? 'ВНИЗ' : 'ВВЕРХ',
            style: AppleViolinTheme.telemetry.copyWith(
              fontSize: 10,
              letterSpacing: 1.0,
              fontWeight: FontWeight.w700,
              color: AppleViolinTheme.headline,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStaff(DetectedNoteInfo? note, bool isInTune) {
    final accidentalCount = _accidentalCount(currentScale.keySignature);
    final isFlat = currentScale.tonality?.accidentalCount != null &&
        currentScale.tonality!.accidentalCount < 0;

    final isRefActive = _controller.isReferencePlaying || _controller.isFullScalePlaying;
    return Container(
      height: 112,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: const Color(0x05FFFFFF),
        borderRadius: AppleViolinTheme.btnRadius,
        border: Border.all(color: AppleViolinTheme.borderSubtle),
      ),
      child: CustomPaint(
        painter: _ScaleStaffPainter(
          targetMidi: currentStep.midiNote,
          playedMidi: isRefActive ? null : note?.midiNote,
          isScratching: isRefActive ? false : (note?.isScratching ?? false),
          isInTune: isRefActive ? true : isInTune,
          accidentalCount: accidentalCount,
          isFlat: isFlat,
          targetLabel: currentStep.fullTitle,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }

  Widget _buildSpecBento() {
    final step = currentStep;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _specTile(
            'ПАЛЕЦ',
            step.fingerLabel,
            color: AppleViolinTheme.headline,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _specTile(
            'СТРУНА',
            '${step.string.solfegeName} (${step.string.name})',
            color: _stringColor(step.string),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _specTile(
            'ЧАСТОТА',
            '${step.targetHz.toStringAsFixed(2)} Hz',
            color: AppleViolinTheme.highVoltageLime,
          ),
        ),
      ],
    );
  }

  Widget _specTile(String label, String value, {required Color color}) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0x05FFFFFF),
        borderRadius: AppleViolinTheme.btnRadius,
        border: Border.all(color: const Color(0x12FFFFFF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _micro(label, color: const Color(0xFF52525B), size: 9),
          const SizedBox(height: 5),
          Text(
            value,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: AppleViolinTheme.fontMono,
              fontSize: 10,
              height: 1.25,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepTrail() {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: currentScale.steps.length,
        separatorBuilder: (context, index) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final step = currentScale.steps[index];
          final isCurrent = index == _controller.currentStepIndex;
          final isDone = index < _controller.currentStepIndex;

          final bg = isCurrent
              ? AppleViolinTheme.highVoltageLime
              : isDone
                  ? AppleViolinTheme.hyperEmerald.withValues(alpha: 0.16)
                  : const Color(0x08FFFFFF);

          final borderCol = isCurrent
              ? AppleViolinTheme.highVoltageLime
              : isDone
                  ? AppleViolinTheme.hyperEmerald.withValues(alpha: 0.4)
                  : AppleViolinTheme.borderSubtle;

          final textCol = isCurrent
              ? AppleViolinTheme.voidBg
              : isDone
                  ? AppleViolinTheme.hyperEmerald
                  : AppleViolinTheme.subtext;

          return GestureDetector(
            onTap: () {
              _controller.setStepIndex(index);
            },
            child: AnimatedContainer(
              duration: AppleViolinTheme.motionFast,
              curve: AppleViolinTheme.easeOutExpo,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: AppleViolinTheme.pillRadius,
                border: Border.all(color: borderCol),
                boxShadow: isCurrent ? const [AppleViolinTheme.limeGlow] : null,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${index + 1}.',
                    style: TextStyle(
                      fontFamily: AppleViolinTheme.fontMono,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: textCol.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    step.fullTitle,
                    style: TextStyle(
                      fontFamily: AppleViolinTheme.fontMono,
                      fontSize: 11,
                      fontWeight: isCurrent ? FontWeight.w800 : FontWeight.w600,
                      color: textCol,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPurityRow(DetectedNoteInfo? note, bool isInTune, bool bowDown) {
    final pct = (_controller.holdProgress * 100).round();
    final (hintText, hintColor) = _hint(note, isInTune);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            _micro('ЧИСТОТА', color: const Color(0xFF52525B), size: 9),
            const SizedBox(width: 10),
            Expanded(
              child: ClipRRect(
                borderRadius: AppleViolinTheme.pillRadius,
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.0, end: _controller.holdProgress),
                  duration: AppleViolinTheme.motion,
                  curve: AppleViolinTheme.easeOutExpo,
                  builder: (context, value, _) => LinearProgressIndicator(
                    value: value,
                    minHeight: 6,
                    backgroundColor: const Color(0x12FFFFFF),
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      AppleViolinTheme.highVoltageLime,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              '$pct%',
              style: AppleViolinTheme.telemetry.copyWith(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: AppleViolinTheme.highVoltageLime,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              bowDown ? '↓ Вниз' : '↑ Вверх',
              style: AppleViolinTheme.telemetry.copyWith(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: const Color(0xFFE4E4E7),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          hintText,
          style: TextStyle(
            fontFamily: AppleViolinTheme.fontEditorial,
            fontStyle: FontStyle.italic,
            fontSize: 12,
            color: hintColor,
          ),
        ),
      ],
    );
  }

  Widget _buildTrainModes() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _micro('РЕЖИМ ТРЕНИРОВКИ', color: AppleViolinTheme.subtext),
        const SizedBox(height: 8),
        SizedBox(
          height: 32,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: _trainModes.length,
            separatorBuilder: (context, index) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final (id, label) = _trainModes[index];
              final isActive = id == _controller.trainMode;
              return GestureDetector(
                onTap: () => _controller.setTrainMode(id),
                child: AnimatedContainer(
                  duration: AppleViolinTheme.motionFast,
                  curve: AppleViolinTheme.easeOutExpo,
                  padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                  decoration: BoxDecoration(
                    color: isActive
                        ? AppleViolinTheme.highVoltageLime
                        : const Color(0x08FFFFFF),
                    borderRadius: AppleViolinTheme.pillRadius,
                    border: Border.all(
                      color: isActive
                          ? AppleViolinTheme.highVoltageLime
                          : AppleViolinTheme.borderSubtle,
                    ),
                    boxShadow: isActive ? const [AppleViolinTheme.limeGlow] : null,
                  ),
                  child: Center(
                    child: Text(
                      label,
                      style: AppleViolinTheme.telemetry.copyWith(
                        fontSize: 9,
                        letterSpacing: 0.4,
                        fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                        color: isActive
                            ? AppleViolinTheme.voidBg
                            : AppleViolinTheme.subtext,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildActions() {
    final isReferencePlaying = _controller.isReferencePlaying;
    final isFullScalePlaying = _controller.isFullScalePlaying;

    return Row(
      children: [
        Expanded(
          flex: 5,
          child: GestureDetector(
            onTap: _controller.playSingleReference,
            child: AnimatedContainer(
              duration: AppleViolinTheme.motionFast,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: isReferencePlaying
                    ? AppleViolinTheme.highVoltageLime.withValues(alpha: 0.18)
                    : const Color(0x0CFFFFFF),
                borderRadius: AppleViolinTheme.pillRadius,
                border: Border.all(
                  color: isReferencePlaying
                      ? AppleViolinTheme.highVoltageLime
                      : AppleViolinTheme.borderSubtle,
                ),
                boxShadow: isReferencePlaying ? const [AppleViolinTheme.limeGlow] : null,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    isReferencePlaying ? Icons.graphic_eq_rounded : Icons.volume_up_rounded,
                    size: 16,
                    color: AppleViolinTheme.highVoltageLime,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    isReferencePlaying ? 'ЗВУЧИТ...' : 'ЭТАЛОН',
                    style: AppleViolinTheme.telemetry.copyWith(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: isReferencePlaying
                          ? AppleViolinTheme.highVoltageLime
                          : const Color(0xFFE4E4E7),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 6,
          child: GestureDetector(
            onTap: _controller.playFullScale,
            child: AnimatedContainer(
              duration: AppleViolinTheme.motionFast,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: isFullScalePlaying
                    ? const Color(0xFF38BDF8).withValues(alpha: 0.18)
                    : const Color(0x0CFFFFFF),
                borderRadius: AppleViolinTheme.pillRadius,
                border: Border.all(
                  color: isFullScalePlaying
                      ? const Color(0xFF38BDF8)
                      : AppleViolinTheme.borderSubtle,
                ),
                boxShadow: isFullScalePlaying
                    ? [
                        BoxShadow(
                          color: const Color(0xFF38BDF8).withValues(alpha: 0.35),
                          blurRadius: 18,
                        ),
                      ]
                    : null,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    isFullScalePlaying ? Icons.stop_rounded : Icons.play_arrow_rounded,
                    size: 18,
                    color: isFullScalePlaying
                        ? const Color(0xFF38BDF8)
                        : AppleViolinTheme.headline,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    isFullScalePlaying ? 'СТОП' : 'ВСЯ ГАММА',
                    style: AppleViolinTheme.telemetry.copyWith(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: isFullScalePlaying
                          ? const Color(0xFF38BDF8)
                          : AppleViolinTheme.headline,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// Treble clef staff painter for current scale step
// -----------------------------------------------------------------------------

class _ScaleStaffPainter extends CustomPainter {
  final int targetMidi;
  final int? playedMidi;
  final bool isScratching;
  final bool isInTune;
  final int accidentalCount;
  final bool isFlat;
  final String targetLabel;

  _ScaleStaffPainter({
    required this.targetMidi,
    required this.playedMidi,
    required this.isScratching,
    required this.isInTune,
    required this.accidentalCount,
    required this.isFlat,
    required this.targetLabel,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final staffPaint = Paint()
      ..color = const Color(0x3DFFFFFF)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    final double staffTop = size.height * 0.32;
    final double lineSpacing = 11.0;

    for (int i = 0; i < 5; i++) {
      final y = staffTop + i * lineSpacing;
      canvas.drawLine(Offset(10, y), Offset(size.width - 10, y), staffPaint);
    }

    _drawClef(canvas, Offset(24, staffTop + lineSpacing * 2.3));

    if (accidentalCount > 0) {
      final keyPaint = Paint()
        ..color = const Color(0xB3FFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.3;
      final keyX = 42.0;
      for (int i = 0; i < accidentalCount && i < 7; i++) {
        final x = keyX + i * 8.0;
        final y = staffTop + (i.isEven ? 0 : 2) * lineSpacing;
        _drawAccidental(canvas, Offset(x, y), isFlat: isFlat, paint: keyPaint);
      }
    }

    final double noteX = size.width * 0.58;
    final double targetY = _midiToY(targetMidi, staffTop, lineSpacing);

    _drawLedgerLinesIfNeeded(canvas, noteX, targetY, staffTop, lineSpacing);

    final targetPaint = Paint()
      ..color = isInTune
          ? AppleViolinTheme.highVoltageLime
          : AppleViolinTheme.headline
      ..style = PaintingStyle.fill;

    _drawNoteHead(canvas, Offset(noteX, targetY), targetPaint, isHollow: false);
    _drawStem(canvas, Offset(noteX, targetY), targetPaint, lineSpacing, goUp: targetY > staffTop + lineSpacing * 2);

    if (playedMidi != null && playedMidi != targetMidi) {
      final double playedY = _midiToY(playedMidi!, staffTop, lineSpacing);
      final playedPaint = Paint()
        ..color = isScratching
            ? AppleViolinTheme.crimsonScratch
            : AppleViolinTheme.solarAmber
        ..style = PaintingStyle.fill;

      final playedX = noteX + 26;
      _drawLedgerLinesIfNeeded(canvas, playedX, playedY, staffTop, lineSpacing);
      _drawNoteHead(canvas, Offset(playedX, playedY), playedPaint, isHollow: true);
    }
  }

  double _midiToY(int midi, double staffTop, double spacing) {
    const int e4Midi = 64;
    final int semitonesFromE4 = midi - e4Midi;
    final double diatonicStep = semitonesFromE4 * 0.5;
    final double bottomLineY = staffTop + spacing * 4;
    return bottomLineY - diatonicStep * spacing;
  }

  void _drawLedgerLinesIfNeeded(Canvas canvas, double x, double y, double staffTop, double spacing) {
    final bottomLineY = staffTop + spacing * 4;
    final ledgerPaint = Paint()
      ..color = const Color(0x66FFFFFF)
      ..strokeWidth = 1.0;

    if (y > bottomLineY + spacing * 0.5) {
      double cur = bottomLineY + spacing;
      while (cur <= y + spacing * 0.4) {
        canvas.drawLine(Offset(x - 12, cur), Offset(x + 12, cur), ledgerPaint);
        cur += spacing;
      }
    } else if (y < staffTop - spacing * 0.5) {
      double cur = staffTop - spacing;
      while (cur >= y - spacing * 0.4) {
        canvas.drawLine(Offset(x - 12, cur), Offset(x + 12, cur), ledgerPaint);
        cur -= spacing;
      }
    }
  }

  void _drawNoteHead(Canvas canvas, Offset center, Paint paint, {required bool isHollow}) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(-0.35);

    final rect = Rect.fromCenter(center: Offset.zero, width: 11.5, height: 8.0);
    if (isHollow) {
      final strokePaint = Paint()
        ..color = paint.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;
      canvas.drawOval(rect, strokePaint);
    } else {
      canvas.drawOval(rect, paint);
    }
    canvas.restore();
  }

  void _drawStem(Canvas canvas, Offset noteCenter, Paint paint, double spacing, {required bool goUp}) {
    final stemPaint = Paint()
      ..color = paint.color
      ..strokeWidth = 1.3
      ..style = PaintingStyle.stroke;

    final stemX = goUp ? noteCenter.dx + 5.0 : noteCenter.dx - 5.0;
    final stemHeight = spacing * 3.2;
    final endY = goUp ? noteCenter.dy - stemHeight : noteCenter.dy + stemHeight;

    canvas.drawLine(Offset(stemX, noteCenter.dy), Offset(stemX, endY), stemPaint);
  }

  void _drawClef(Canvas canvas, Offset pos) {
    final tp = TextPainter(
      text: const TextSpan(
        text: '𝄞',
        style: TextStyle(
          fontFamily: 'serif',
          fontSize: 36,
          color: Color(0xCCFFFFFF),
          height: 1.0,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(pos.dx - 10, pos.dy - 22));
  }

  void _drawAccidental(Canvas canvas, Offset pos, {required bool isFlat, required Paint paint}) {
    final symbol = isFlat ? '♭' : '♯';
    final tp = TextPainter(
      text: TextSpan(
        text: symbol,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: paint.color,
          height: 1.0,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(pos.dx, pos.dy - 6));
  }

  @override
  bool shouldRepaint(covariant _ScaleStaffPainter old) {
    return old.targetMidi != targetMidi ||
        old.playedMidi != playedMidi ||
        old.isScratching != isScratching ||
        old.isInTune != isInTune;
  }
}
