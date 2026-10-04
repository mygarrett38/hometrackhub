import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Background color of the launch screen. It matches the logo's own
/// background and the native launch screen set up by flutter_native_splash
/// in pubspec.yaml, so the handoff from the native screen is invisible.
const launchBackgroundColor = Color(0xFFF3F1EC);

/// Shows the HomeTrack Hub logo when the app opens, then reveals [child].
///
/// The transition has three parts:
/// 1. The logo holds still, exactly where the native launch screen drew it.
/// 2. The logo pulls back slightly, like taking a breath.
/// 3. The logo zooms toward the viewer and fades out while [child] is
///    revealed through a circle growing from the middle of the screen and
///    settles into place.
///
/// If the device asks for reduced motion, the logo simply fades into [child].
class LaunchScreen extends StatefulWidget {
  const LaunchScreen({super.key, required this.child});

  /// The app's main screen, shown once the launch animation finishes.
  final Widget child;

  /// The logo image. It is 1192px wide, drawn for 4x pixel density.
  static const logo = AssetImage('assets/images/logo.png');

  /// The logo's size on screen, matching the native launch screen, which
  /// draws the 4x image at a quarter of its pixel width.
  static const logoSize = 298.0;

  @override
  State<LaunchScreen> createState() => _LaunchScreenState();
}

class _LaunchScreenState extends State<LaunchScreen>
    with SingleTickerProviderStateMixin {
  static const _duration = Duration(milliseconds: 1800);
  static const _reducedMotionDuration = Duration(milliseconds: 400);

  // When each part of the animation happens, as a fraction of [_duration].
  static const _breathStart = 0.25;
  static const _revealStart = 0.42;
  static const _logoGoneAt = 0.75;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _duration,
  );

  late final Animation<double> _logoScale = TweenSequence<double>([
    TweenSequenceItem(tween: ConstantTween(1.0), weight: _breathStart),
    TweenSequenceItem(
      tween: Tween(
        begin: 1.0,
        end: 0.9,
      ).chain(CurveTween(curve: Curves.easeInOut)),
      weight: _revealStart - _breathStart,
    ),
    TweenSequenceItem(
      tween: Tween(
        begin: 0.9,
        end: 2.4,
      ).chain(CurveTween(curve: Curves.easeIn)),
      weight: 1 - _revealStart,
    ),
  ]).animate(_controller);

  late final Animation<double> _logoOpacity = Tween(begin: 1.0, end: 0.0)
      .animate(
        CurvedAnimation(
          parent: _controller,
          curve: const Interval(
            _revealStart,
            _logoGoneAt,
            curve: Curves.easeIn,
          ),
        ),
      );

  /// How far the circle revealing [LaunchScreen.child] has grown, from 0 to 1.
  late final Animation<double> _reveal = CurvedAnimation(
    parent: _controller,
    curve: const Interval(_revealStart, 1, curve: Curves.easeInOutCubic),
  );

  /// The main screen starts slightly enlarged and settles to its normal size.
  late final Animation<double> _childScale = Tween(begin: 1.08, end: 1.0)
      .animate(
        CurvedAnimation(
          parent: _controller,
          curve: const Interval(_revealStart, 1, curve: Curves.easeOutCubic),
        ),
      );

  bool _started = false;
  bool _reduceMotion = false;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    // Keep the native launch screen up until the logo image is ready, so
    // the logo doesn't blink while it loads.
    WidgetsBinding.instance.deferFirstFrame();
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        setState(() => _finished = true);
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;

    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (_reduceMotion) _controller.duration = _reducedMotionDuration;

    precacheImage(LaunchScreen.logo, context).whenComplete(() {
      WidgetsBinding.instance.allowFirstFrame();
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Once finished, only the main screen is drawn. Its widget stays at the
    // same place in the tree throughout, so it is never rebuilt from scratch.
    return ColoredBox(
      color: _finished ? Colors.transparent : launchBackgroundColor,
      child: AnimatedBuilder(
        animation: _controller,
        child: widget.child,
        builder: (context, child) {
          final showChild = _finished || _controller.value >= _revealStart;
          return Stack(
            fit: StackFit.expand,
            children: [
              if (showChild) _revealedChild(child!) else const SizedBox(),
              if (!_finished) _logoLayer(),
            ],
          );
        },
      ),
    );
  }

  Widget _revealedChild(Widget child) {
    if (_reduceMotion) {
      return Opacity(
        opacity: _finished ? 1 : 1 - _logoOpacity.value,
        child: child,
      );
    }
    return ClipPath(
      clipper: _CircleRevealClipper(_finished ? 1 : _reveal.value),
      clipBehavior: _finished ? Clip.none : Clip.antiAlias,
      child: Transform.scale(
        scale: _finished ? 1 : _childScale.value,
        child: child,
      ),
    );
  }

  Widget _logoLayer() {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      // Dark status bar icons on the light launch background.
      value: SystemUiOverlayStyle.dark,
      child: IgnorePointer(
        child: Center(
          child: Opacity(
            opacity: _logoOpacity.value,
            child: Transform.scale(
              scale: _reduceMotion ? 1 : _logoScale.value,
              child: const Image(
                image: LaunchScreen.logo,
                width: LaunchScreen.logoSize,
                height: LaunchScreen.logoSize,
                semanticLabel: 'HomeTrack Hub',
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Clips to a circle in the middle of the area. At a [fraction] of 1 the
/// circle reaches the corners, so nothing is clipped.
class _CircleRevealClipper extends CustomClipper<Path> {
  _CircleRevealClipper(this.fraction);

  final double fraction;

  @override
  Path getClip(Size size) {
    final center = size.center(Offset.zero);
    final radiusToCorner = center.distance;
    return Path()..addOval(
      Rect.fromCircle(center: center, radius: radiusToCorner * fraction),
    );
  }

  @override
  bool shouldReclip(_CircleRevealClipper oldClipper) =>
      oldClipper.fraction != fraction;
}
