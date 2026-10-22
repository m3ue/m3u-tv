import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/shared/app_button.dart';
import 'package:m3u_tv/shared/host_platform.dart';
import 'package:m3u_tv/shared/qr_link_dialog.dart';
import 'package:url_launcher/url_launcher.dart';

/// tvOS has no `url_launcher` registration, so the Runner exposes its own
/// `UIApplication.open` bridge (see tvos/Runner/AppDelegate.swift).
const MethodChannel _tvosExternalUrlChannel = MethodChannel(
  'm3u_tv/external_url',
);

/// Opens a YouTube trailer outside the app rather than in the player, since
/// YouTube streams aren't playable through the app's own pipeline.
///
/// - Android (TV and phone), iOS: the YouTube app when installed (the system
///   routes youtube.com links to it), otherwise the browser.
/// - Desktop: the default browser.
/// - tvOS: the YouTube app via its URL scheme.
///
/// Falls back to a QR code when nothing on the device can open the link
/// (e.g. a TV with no YouTube app and no browser).
Future<void> openTrailer(BuildContext context, String url) async {
  final opened = await _launchExternally(url);
  if (opened || !context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => QrLinkDialog(
      title: AppLocalizations.of(dialogContext).trailerWatch,
      url: url,
      memoryKey: 'trailer-qr',
    ),
  );
}

Future<bool> _launchExternally(String url) async {
  try {
    if (HostPlatform.isTvOS) {
      final id = youtubeVideoId(url);
      final candidates = [
        if (id != null) 'youtube://watch/$id',
        if (id != null) 'youtube://www.youtube.com/watch?v=$id',
        if (id != null) 'vnd.youtube://$id',
        if (id != null) 'youtubetv://watch/$id',
        url,
      ];
      for (final candidate in candidates) {
        final reply = await _tvosExternalUrlChannel
            .invokeMapMethod<String, Object?>('open', {'url': candidate});
        debugPrint(
          '[Trailer] tvOS open $candidate: opened=${reply?['opened']} '
          'canOpen=${reply?['canOpen']}',
        );
        if (reply?['opened'] == true) return true;
      }
      return false;
    }
    final opened = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
    if (!opened) debugPrint('[Trailer] no app could open $url');
    return opened;
  } on PlatformException catch (error) {
    debugPrint('[Trailer] open failed for $url: $error');
    return false;
  } on MissingPluginException catch (error) {
    debugPrint('[Trailer] open unavailable for $url: $error');
    return false;
  }
}

/// "Trailer" action for a detail page's button row.
class TrailerButton extends StatelessWidget {
  const TrailerButton({super.key, required this.url, this.label});

  final String url;

  /// Overrides the default "Trailer" label (e.g. "Season 2 Trailer").
  final String? label;

  @override
  Widget build(BuildContext context) {
    return AppButton(
      icon: Icons.smart_display_outlined,
      label: label ?? AppLocalizations.of(context).trailerButton,
      onPressed: () => unawaited(openTrailer(context, url)),
      autoScroll: false,
    );
  }
}
