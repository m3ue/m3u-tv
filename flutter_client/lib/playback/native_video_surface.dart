import 'dart:async' show unawaited;
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show Factory;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show PlatformViewHitTestBehavior;
import 'package:flutter/services.dart';

import 'package:m3u_tv/playback/player_adapter.dart';

/// Renders whichever of [platformView] (a `PlatformViewProvider`-backed
/// native mpv core), [nativePlane] (a `NativePlaneProvider`-backed backend
/// rendering through a native surface outside Flutter's compositor, e.g. the
/// Linux Wayland video plane), or [textureId] (a `VideoTextureProvider`-
/// backed backend) is active, or a black placeholder while none is
/// available yet. Shared by `PlayerScreen`'s `_VideoSurface` and
/// `MultiviewScreen`'s `_TileVideoSurface`.
class NativeVideoSurface extends StatelessWidget {
  const NativeVideoSurface({
    super.key,
    required this.textureId,
    required this.platformView,
    required this.aspectRatio,
    this.nativePlane,
    this.wrapInBlackBackground = true,
  });

  final int? textureId;
  final PlatformViewProvider? platformView;
  final NativePlaneProvider? nativePlane;
  final double aspectRatio;

  /// Whether to wrap the platform-view/texture surface in its own black
  /// [ColoredBox]. Callers that already paint a black background behind
  /// this widget (e.g. a Multiview tile's own container) should pass
  /// `false` to avoid an extra, redundant paint layer.
  final bool wrapInBlackBackground;

  @override
  Widget build(BuildContext context) {
    final plane = nativePlane;
    if (plane != null && plane.usesNativePlane) {
      return _wrap(
        Center(
          child: AspectRatio(
            aspectRatio: aspectRatio,
            child: _NativePlaneReporter(plane: plane),
          ),
        ),
      );
    }
    final view = platformView;
    if (view != null) {
      final child = Platform.isMacOS
          ? AppKitView(
              viewType: view.platformViewType,
              creationParams: view.platformViewCreationParams,
              creationParamsCodec: const StandardMessageCodec(),
            )
          : Platform.isAndroid
          ? _androidHybridCompositionView(view)
          : UiKitView(
              viewType: view.platformViewType,
              creationParams: view.platformViewCreationParams,
              creationParamsCodec: const StandardMessageCodec(),
            );
      return _wrap(
        Center(
          child: AspectRatio(aspectRatio: aspectRatio, child: child),
        ),
      );
    }
    final id = textureId;
    if (id == null) {
      // Neither a platform view nor a texture is available yet -- normal
      // while a backend is still loading, but also what a MultiviewBackend
      // that forgot to implement either PlatformViewProvider or
      // VideoTextureProvider would render: an indistinguishable black
      // surface with no diagnostic. If this ever needs to be told apart
      // from normal loading, a backend implementing neither interface is
      // the thing to check for here.
      return const ColoredBox(color: Colors.black);
    }
    return _wrap(
      Center(
        child: AspectRatio(
          aspectRatio: aspectRatio,
          child: Texture(textureId: id),
        ),
      ),
    );
  }

  Widget _wrap(Widget child) {
    if (!wrapInBlackBackground) return child;
    return ColoredBox(color: Colors.black, child: child);
  }

  /// `AndroidMpvBackend`'s platform view hosts a raw `SurfaceView` (mpv
  /// draws into it directly via `attachSurface`) -- Flutter's default
  /// `AndroidView` composition mode captures platform-view content into an
  /// offscreen buffer, which a `SurfaceView` bypasses entirely by
  /// compositing straight through to the system compositor, so its content
  /// never appears there. Explicit Hybrid Composition (this
  /// `PlatformViewLink`/`initSurfaceAndroidView` shape) is Flutter's
  /// documented mechanism for embedding a `SurfaceView` correctly.
  Widget _androidHybridCompositionView(PlatformViewProvider view) {
    return PlatformViewLink(
      viewType: view.platformViewType,
      surfaceFactory: (context, controller) {
        return AndroidViewSurface(
          controller: controller as AndroidViewController,
          gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{},
          hitTestBehavior: PlatformViewHitTestBehavior.opaque,
        );
      },
      onCreatePlatformView: (params) {
        final controller = PlatformViewsService.initSurfaceAndroidView(
          id: params.id,
          viewType: view.platformViewType,
          layoutDirection: TextDirection.ltr,
          creationParams: view.platformViewCreationParams,
          creationParamsCodec: const StandardMessageCodec(),
          onFocus: () => params.onFocusChanged(true),
        )..addOnPlatformViewCreatedListener(params.onPlatformViewCreated);
        unawaited(controller.create());
        return controller;
      },
    );
  }
}

/// Reports this widget's on-screen rect to [plane] on every layout, and
/// paints fully transparent -- the actual video is a native surface (e.g. a
/// Wayland `wl_subsurface`) stacked outside Flutter's own compositor, which
/// only shows through where Flutter itself paints nothing.
class _NativePlaneReporter extends StatefulWidget {
  const _NativePlaneReporter({required this.plane});

  final NativePlaneProvider plane;

  @override
  State<_NativePlaneReporter> createState() => _NativePlaneReporterState();
}

class _NativePlaneReporterState extends State<_NativePlaneReporter> {
  final GlobalKey _key = GlobalKey();

  void _reportRect(Duration _) {
    if (!mounted) return;
    final renderObject = _key.currentContext?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return;
    final topLeft = renderObject.localToGlobal(Offset.zero);
    final size = renderObject.size;
    final devicePixelRatio = MediaQuery.of(context).devicePixelRatio;
    widget.plane.reportVideoRect(
      topLeft.dx * devicePixelRatio,
      topLeft.dy * devicePixelRatio,
      size.width * devicePixelRatio,
      size.height * devicePixelRatio,
      devicePixelRatio,
    );
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback(_reportRect);
    return SizedBox.expand(
      key: _key,
      child: const ColoredBox(color: Colors.transparent),
    );
  }
}
