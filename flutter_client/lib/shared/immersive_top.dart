import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:m3u_tv/shared/host_platform.dart';

/// What the iOS side reports while a detail screen holds the immersive top
/// (see `RunnerFlutterViewController` in ios/Runner/SceneDelegate.swift).
@immutable
class ImmersiveTopRegions {
  const ImmersiveTopRegions({
    required this.statusBarHidden,
    required this.occlusions,
  });

  factory ImmersiveTopRegions.fromMap(Map<Object?, Object?> map) {
    final rawOcclusions = map['occlusions'];
    return ImmersiveTopRegions(
      statusBarHidden: map['statusBarHidden'] == true,
      occlusions: [
        if (rawOcclusions is List)
          for (final raw in rawOcclusions)
            if (raw is List && raw.length == 4)
              Rect.fromLTWH(
                (raw[0] as num).toDouble(),
                (raw[1] as num).toDouble(),
                (raw[2] as num).toDouble(),
                (raw[3] as num).toDouble(),
              ),
      ],
    );
  }

  /// True only where the system would use a vertical bar (iPhone Duo folded,
  /// or unfolded in landscape): the status bar is hidden and the header may
  /// move up into its band.
  final bool statusBarHidden;

  /// Camera/sensor areas the header must stay clear of, margins included.
  final List<Rect> occlusions;
}

/// Publishes, while an item detail screen is up, whether the header may use
/// the status bar band (iOS keeps the status bar hidden wherever it would
/// otherwise be a tall band, see `RunnerFlutterViewController`) and the
/// occlusion regions it has to avoid there. Reference counted, as detail
/// routes stack (detail -> cast member -> detail).
class ImmersiveTopController {
  ImmersiveTopController({MethodChannel? channel, bool? enabled})
    : _channel = channel ?? const MethodChannel('m3u_tv/display_regions'),
      _enabled = enabled ?? (HostPlatform.isIOS && !HostPlatform.isTvOS);

  static final ImmersiveTopController instance = ImmersiveTopController();

  final MethodChannel _channel;
  final bool _enabled;
  int _holders = 0;
  bool _handlerInstalled = false;

  /// Null while no detail screen holds the request, or off iOS.
  final ValueNotifier<ImmersiveTopRegions?> regions = ValueNotifier(null);

  void acquire() {
    if (!_enabled) return;
    _installHandler();
    _holders++;
    if (_holders == 1) unawaited(_request(true));
  }

  void release() {
    if (!_enabled || _holders == 0) return;
    _holders--;
    if (_holders == 0) {
      regions.value = null;
      unawaited(_request(false));
    }
  }

  void _installHandler() {
    if (_handlerInstalled) return;
    _handlerInstalled = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'changed' && _holders > 0) {
        final arguments = call.arguments;
        if (arguments is Map) {
          regions.value = ImmersiveTopRegions.fromMap(arguments);
        }
      }
    });
  }

  Future<void> _request(bool enabled) async {
    try {
      final result = await _channel.invokeMethod<Map<Object?, Object?>>(
        'setImmersiveTop',
        enabled,
      );
      // A release can land while an acquire's reply is still in flight.
      if (enabled && _holders > 0 && result != null) {
        regions.value = ImmersiveTopRegions.fromMap(result);
      }
    } on MissingPluginException {
      // No phone window (CarPlay-only launch): nothing to hide.
    } on PlatformException {
      // Same: the request is cosmetic.
    }
  }
}

/// Top inset for a header made of a leading button and a centered title,
/// when [regions] lets it use the status bar band: just below every
/// occlusion it would overlap, or [minTop] when none is in the way. Null
/// when the band isn't available, so callers keep the normal safe area.
///
/// [headerSpans] are the header's horizontal extents (logical pixels from
/// the left edge); an occlusion only pushes the header down if it overlaps
/// one of them and starts above the header's bottom edge.
double? immersiveHeaderTop({
  required ImmersiveTopRegions? regions,
  required List<(double, double)> headerSpans,
  required double headerHeight,
  double minTop = 12,
}) {
  if (regions == null || !regions.statusBarHidden) return null;
  final occlusions = [...regions.occlusions]
    ..sort((a, b) => a.top.compareTo(b.top));
  var top = minTop;
  for (final occlusion in occlusions) {
    if (occlusion.top >= top + headerHeight) break;
    final overlapsHeader = headerSpans.any(
      (span) => occlusion.left < span.$2 && occlusion.right > span.$1,
    );
    if (overlapsHeader) top = math.max(top, occlusion.bottom);
  }
  return top;
}
