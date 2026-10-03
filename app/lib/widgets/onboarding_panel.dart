import 'package:flutter/material.dart';

import '../app_theme.dart';
import 'glass_panel.dart';

class OnboardingPanel extends StatefulWidget {
  const OnboardingPanel({super.key, required this.onAllow});

  final Future<void> Function() onAllow;

  @override
  State<OnboardingPanel> createState() => _OnboardingPanelState();
}

class _OnboardingPanelState extends State<OnboardingPanel>
    with SingleTickerProviderStateMixin {
  bool _busy = false;
  late final AnimationController _fadeController;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _fade = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOutCubic,
    );
    _slide = Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero)
        .animate(
          CurvedAnimation(parent: _fadeController, curve: Curves.easeOutCubic),
        );
    _fadeController.forward();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  Future<void> _handleAllow() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.onAllow();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Scaffold(
      backgroundColor: colors.voidBg,
      body: SafeArea(
        child: FadeTransition(
          opacity: _fade,
          child: SlideTransition(
            position: _slide,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: Column(
                children: [
                  const Spacer(flex: 2),
                  GlassPanel(
                    blur: 28,
                    opacity: 0.9,
                    borderRadius: BorderRadius.circular(28),
                    padding: const EdgeInsets.fromLTRB(28, 36, 28, 32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: colors.mark,
                            boxShadow: [
                              BoxShadow(
                                color: colors.mark.withValues(alpha: 0.35),
                                blurRadius: 24,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: Icon(
                            Icons.route_rounded,
                            color: colors.onMark,
                            size: 34,
                          ),
                        ),
                        const SizedBox(height: 28),
                        Text(
                          'Дорожный Пульс',
                          style: TextStyle(
                            fontFamily: AppTheme.fontDisplay,
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.6,
                            color: colors.ink,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Дорожный Пульс требует доступ к GPS и фоновой работе, '
                          'чтобы строить карту ям в реальном времени',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: AppTheme.fontUi,
                            fontSize: 15,
                            height: 1.45,
                            fontWeight: FontWeight.w500,
                            color: colors.ink2,
                          ),
                        ),
                        const SizedBox(height: 32),
                        _MagneticAllowButton(
                          busy: _busy,
                          onPressed: _handleAllow,
                        ),
                      ],
                    ),
                  ),
                  const Spacer(flex: 3),
                  Text(
                    'Данные используются только для карты дефектов',
                    style: TextStyle(
                      fontFamily: AppTheme.fontUi,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: colors.ink3,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MagneticAllowButton extends StatefulWidget {
  const _MagneticAllowButton({required this.onPressed, required this.busy});

  final VoidCallback onPressed;
  final bool busy;

  @override
  State<_MagneticAllowButton> createState() => _MagneticAllowButtonState();
}

class _MagneticAllowButtonState extends State<_MagneticAllowButton> {
  Offset _offset = Offset.zero;
  bool _pressed = false;

  static const double _maxPull = 10;

  void _onHover(PointerEvent event, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final local = event.localPosition;
    final delta = local - center;
    final distance = delta.distance;
    if (distance < 1) {
      setState(() => _offset = Offset.zero);
      return;
    }
    final pull = (distance / 80).clamp(0.0, 1.0) * _maxPull;
    setState(() => _offset = Offset.fromDirection(delta.direction, pull));
  }

  void _reset() {
    setState(() {
      _offset = Offset.zero;
      _pressed = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, 56);
        return MouseRegion(
          onHover: (e) => _onHover(e, size),
          onExit: (_) => _reset(),
          child: GestureDetector(
            onTapDown: (_) => setState(() => _pressed = true),
            onTapUp: (_) {
              setState(() => _pressed = false);
              if (!widget.busy) widget.onPressed();
            },
            onTapCancel: _reset,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              transform: Matrix4.identity()
                ..translateByDouble(
                  _offset.dx,
                  _offset.dy + (_pressed ? 1.0 : 0.0),
                  0,
                  1,
                )
                ..scaleByDouble(
                  _pressed ? 0.97 : 1.0,
                  _pressed ? 0.97 : 1.0,
                  1,
                  1,
                ),
              transformAlignment: Alignment.center,
              width: double.infinity,
              height: 56,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                color: colors.mark,
                boxShadow: [
                  BoxShadow(
                    color: colors.mark.withValues(alpha: _pressed ? 0.25 : 0.4),
                    blurRadius: _pressed ? 12 : 22,
                    offset: Offset(0, _pressed ? 4 : 10),
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: widget.busy
                  ? SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: colors.onMark,
                      ),
                    )
                  : Text(
                      'Разрешить и начать',
                      style: TextStyle(
                        fontFamily: AppTheme.fontUi,
                        color: colors.onMark,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                      ),
                    ),
            ),
          ),
        );
      },
    );
  }
}
