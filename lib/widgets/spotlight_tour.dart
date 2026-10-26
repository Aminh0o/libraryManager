import 'package:flutter/material.dart';
import '../ui/app_tokens.dart';

/// One step in an interactive spotlight walkthrough.
class SpotlightStep {
  final GlobalKey targetKey;
  final String title;
  final String description;
  final EdgeInsets padding;
  final BorderRadius borderRadius;

  const SpotlightStep({
    required this.targetKey,
    required this.title,
    required this.description,
    this.padding = const EdgeInsets.all(8),
    this.borderRadius = const BorderRadius.all(Radius.circular(12)),
  });
}

/// An interactive spotlight walkthrough overlay matching the modern
/// cutout-with-dashed-border design.
class SpotlightTourOverlay extends StatefulWidget {
  final List<SpotlightStep> steps;
  final VoidCallback onFinish;
  final VoidCallback? onSkip;

  const SpotlightTourOverlay({
    super.key,
    required this.steps,
    required this.onFinish,
    this.onSkip,
  });

  /// Displays the interactive spotlight tour as a modal overlay on top of the
  /// current route.
  static Future<void> show(
    BuildContext context, {
    required List<SpotlightStep> steps,
    VoidCallback? onComplete,
  }) {
    if (steps.isEmpty) return Future.value();
    final navigator = Navigator.of(context, rootNavigator: true);
    return navigator.push(
      PageRouteBuilder(
        opaque: false,
        barrierDismissible: false,
        transitionDuration: const Duration(milliseconds: 250),
        reverseTransitionDuration: const Duration(milliseconds: 200),
        pageBuilder: (context, anim, secAnim) {
          return FadeTransition(
            opacity: anim,
            child: SpotlightTourOverlay(
              steps: steps,
              onFinish: () {
                navigator.pop();
                onComplete?.call();
              },
              onSkip: () {
                navigator.pop();
                onComplete?.call();
              },
            ),
          );
        },
      ),
    );
  }

  @override
  State<SpotlightTourOverlay> createState() => _SpotlightTourOverlayState();
}

class _SpotlightTourOverlayState extends State<SpotlightTourOverlay>
    with SingleTickerProviderStateMixin {
  int _currentIndex = 0;
  Rect? _targetRect;
  late AnimationController _animCtrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _anim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeInOut);
    WidgetsBinding.instance.addPostFrameCallback((_) => _measureCurrentStep());
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  void _measureCurrentStep() {
    if (_currentIndex >= widget.steps.length) return;
    final step = widget.steps[_currentIndex];
    final keyContext = step.targetKey.currentContext;

    if (keyContext != null) {
      final box = keyContext.findRenderObject() as RenderBox?;
      if (box != null && box.hasSize && mounted) {
        final origin = box.localToGlobal(Offset.zero);
        final size = box.size;
        final rawRect = origin & size;
        final padded = Rect.fromLTRB(
          rawRect.left - step.padding.left,
          rawRect.top - step.padding.top,
          rawRect.right + step.padding.right,
          rawRect.bottom + step.padding.bottom,
        );
        setState(() {
          _targetRect = padded;
        });
        _animCtrl.forward(from: 0.0);
        return;
      }
    }

    // Fallback if target element is offscreen or not mounted
    final media = MediaQuery.of(context);
    setState(() {
      _targetRect = Rect.fromCenter(
        center: Offset(media.size.width / 2, media.size.height / 3),
        width: 200,
        height: 80,
      );
    });
    _animCtrl.forward(from: 0.0);
  }

  void _nextStep() {
    if (_currentIndex < widget.steps.length - 1) {
      setState(() {
        _currentIndex++;
      });
      _measureCurrentStep();
    } else {
      widget.onFinish();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_currentIndex >= widget.steps.length) {
      return const SizedBox.shrink();
    }
    final step = widget.steps[_currentIndex];
    final screenSize = MediaQuery.of(context).size;
    final target = _targetRect;

    // Determine tooltip position (above or below the target)
    final bool showBelow =
        target == null || target.bottom < screenSize.height * 0.65;
    final double cardTop = showBelow
        ? (target != null ? target.bottom + 16 : screenSize.height * 0.4)
        : (target.top - 180);

    final double cardLeft = target != null
        ? (target.center.dx - 160).clamp(
            16.0,
            (screenSize.width - 336).clamp(16.0, screenSize.width),
          )
        : (screenSize.width - 320) / 2;

    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          // Semi-transparent scrim with spotlight cutout
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _nextStep,
              child: CustomPaint(
                painter: _SpotlightPainter(
                  targetRect: target,
                  borderRadius: step.borderRadius,
                  animation: _anim,
                ),
              ),
            ),
          ),

          // Floating Tooltip Bubble
          if (target != null)
            Positioned(
              top: cardTop,
              left: cardLeft,
              child: FadeTransition(
                opacity: _anim,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: showBelow
                        ? const Offset(0, 0.1)
                        : const Offset(0, -0.1),
                    end: Offset.zero,
                  ).animate(_anim),
                  child: _TourTooltipCard(
                    step: step,
                    stepNumber: _currentIndex + 1,
                    totalSteps: widget.steps.length,
                    isLastStep: _currentIndex == widget.steps.length - 1,
                    pointsUp: showBelow,
                    caretDx: (target.center.dx - cardLeft).clamp(24.0, 296.0),
                    onNext: _nextStep,
                  ),
                ),
              ),
            ),

          // Floating Dismiss / Close (X) button at bottom right (per design reference)
          Positioned(
            right: 28,
            bottom: 28,
            child: Material(
              color: Colors.black.withValues(alpha: 0.6),
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: widget.onSkip ?? widget.onFinish,
                child: Container(
                  width: 48,
                  height: 48,
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.close,
                    color: Colors.white,
                    size: AppIcon.lg,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Renders the darkened scrim with a smooth rounded cutout and dashed white border.
class _SpotlightPainter extends CustomPainter {
  final Rect? targetRect;
  final BorderRadius borderRadius;
  final Animation<double> animation;

  _SpotlightPainter({
    required this.targetRect,
    required this.borderRadius,
    required this.animation,
  }) : super(repaint: animation);

  @override
  void paint(Canvas canvas, Size size) {
    final backgroundPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.65)
      ..style = PaintingStyle.fill;

    final screenPath = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height));

    if (targetRect == null) {
      canvas.drawPath(screenPath, backgroundPaint);
      return;
    }

    final cutoutRRect = RRect.fromRectAndCorners(
      targetRect!,
      topLeft: borderRadius.topLeft,
      topRight: borderRadius.topRight,
      bottomLeft: borderRadius.bottomLeft,
      bottomRight: borderRadius.bottomRight,
    );

    final cutoutPath = Path()..addRRect(cutoutRRect);
    final combined = Path.combine(
      PathOperation.difference,
      screenPath,
      cutoutPath,
    );
    canvas.drawPath(combined, backgroundPaint);

    // Draw dashed white border around spotlighted item
    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    _drawDashedRRect(canvas, cutoutRRect, borderPaint);
  }

  void _drawDashedRRect(Canvas canvas, RRect rrect, Paint paint) {
    final path = Path()..addRRect(rrect);
    final metrics = path.computeMetrics();
    const dashWidth = 6.0;
    const dashSpace = 4.0;

    for (final metric in metrics) {
      double distance = 0.0;
      while (distance < metric.length) {
        final double length = (distance + dashWidth < metric.length)
            ? dashWidth
            : metric.length - distance;
        final extract = metric.extractPath(distance, distance + length);
        canvas.drawPath(extract, paint);
        distance += dashWidth + dashSpace;
      }
    }
  }

  @override
  bool shouldRepaint(_SpotlightPainter oldDelegate) {
    return oldDelegate.targetRect != targetRect ||
        oldDelegate.borderRadius != borderRadius ||
        oldDelegate.animation.value != animation.value;
  }
}

/// The speech bubble tooltip card containing the tutorial explanation, step counter,
/// and Next/OK button.
class _TourTooltipCard extends StatelessWidget {
  final SpotlightStep step;
  final int stepNumber;
  final int totalSteps;
  final bool isLastStep;
  final bool pointsUp;
  final double caretDx;
  final VoidCallback onNext;

  const _TourTooltipCard({
    required this.step,
    required this.stepNumber,
    required this.totalSteps,
    required this.isLastStep,
    required this.pointsUp,
    required this.caretDx,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _BubblePointerPainter(
        pointsUp: pointsUp,
        caretDx: caretDx,
        bubbleColor: Colors.white,
      ),
      child: Container(
        width: 320,
        margin: EdgeInsets.only(
          top: pointsUp ? 8 : 0,
          bottom: pointsUp ? 0 : 8,
        ),
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (step.title.isNotEmpty) ...[
              Text(
                step.title,
                style: const TextStyle(
                  color: Color(0xFF1E293B),
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
            ],
            Text(
              step.description,
              style: const TextStyle(
                color: Color(0xFF475569),
                fontSize: 13,
                height: 1.4,
                fontWeight: FontWeight.w400,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '$stepNumber/$totalSteps',
                  style: const TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                FilledButton(
                  onPressed: onNext,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF1E293B),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg,
                      vertical: AppSpacing.xs,
                    ),
                  ),
                  child: Text(
                    isLastStep ? 'OK' : 'Next',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Paints the small triangular caret pointing from the bubble towards the spotlighted element.
class _BubblePointerPainter extends CustomPainter {
  final bool pointsUp;
  final double caretDx;
  final Color bubbleColor;

  const _BubblePointerPainter({
    required this.pointsUp,
    required this.caretDx,
    required this.bubbleColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = bubbleColor
      ..style = PaintingStyle.fill;

    final path = Path();
    const caretWidth = 14.0;
    const caretHeight = 8.0;

    if (pointsUp) {
      path.moveTo(caretDx - caretWidth / 2, caretHeight);
      path.lineTo(caretDx, 0);
      path.lineTo(caretDx + caretWidth / 2, caretHeight);
      path.close();
    } else {
      path.moveTo(caretDx - caretWidth / 2, size.height - caretHeight);
      path.lineTo(caretDx, size.height);
      path.lineTo(caretDx + caretWidth / 2, size.height - caretHeight);
      path.close();
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_BubblePointerPainter oldDelegate) {
    return oldDelegate.pointsUp != pointsUp ||
        oldDelegate.caretDx != caretDx ||
        oldDelegate.bubbleColor != bubbleColor;
  }
}
