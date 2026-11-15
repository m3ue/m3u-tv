import 'dart:async';

import 'package:m3u_tv/features/player/playback_controls.dart'
    show isHandheldLayout;
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/services/online_subtitle_service.dart';
import 'package:m3u_tv/shared/app_loading_indicator.dart';
import 'package:m3u_tv/shared/list_picker_sheet.dart';
import 'package:m3u_tv/shared/sort_option_row.dart';
import 'package:material_ui/material_ui.dart';

/// Searches, then lets the viewer pick a language and a release. Closes once
/// [onSelected] has finished. [onSelected] should throw on failure, which
/// leaves the picker open to try another.
Future<void> showOnlineSubtitlePicker(
  BuildContext context, {
  required Future<List<OnlineSubtitle>> Function() search,
  required Future<void> Function(OnlineSubtitle subtitle) onSelected,
  String? lastLanguage,
  ValueChanged<String>? onLanguagePicked,
}) {
  final l = AppLocalizations.of(context);
  return ListPickerSheet.show(
    context,
    title: l.playerOnlineSubtitlesTitle,
    cancelLabel: l.cancel,
    asDialog: !isHandheldLayout(context),
    autofocusIndex: -1,
    children: [
      OnlineSubtitleResults(
        search: search,
        onSelected: onSelected,
        lastLanguage: lastLanguage,
        onLanguagePicked: onLanguagePicked,
        deviceLanguage: Localizations.localeOf(context).languageCode,
      ),
    ],
  );
}

/// Languages in pick order: the last one used, then the device's, then by name.
@visibleForTesting
List<String> orderOnlineSubtitleLanguages(
  Iterable<OnlineSubtitle> subtitles, {
  String? lastLanguage,
  String? deviceLanguage,
}) {
  final deviceCode = deviceLanguage == null
      ? null
      : onlineSubtitleCodeForLocale(deviceLanguage);
  int rank(String code) {
    if (code == lastLanguage) return 0;
    if (code == deviceCode) return 1;
    return 2;
  }

  final languages = subtitles
      .map((subtitle) => subtitle.language)
      .toSet()
      .toList();
  return languages..sort((a, b) {
    final byRank = rank(a).compareTo(rank(b));
    if (byRank != 0) return byRank;
    return onlineSubtitleLanguageName(
      a,
    ).compareTo(onlineSubtitleLanguageName(b));
  });
}

class OnlineSubtitleResults extends StatefulWidget {
  const OnlineSubtitleResults({
    super.key,
    required this.search,
    required this.onSelected,
    this.lastLanguage,
    this.deviceLanguage,
    this.onLanguagePicked,
  });

  final Future<List<OnlineSubtitle>> Function() search;
  final Future<void> Function(OnlineSubtitle subtitle) onSelected;
  final String? lastLanguage;
  final String? deviceLanguage;
  final ValueChanged<String>? onLanguagePicked;

  @override
  State<OnlineSubtitleResults> createState() => _OnlineSubtitleResultsState();
}

class _OnlineSubtitleResultsState extends State<OnlineSubtitleResults> {
  List<OnlineSubtitle>? _results;
  List<String> _languages = const [];
  String? _language;
  bool _searchFailed = false;
  bool _applyFailed = false;
  bool _applying = false;

  @override
  void initState() {
    super.initState();
    unawaited(_search());
  }

  Future<void> _search() async {
    setState(() {
      _results = null;
      _searchFailed = false;
    });
    try {
      final results = await widget.search();
      if (!mounted) return;
      final languages = orderOnlineSubtitleLanguages(
        results,
        lastLanguage: widget.lastLanguage,
        deviceLanguage: widget.deviceLanguage,
      );
      setState(() {
        _results = results;
        _languages = languages;
        if (languages.length == 1) _language = languages.single;
      });
    } on Object catch (_) {
      if (mounted) setState(() => _searchFailed = true);
    }
  }

  void _pickLanguage(String language) {
    widget.onLanguagePicked?.call(language);
    setState(() {
      _language = language;
      _applyFailed = false;
    });
  }

  Future<void> _apply(OnlineSubtitle subtitle) async {
    setState(() {
      _applying = true;
      _applyFailed = false;
    });
    try {
      await widget.onSelected(subtitle);
      if (mounted) Navigator.of(context).pop();
    } on Object catch (_) {
      if (mounted) {
        setState(() {
          _applying = false;
          _applyFailed = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final results = _results;
    if (_searchFailed) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _Message(l.playerOnlineSubtitlesFailed),
          SortOptionRow(
            key: const ValueKey('online-subtitles-retry'),
            icon: Icons.refresh,
            label: l.playerOnlineSubtitlesRetry,
            autofocus: true,
            onTap: () => unawaited(_search()),
          ),
        ],
      );
    }
    if (results == null) return _Busy(l.playerOnlineSubtitlesSearching);
    if (_applying) return _Busy(l.playerOnlineSubtitlesLoading);
    if (results.isEmpty) {
      return Focus(
        autofocus: true,
        child: _Message(l.playerOnlineSubtitlesEmpty),
      );
    }
    final language = _language;
    if (language == null) {
      return Column(
        key: const ValueKey('online-subtitles-languages'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (index, code) in _languages.indexed)
            SortOptionRow(
              icon: Icons.language,
              label:
                  '${onlineSubtitleLanguageName(code)} '
                  '(${results.where((subtitle) => subtitle.language == code).length})',
              autofocus: index == 0,
              onTap: () => _pickLanguage(code),
            ),
        ],
      );
    }
    return Column(
      key: ValueKey('online-subtitles-releases-$language'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_applyFailed) _Message(l.playerOnlineSubtitlesFailed),
        if (_languages.length > 1)
          SortOptionRow(
            icon: Icons.arrow_back,
            label: l.playerOnlineSubtitlesAllLanguages,
            onTap: () => setState(() {
              _language = null;
              _applyFailed = false;
            }),
          ),
        for (final (index, subtitle)
            in results
                .where((subtitle) => subtitle.language == language)
                .indexed)
          SortOptionRow(
            icon: Icons.closed_caption,
            label: subtitle.release,
            autofocus: index == 0,
            onTap: () => unawaited(_apply(subtitle)),
          ),
      ],
    );
  }
}

class _Busy extends StatelessWidget {
  const _Busy(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    // Holds focus in the dialog, so Back still closes it while there's nothing
    // to select.
    return Focus(
      autofocus: true,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Row(
          children: [
            const SizedBox(
              width: 20,
              height: 20,
              child: AppLoadingIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 16),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Text(message),
    );
  }
}
