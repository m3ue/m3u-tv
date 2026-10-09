import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Logo size the native launch screens show, in their own dp / pt.
///
/// Android pre-12 and iOS show a 409 px logo out of a 512 px / 128dp image;
/// Android 12+ draws `splash-icon-android12.png` at 288dp (192dp icon, 1.5x
/// for the adaptive-icon inset) with a 341 px logo out of 960, the same
/// ~102dp; the tvOS LaunchScreen.storyboard shows a 205pt logo - see
/// scripts/setup-icons.sh. [LaunchSplashHost] draws its logo at this size,
/// centred on the full screen like the native splashes, so the handover is
/// invisible.
double get launchSplashLogoSize =>
    Platform.operatingSystem == 'tvos' ? 205 : 128 * 409 / 512;

const MethodChannel _deviceInfoChannel = MethodChannel('m3u_tv/device_info');

/// The density Android drew the launch splash at. On Android TV it differs
/// from Flutter's devicePixelRatio: MainActivity overrides the app density so
/// layouts are 1920 logical px wide (1.0x on a 1080p SHIELD, where the system
/// splash is drawn at 2.0x). Null elsewhere, or on a stale native build.
Future<double?> _launchDensity() async {
  if (!Platform.isAndroid) return null;
  try {
    return await _deviceInfoChannel.invokeMethod<double>('getLaunchDensity');
  } on MissingPluginException {
    return null;
  } on PlatformException {
    return null;
  }
}

/// The native splash background (`color` in flutter_native_splash.yaml).
const Color launchSplashBackground = Color(0xFF0a0a0f);

/// Hands the real app to a running [LaunchSplashHost] and tells it when the
/// app has finished booting.
class LaunchSplashController extends ChangeNotifier {
  Widget? _app;
  Listenable? _bootState;
  bool Function()? _isBooting;

  Widget? get app => _app;
  Listenable? get bootState => _bootState;

  /// Whether the app is still booting. False before [attach].
  bool get isBooting => _isBooting?.call() ?? false;

  /// Builds [app] under the splash. The splash fades out
  /// [LaunchSplashHost.settle] after [isBooting] reports false following the
  /// app's first frame (re-checked whenever [bootState] notifies), or once
  /// [LaunchSplashHost.maxHold] runs out.
  void attach(
    Widget app, {
    required Listenable bootState,
    required bool Function() isBooting,
  }) {
    if (_app != null) return;
    _app = app;
    _bootState = bootState;
    _isBooting = isBooting;
    notifyListeners();
  }
}

/// Starts the app on an animated continuation of the native launch screen and
/// returns the controller to [LaunchSplashController.attach] the real app to
/// once startup work is done. Returns null (the caller should `runApp` the
/// app directly) if the logo can't be loaded.
///
/// The logo is decoded before `runApp` so the very first Flutter frame - the
/// one that removes the native splash - already has it in place.
Future<LaunchSplashController?> showLaunchSplash() async {
  final PictureInfo logo;
  try {
    logo = await vg.loadPicture(
      const SvgAssetLoader('assets/icons/logo.svg'),
      null,
    );
  } on Object catch (error) {
    debugPrint('[LaunchSplash] logo failed to load, skipping: $error');
    return null;
  }
  final controller = LaunchSplashController();
  runApp(
    LaunchSplashHost(
      controller: controller,
      logo: logo.picture,
      logoViewBox: logo.size,
      logoSize: launchSplashLogoSize,
      launchDensity: await _launchDensity(),
    ),
  );
  return controller;
}

/// Root widget while the app starts: the attached app (once there is one)
/// with the animated splash on top, until the app has booted.
///
/// The splash starts as an exact copy of the native launch screen (logo only,
/// at rest), then eases in a soft pulsing glow, a gentle breathing scale and a
/// gradient arc circling the logo. On dismissal it fades out with a slight
/// zoom, then leaves the tree entirely, so nothing keeps ticking afterwards.
/// With the OS "remove animations" setting on it stays a still logo and is
/// removed without a fade.
///
/// Everything is a few gradient-filled primitives on one small
/// [RepaintBoundary] - no blur, no fragment shader, no image decode - so it
/// costs next to nothing on low-end Android TV boxes.
class LaunchSplashHost extends StatefulWidget {
  const LaunchSplashHost({
    required this.controller,
    required this.logo,
    required this.logoViewBox,
    required this.logoSize,
    this.launchDensity,
    this.maxHold = const Duration(seconds: 10),
    this.settle = const Duration(seconds: 1),
    super.key,
  });

  final LaunchSplashController controller;

  /// The logo, drawn at [logoSize] wide. Disposed once the splash is gone.
  final ui.Picture logo;
  final Size logoViewBox;

  /// The native splash's logo size, in its own dp / pt.
  final double logoSize;

  /// Physical pixels per dp the native splash was drawn at, when that isn't
  /// Flutter's devicePixelRatio (see [_launchDensity]). Null means they match.
  final double? launchDensity;

  /// Longest the splash waits on boot after the app is attached. A slow or
  /// unreachable server must not trap the user on it - past this the app's
  /// own loading states (and Settings) take over.
  final Duration maxHold;

  /// Extra time the splash stays up once boot is done, so the start page has
  /// laid out and its first posters and logos have loaded before it is
  /// revealed, instead of popping in under the fade.
  final Duration settle;

  @override
  State<LaunchSplashHost> createState() => _LaunchSplashHostState();
}

class _LaunchSplashHostState extends State<LaunchSplashHost>
    with TickerProviderStateMixin {
  static const _exitDuration = Duration(milliseconds: 450);

  late final Ticker _ticker = createTicker(_onTick);
  final ValueNotifier<double> _seconds = ValueNotifier(0);
  late final AnimationController _exit = AnimationController(
    vsync: this,
    duration: _exitDuration,
  );
  late final Animation<double> _opacity = ReverseAnimation(
    CurvedAnimation(parent: _exit, curve: Curves.easeOut),
  );

  Widget? _app;
  Listenable? _bootState;
  Timer? _holdTimer;
  Timer? _settleTimer;
  bool _bootCheckScheduled = false;
  bool _dismissing = false;
  bool _removed = false;
  bool _logoDisposed = false;

  // Startup jank report, logged once on removal (see [_logFrameStats]).
  final Stopwatch _shownFor = Stopwatch()..start();
  Duration? _attachedAt;
  int _frames = 0;
  int _slowFrames = 0;
  Duration _worstBuild = Duration.zero;
  Duration _worstRaster = Duration.zero;
  Duration _worstWait = Duration.zero;
  int? _firstVsyncMicros;
  // The slowest few frames as (ms since the splash's first frame, timing), to
  // tell the app's first build apart from boot's later rebuilds.
  final List<(int, ui.FrameTiming)> _slowest = [];

  bool get _animationsDisabled => WidgetsBinding
      .instance
      .platformDispatcher
      .accessibilityFeatures
      .disableAnimations;

  @override
  void initState() {
    super.initState();
    _exit.addStatusListener((status) {
      if (status == AnimationStatus.completed) _remove();
    });
    if (!_animationsDisabled) _ticker.start();
    SchedulerBinding.instance.addTimingsCallback(_onFrameTimings);
    widget.controller.addListener(_onControllerChanged);
    _app = widget.controller.app;
    if (_app != null) _watchBoot();
  }

  @override
  void dispose() {
    if (!_removed) {
      SchedulerBinding.instance.removeTimingsCallback(_onFrameTimings);
    }
    widget.controller.removeListener(_onControllerChanged);
    _bootState?.removeListener(_scheduleBootCheck);
    _holdTimer?.cancel();
    _settleTimer?.cancel();
    _ticker.dispose();
    _exit.dispose();
    _seconds.dispose();
    _disposeLogo();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    _seconds.value = elapsed.inMicroseconds / Duration.microsecondsPerSecond;
  }

  void _onFrameTimings(List<ui.FrameTiming> timings) {
    for (final timing in timings) {
      _frames++;
      if (timing.totalSpan > const Duration(milliseconds: 33)) _slowFrames++;
      if (timing.buildDuration > _worstBuild) {
        _worstBuild = timing.buildDuration;
      }
      if (timing.rasterDuration > _worstRaster) {
        _worstRaster = timing.rasterDuration;
      }
      // Vsync to build start: time the UI thread was busy with something
      // else (startup work, boot) when the frame was due.
      if (timing.vsyncOverhead > _worstWait) _worstWait = timing.vsyncOverhead;
      final vsync = timing.timestampInMicroseconds(ui.FramePhase.vsyncStart);
      final offsetMs = (vsync - (_firstVsyncMicros ??= vsync)) ~/ 1000;
      _slowest
        ..add((offsetMs, timing))
        ..sort((a, b) => b.$2.totalSpan.compareTo(a.$2.totalSpan));
      if (_slowest.length > 5) _slowest.removeLast();
    }
  }

  void _logFrameStats() {
    String ms(Duration duration) => '${duration.inMilliseconds}ms';
    const mode = kReleaseMode
        ? 'release'
        : kProfileMode
        ? 'profile'
        : 'debug, not representative';
    String describe((int, ui.FrameTiming) frame) {
      final (offsetMs, timing) = frame;
      return '@${offsetMs}ms build ${ms(timing.buildDuration)} wait '
          '${ms(timing.vsyncOverhead)} raster ${ms(timing.rasterDuration)}';
    }

    final slowest = _slowest.map(describe).join('; ');
    debugPrint(
      '[LaunchSplash] ($mode) shown ${ms(_shownFor.elapsed)} '
      '(app attached at ${_attachedAt == null ? '-' : ms(_attachedAt!)}), '
      '$_frames frames, $_slowFrames over 33ms; worst build '
      '${ms(_worstBuild)}, raster ${ms(_worstRaster)}, '
      'UI thread wait ${ms(_worstWait)}; slowest: $slowest',
    );
  }

  void _onControllerChanged() {
    final app = widget.controller.app;
    if (_app != null || app == null) return;
    _attachedAt = _shownFor.elapsed;
    setState(() => _app = app);
    _watchBoot();
  }

  void _watchBoot() {
    _bootState = widget.controller.bootState?..addListener(_scheduleBootCheck);
    _holdTimer = Timer(widget.maxHold, _dismiss);
    _scheduleBootCheck();
  }

  /// Checks boot state after the next frame. Deferred because AppShell starts
  /// boot() from initState, so its first notification lands mid-build - and
  /// the first check has to wait for the app's first frame anyway, which is
  /// where boot() flips isBootstrapping on.
  void _scheduleBootCheck() {
    if (_bootCheckScheduled || _dismissing) return;
    _bootCheckScheduled = true;
    SchedulerBinding.instance
      ..addPostFrameCallback((_) {
        _bootCheckScheduled = false;
        if (mounted && !widget.controller.isBooting) {
          _settleTimer ??= Timer(widget.settle, _dismiss);
        }
      })
      ..ensureVisualUpdate();
  }

  void _dismiss() {
    if (_dismissing || !mounted) return;
    _dismissing = true;
    _holdTimer?.cancel();
    _settleTimer?.cancel();
    _bootState?.removeListener(_scheduleBootCheck);
    _bootState = null;
    if (_animationsDisabled) {
      _remove();
    } else {
      _exit.forward();
    }
  }

  void _remove() {
    if (_removed || !mounted) return;
    _ticker.stop();
    SchedulerBinding.instance.removeTimingsCallback(_onFrameTimings);
    _logFrameStats();
    setState(() => _removed = true);
    // The painter holding the picture is gone after this frame.
    SchedulerBinding.instance.addPostFrameCallback((_) => _disposeLogo());
  }

  void _disposeLogo() {
    if (_logoDisposed) return;
    _logoDisposed = true;
    widget.logo.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Same physical size as the native splash's logo, in Flutter's pixels.
    final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
    final logoSize =
        widget.logoSize *
        (widget.launchDensity ?? devicePixelRatio) /
        devicePixelRatio;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // A fixed first slot, so attaching the app never shifts the
          // splash's element (and restarts its animation).
          _app ?? const SizedBox.shrink(),
          if (!_removed)
            AbsorbPointer(
              child: FadeTransition(
                opacity: _opacity,
                child: ColoredBox(
                  color: launchSplashBackground,
                  child: Center(
                    child: RepaintBoundary(
                      child: SizedBox.square(
                        dimension: logoSize * 2.6,
                        child: CustomPaint(
                          painter: LaunchSplashPainter(
                            logo: widget.logo,
                            logoViewBox: widget.logoViewBox,
                            logoSize: logoSize,
                            seconds: _seconds,
                            exit: _exit,
                          ),
                        ),
                      ),
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

/// Paints the splash logo with its glow, breathing scale and loading arc.
///
/// At `seconds == 0` it paints the logo alone at rest, matching the native
/// launch screen; the effects ease in over the first [introSeconds].
@visibleForTesting
class LaunchSplashPainter extends CustomPainter {
  LaunchSplashPainter({
    required this.logo,
    required this.logoViewBox,
    required this.logoSize,
    required this.seconds,
    required this.exit,
  }) : super(repaint: Listenable.merge([seconds, exit]));

  static const double introSeconds = 0.6;
  static const double breathSeconds = 2.4;
  static const double spinSeconds = 1.3;

  // The logo's own gradient colour, and the app's primary (focus border and
  // sidebar accent) for the arc's tail.
  static const Color _rose = Color(0xFFff2056);
  static const Color _indigo = Color(0xFF4f39f6);

  /// The lowest 8-bit alpha step: invisible on the dark background, but not
  /// transparent, so Skia still runs (and compiles) the draw.
  static const double _primeAlpha = 1 / 255;

  final ui.Picture logo;
  final Size logoViewBox;
  final double logoSize;
  final ValueListenable<double> seconds;
  final Animation<double> exit;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final time = seconds.value;
    final intro = Curves.easeOut.transform(
      (time / introSeconds).clamp(0.0, 1.0),
    );
    // 0 at rest, 1 at full breath; starts at rest so frame one matches the
    // native splash.
    final breath = (1 - math.cos(2 * math.pi * time / breathSeconds)) / 2;
    final out = Curves.easeOut.transform(exit.value);
    final effects = intro * (1 - out);

    // Painted even at zero strength (floored to [_primeAlpha]) so the very
    // first frame, still identical to the native splash, already uses the
    // glow and arc gradients: on Skia (Android < 12, Fire TV) compiling those
    // shaders took 80-150ms per effect on a SHIELD, a visible hitch when they
    // first faded in mid-animation. Paid on frame one instead, it only keeps
    // the native splash up a moment longer.
    _paintGlow(canvas, center, breath, effects);
    _paintArc(canvas, center, time, breath, out, effects);

    final scale =
        (1 + 0.035 * breath * intro) *
        (1 + 0.1 * out) *
        logoSize /
        logoViewBox.width;
    canvas
      ..save()
      ..translate(center.dx, center.dy)
      ..scale(scale)
      ..translate(-logoViewBox.width / 2, -logoViewBox.height / 2)
      ..drawPicture(logo)
      ..restore();
  }

  void _paintGlow(Canvas canvas, Offset center, double breath, double effects) {
    final alpha = math.max((0.1 + 0.14 * breath) * effects, _primeAlpha);
    final radius = logoSize * (1.05 + 0.08 * breath);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(
          colors: [
            _rose.withValues(alpha: alpha),
            _rose.withValues(alpha: alpha * 0.35),
            _rose.withValues(alpha: 0),
          ],
          stops: const [0, 0.5, 1],
        ).createShader(Rect.fromCircle(center: center, radius: radius)),
    );
  }

  void _paintArc(
    Canvas canvas,
    Offset center,
    double time,
    double breath,
    double out,
    double effects,
  ) {
    final radius = logoSize * (0.66 + 0.12 * out);
    final strokeWidth = math.max(2, logoSize * 0.026).toDouble();
    final arcAlpha = math.max(effects, _primeAlpha);
    final rect = Rect.fromCircle(center: center, radius: radius);

    // Faint full track.
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..color = Colors.white.withValues(alpha: 0.06 * effects),
    );

    // Spinning arc fading in from a transparent tail to a rose head. Butt
    // caps, since a round tail cap would pick up the head colour across the
    // sweep gradient's seam; the head gets its own round dot instead.
    final sweep = 2 * math.pi * (0.22 + 0.08 * breath);
    final start = 2 * math.pi * time / spinSeconds - math.pi / 2;
    canvas.drawArc(
      rect,
      start,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..shader = SweepGradient(
          endAngle: sweep,
          colors: [
            _indigo.withValues(alpha: 0),
            _indigo.withValues(alpha: arcAlpha),
            _rose.withValues(alpha: arcAlpha),
          ],
          stops: const [0, 0.45, 1],
          transform: GradientRotation(start),
        ).createShader(rect),
    );
    final headAngle = start + sweep;
    canvas.drawCircle(
      center + Offset(math.cos(headAngle), math.sin(headAngle)) * radius,
      strokeWidth / 2,
      Paint()..color = _rose.withValues(alpha: arcAlpha),
    );
  }

  @override
  bool shouldRepaint(LaunchSplashPainter oldDelegate) =>
      oldDelegate.logo != logo ||
      oldDelegate.logoSize != logoSize ||
      oldDelegate.seconds != seconds ||
      oldDelegate.exit != exit;
}
