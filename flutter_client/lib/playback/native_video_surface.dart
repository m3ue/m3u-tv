import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:m3u_tv/playback/player_adapter.dart';

/// Renders whichever of [platformView] (a `PlatformViewProvider`-backed
/// native mpv core) or [textureId] (a `VideoTextureProvider`-backed
/// backend) is active, or a black placeholder while neither is available
/// yet. Shared by `PlayerScreen`'s `_VideoSurface` and
/// `MultiviewScreen`'s `_TileVideoSurface`.
class NativeVideoSurface extends StatelessWidget {
  const NativeVideoSurface({
    super.key,
    required this.textureId,
    required this.platformView,
    required this.aspectRatio,
    this.wrapInBlackBackground = true,
  });

  final int? textureId;
  final PlatformViewProvider? platformView;
  final double aspectRatio;

  /// Whether to wrap the platform-view/texture surface in its own black
  /// [ColoredBox]. Callers that already paint a black background behind
  /// this widget (e.g. a Multiview tile's own container) should pass
  /// `false` to avoid an extra, redundant paint layer.
  final bool wrapInBlackBackground;

  @override
  Widget build(BuildContext context) {
    final view = platformView;
    if (view != null) {
      final child = Platform.isMacOS
          ? AppKitView(
              viewType: view.platformViewType,
              creationParams: view.platformViewCreationParams,
              creationParamsCodec: const StandardMessageCodec(),
            )
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
}
