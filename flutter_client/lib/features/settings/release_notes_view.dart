import 'dart:async';
import 'dart:math' as math;

import 'package:dpad/dpad.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:m3u_tv/features/settings/settings_ui.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/services/app_version_service.dart';
import 'package:m3u_tv/services/release_notes_service.dart';
import 'package:m3u_tv/shared/app_button.dart';
import 'package:m3u_tv/shared/app_callout.dart';
import 'package:m3u_tv/shared/dpad_ink_well.dart';
import 'package:m3u_tv/shared/image_quality_scope.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

/// Settings "What's New" sub-page: read the `m3u-tv` GitHub release notes one
/// version at a time. A single full-width reading view driven on both axes -
/// Up/Down scrolls the notes, Left/Right steps to the older/newer version -
/// with a version header above it (arrows + a tappable title that opens a
/// version picker) for touch and for jumping straight to a version.
class ReleaseNotesView extends StatefulWidget {
  const ReleaseNotesView({
    super.key,
    this.releaseNotesService,
    this.appVersionService,
    this.isTv = false,
    this.onHandleTopLevelBack,
  });

  /// Injectable for tests; a real [ReleaseNotesService] is used otherwise.
  final ReleaseNotesService? releaseNotesService;
  final AppVersionService? appVersionService;

  /// TV can't open a link (and tvOS has no browser to hand off to), so the
  /// GitHub button shows a QR code to scan instead, and the remote hint row
  /// is shown under the notes.
  final bool isTv;

  /// Threaded into the pushed version picker so Android TV's hardware Back
  /// dedupes correctly (see `pushSettingsSubpage`).
  final bool Function()? onHandleTopLevelBack;

  @override
  State<ReleaseNotesView> createState() => _ReleaseNotesViewState();
}

class _ReleaseNotesViewState extends State<ReleaseNotesView> {
  static const _githubReleasesUrl = 'https://github.com/m3ue/m3u-tv/releases';

  late final ReleaseNotesService _service =
      widget.releaseNotesService ?? ReleaseNotesService();
  late final AppVersionService _versionService =
      widget.appVersionService ?? AppVersionService();

  final _notesFocusNode = FocusNode(debugLabel: 'release-notes/notes');
  final _versionButtonFocusNode = FocusNode(
    debugLabel: 'release-notes/version-button',
  );

  bool _loading = true;
  List<ReleaseNote> _releases = const [];
  String? _currentVersion;
  int _selectedIndex = 0;

  /// Expands the low-priority (maintenance/refactoring) sections. Kept for
  /// the whole visit so stepping between versions doesn't re-collapse them.
  bool _showAllSections = false;

  final _parsedByTag = <String, _StructuredNotes?>{};

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _notesFocusNode.dispose();
    _versionButtonFocusNode.dispose();
    super.dispose();
  }

  Future<void> _load({bool forceRefresh = false}) async {
    setState(() => _loading = true);
    final releases = await _service.fetch(forceRefresh: forceRefresh);
    final current = await _versionService.currentVersion();
    if (!mounted) return;
    setState(() {
      _loading = false;
      _releases = releases;
      _currentVersion = current;
      _parsedByTag.clear();
      _selectedIndex = _initialIndex(releases, current);
    });
  }

  int _initialIndex(List<ReleaseNote> releases, String? current) {
    if (current == null) return 0;
    final i = releases.indexWhere((r) => r.normalizedVersion == current);
    return i >= 0 ? i : 0;
  }

  _StructuredNotes? _structuredFor(ReleaseNote note) => _parsedByTag
      .putIfAbsent(note.tag, () => _StructuredNotes.tryParse(note.body));

  // Releases are newest-first, so "older" is the next index.
  bool get _hasOlder => _selectedIndex < _releases.length - 1;
  bool get _hasNewer => _selectedIndex > 0;

  void _select(int index) {
    if (index < 0 || index >= _releases.length || index == _selectedIndex) {
      return;
    }
    setState(() => _selectedIndex = index);
  }

  void _showOlder() => _select(_selectedIndex + 1);
  void _showNewer() => _select(_selectedIndex - 1);

  /// A header chevron press. Reaching the oldest/newest hides that chevron,
  /// so focus moves to the version title rather than being dropped.
  void _stepFromHeader({required bool older}) {
    older ? _showOlder() : _showNewer();
    if (older ? !_hasOlder : !_hasNewer) {
      _versionButtonFocusNode.requestFocus();
    }
  }

  _VersionBadge _badgeFor(ReleaseNote note) {
    final current = _currentVersion;
    if (current == null) return _VersionBadge.none;
    if (note.normalizedVersion == current) return _VersionBadge.current;
    if (_isNewer(note.normalizedVersion, current)) return _VersionBadge.newer;
    return _VersionBadge.none;
  }

  int _newerCount() {
    final current = _currentVersion;
    if (current == null) return 0;
    return _releases
        .where((r) => _isNewer(r.normalizedVersion, current))
        .length;
  }

  String _summaryFor(BuildContext context, ReleaseNote note) {
    final l = AppLocalizations.of(context);
    final parts = <String>[];
    final published = note.publishedAt;
    if (published != null) {
      parts.add(
        DateFormat.yMMMd(
          Localizations.localeOf(context).toLanguageTag(),
        ).format(published.toLocal()),
      );
    }
    final structured = _structuredFor(note);
    if (structured != null) {
      final features = structured.countOf(_SectionKind.features);
      final fixes = structured.countOf(_SectionKind.fixes);
      if (features > 0) parts.add(l.settingsReleaseNotesFeatureCount(features));
      if (fixes > 0) parts.add(l.settingsReleaseNotesFixCount(fixes));
    }
    return parts.join('  ·  ');
  }

  Future<void> _pickVersion() async {
    final picked = await pushSettingsSubpage<int>(
      context,
      title: (context) =>
          AppLocalizations.of(context).settingsReleaseNotesSelectVersion,
      onBack: widget.onHandleTopLevelBack,
      builder: (pageContext) => SettingsGroup(
        children: [
          for (var i = 0; i < _releases.length; i++)
            SettingsRow(
              title: _displayTag(_releases[i]),
              subtitle: _summaryFor(pageContext, _releases[i]),
              autofocus: i == _selectedIndex,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _BadgePill(badge: _badgeFor(_releases[i])),
                  if (i == _selectedIndex) ...[
                    const SizedBox(width: 8),
                    Icon(
                      Icons.check,
                      color: Theme.of(pageContext).colorScheme.primary,
                    ),
                  ],
                ],
              ),
              onTap: () => Navigator.of(pageContext).pop(i),
            ),
        ],
      ),
    );
    if (picked == null || !mounted) return;
    _select(picked);
    _notesFocusNode.requestFocus();
  }

  void _openGithub() {
    if (widget.isTv) {
      unawaited(
        showDialog<void>(
          context: context,
          builder: (_) => const _GithubQrDialog(url: _githubReleasesUrl),
        ),
      );
      return;
    }
    unawaited(
      launchUrl(
        Uri.parse(_githubReleasesUrl),
        mode: LaunchMode.externalApplication,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);

    if (_loading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(l.settingsReleaseNotesLoading),
          ],
        ),
      );
    }

    if (_releases.isEmpty) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppCallout(
                message: l.settingsReleaseNotesError,
                variant: AppCalloutVariant.error,
              ),
              const SizedBox(height: 16),
              AppButton(
                icon: Icons.refresh,
                label: l.settingsReleaseNotesRetry,
                autofocus: true,
                onPressed: () => _load(forceRefresh: true),
              ),
            ],
          ),
        ),
      );
    }

    final scale = FontSizeScope.scaleOf(context);
    final selected = _releases[_selectedIndex];

    return LayoutBuilder(
      builder: (context, constraints) {
        // One content column (readable line length on a wide TV) shared by
        // the header and the notes, so their edges line up. The notes'
        // scroll view spans the full width with the column centred inside
        // it, which puts the scrollbar in the gutter instead of eating into
        // the cards.
        final gutter = 16 * scale;
        final contentWidth = math.min(
          960 * scale,
          constraints.maxWidth - gutter * 2,
        );
        Widget column(Widget child) => Center(
          child: SizedBox(width: contentWidth, child: child),
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            column(
              _StatusBar(
                currentVersion: _currentVersion,
                newerCount: _newerCount(),
                isTv: widget.isTv,
                onOpenGithub: _openGithub,
              ),
            ),
            SizedBox(height: 12 * scale),
            column(
              _VersionHeader(
                title: _displayTag(selected),
                summary: _summaryFor(context, selected),
                badge: _badgeFor(selected),
                focusNode: _versionButtonFocusNode,
                onPick: _pickVersion,
                onOlder: _hasOlder ? () => _stepFromHeader(older: true) : null,
                onNewer: _hasNewer ? () => _stepFromHeader(older: false) : null,
              ),
            ),
            SizedBox(height: 16 * scale),
            Expanded(
              child: _NotesPane(
                note: selected,
                structured: _structuredFor(selected),
                contentWidth: contentWidth,
                showAllSections: _showAllSections,
                onShowAllSections: () =>
                    setState(() => _showAllSections = true),
                focusNode: _notesFocusNode,
                onOlder: _showOlder,
                onNewer: _showNewer,
                onReachTop: _versionButtonFocusNode.requestFocus,
              ),
            ),
            if (widget.isTv) ...[
              SizedBox(height: 12 * scale),
              const _RemoteHints(),
            ],
          ],
        );
      },
    );
  }
}

String _displayTag(ReleaseNote note) =>
    note.tag.isNotEmpty ? note.tag : note.name;

// ---------------------------------------------------------------------------
// Header: install status + version switcher
// ---------------------------------------------------------------------------

enum _VersionBadge { none, current, newer }

class _StatusBar extends StatelessWidget {
  const _StatusBar({
    required this.currentVersion,
    required this.newerCount,
    required this.isTv,
    required this.onOpenGithub,
  });

  final String? currentVersion;
  final int newerCount;
  final bool isTv;
  final VoidCallback onOpenGithub;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scale = FontSizeScope.scaleOf(context);
    final current = currentVersion;

    final status = switch ((newerCount, current)) {
      (_, null) => null,
      (0, _) => (
        Icons.check_circle_outline,
        theme.colorScheme.onSurfaceVariant,
        l.settingsReleaseNotesUpToDate,
      ),
      (final n, final version?) => (
        Icons.arrow_circle_up,
        theme.colorScheme.primary,
        '${l.settingsReleaseNotesNewerCount(n)}  ·  '
            '${l.settingsReleaseNotesYouAreOn(version)}',
      ),
    };

    return LayoutBuilder(
      builder: (context, constraints) {
        // Too narrow for the labelled button beside the status text.
        final compact = constraints.maxWidth < 640;
        return Row(
          children: [
            if (status != null) ...[
              Icon(status.$1, size: 20 * scale, color: status.$2),
              SizedBox(width: 8 * scale),
            ],
            Expanded(
              child: status == null
                  ? const SizedBox.shrink()
                  : Text(
                      status.$3,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: status.$2,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
            ),
            SizedBox(width: 12 * scale),
            if (compact)
              AppIconButton(
                icon: isTv ? Icons.qr_code_2 : Icons.open_in_new,
                tooltip: l.settingsReleaseNotesViewOnGithub,
                autoScroll: false,
                onPressed: onOpenGithub,
              )
            else
              AppButton(
                icon: isTv ? Icons.qr_code_2 : Icons.open_in_new,
                label: l.settingsReleaseNotesViewOnGithub,
                autoScroll: false,
                onPressed: onOpenGithub,
              ),
          ],
        );
      },
    );
  }
}

class _VersionHeader extends StatelessWidget {
  const _VersionHeader({
    required this.title,
    required this.summary,
    required this.badge,
    required this.focusNode,
    required this.onPick,
    required this.onOlder,
    required this.onNewer,
  });

  final String title;
  final String summary;
  final _VersionBadge badge;
  final FocusNode focusNode;
  final VoidCallback onPick;
  final VoidCallback? onOlder;
  final VoidCallback? onNewer;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scale = FontSizeScope.scaleOf(context);

    return Container(
      padding: EdgeInsets.all(8 * scale),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(kSettingsGroupRadius),
      ),
      child: Row(
        children: [
          _EdgeChevron(
            icon: Icons.chevron_left,
            tooltip: l.settingsReleaseNotesOlder,
            onPressed: onOlder,
          ),
          SizedBox(width: 8 * scale),
          Expanded(
            child: DpadInkWell(
              focusNode: focusNode,
              autoScroll: false,
              borderRadius: const BorderRadius.all(Radius.circular(10)),
              onTap: onPick,
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: 12 * scale,
                  vertical: 8 * scale,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (badge != _VersionBadge.none) ...[
                          SizedBox(width: 10 * scale),
                          Flexible(child: _BadgePill(badge: badge)),
                        ],
                        SizedBox(width: 4 * scale),
                        Icon(
                          Icons.expand_more,
                          size: 22 * scale,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ],
                    ),
                    if (summary.isNotEmpty) ...[
                      SizedBox(height: 2 * scale),
                      Text(
                        summary,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          SizedBox(width: 8 * scale),
          _EdgeChevron(
            icon: Icons.chevron_right,
            tooltip: l.settingsReleaseNotesNewer,
            onPressed: onNewer,
          ),
        ],
      ),
    );
  }
}

/// A header step button that disappears (keeping its space, so the title
/// stays centred) when there's no version further in that direction.
class _EdgeChevron extends StatelessWidget {
  const _EdgeChevron({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return ExcludeFocus(
      excluding: !enabled,
      child: Visibility(
        visible: enabled,
        maintainSize: true,
        maintainAnimation: true,
        maintainState: true,
        child: AppIconButton(
          icon: icon,
          tooltip: tooltip,
          autoScroll: false,
          onPressed: onPressed,
        ),
      ),
    );
  }
}

class _BadgePill extends StatelessWidget {
  const _BadgePill({required this.badge});

  final _VersionBadge badge;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return switch (badge) {
      _VersionBadge.none => const SizedBox.shrink(),
      _VersionBadge.current => _Pill(
        label: l.settingsReleaseNotesCurrentBadge,
        background: scheme.secondary,
        foreground: scheme.onSecondary,
      ),
      _VersionBadge.newer => _Pill(
        label: l.settingsReleaseNotesNewBadge,
        background: scheme.primary,
        foreground: scheme.onPrimary,
      ),
    };
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.background,
    required this.foreground,
  });

  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(50),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: foreground,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GithubQrDialog extends StatelessWidget {
  const _GithubQrDialog({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scale = FontSizeScope.scaleOf(context);

    return Dialog(
      child: DpadRegion(
        memoryKey: 'release-notes-github-qr',
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l.settingsReleaseNotesViewOnGithub,
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: QrImageView(
                  data: url,
                  size: 200 * scale,
                  backgroundColor: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                l.settingsAppScanQr,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              AppButton(
                label: MaterialLocalizations.of(context).closeButtonLabel,
                autofocus: true,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RemoteHints extends StatelessWidget {
  const _RemoteHints();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;
    final style = theme.textTheme.bodySmall?.copyWith(color: color);
    final iconSize = 18 * FontSizeScope.scaleOf(context);

    Widget hint(List<IconData> icons, String label) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final icon in icons) Icon(icon, size: iconSize, color: color),
        const SizedBox(width: 6),
        Text(label, style: style),
      ],
    );

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        hint([
          Icons.keyboard_arrow_left,
          Icons.keyboard_arrow_right,
        ], l.settingsReleaseNotesHintVersions),
        const SizedBox(width: 24),
        hint([
          Icons.keyboard_arrow_up,
          Icons.keyboard_arrow_down,
        ], l.settingsReleaseNotesHintScroll),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Notes: one focus target for the whole reading area
// ---------------------------------------------------------------------------

class _NotesPane extends StatefulWidget {
  const _NotesPane({
    required this.note,
    required this.structured,
    required this.contentWidth,
    required this.showAllSections,
    required this.onShowAllSections,
    required this.focusNode,
    required this.onOlder,
    required this.onNewer,
    required this.onReachTop,
  });

  final ReleaseNote note;

  /// Parsed sections, or null when the body isn't in the categorized
  /// changelog shape (rendered as plain Markdown instead).
  final _StructuredNotes? structured;

  /// Width of the page's content column; the notes are centred at this width
  /// inside a full-width scroll view.
  final double contentWidth;
  final bool showAllSections;
  final VoidCallback onShowAllSections;
  final FocusNode focusNode;
  final VoidCallback onOlder;
  final VoidCallback onNewer;

  /// Up pressed while already scrolled to the top: hand focus to the header.
  final VoidCallback onReachTop;

  @override
  State<_NotesPane> createState() => _NotesPaneState();
}

class _NotesPaneState extends State<_NotesPane> {
  final _scrollController = ScrollController();

  @override
  void didUpdateWidget(_NotesPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.note.tag != widget.note.tag && _scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  // Every direction is consumed so a press never falls through to spatial
  // traversal (which would land on the AppBar back button or nowhere).
  bool _onDirection(TraversalDirection direction) {
    switch (direction) {
      case TraversalDirection.left:
        widget.onOlder();
      case TraversalDirection.right:
        widget.onNewer();
      case TraversalDirection.up:
        if (!_scrollController.hasClients ||
            _scrollController.position.pixels <=
                _scrollController.position.minScrollExtent + 0.5) {
          widget.onReachTop();
        } else {
          _scrollBy(-_step);
        }
      case TraversalDirection.down:
        _scrollBy(_step);
    }
    return true;
  }

  double get _step =>
      (_scrollController.position.viewportDimension * 0.4).clamp(120.0, 400.0);

  void _scrollBy(double delta) {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    final target = (position.pixels + delta).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if ((target - position.pixels).abs() < 0.5) return;
    _scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final body = widget.note.body.trim();
    final structured = widget.structured;
    final hasCollapsed =
        structured != null &&
        !widget.showAllSections &&
        structured.collapsibleCount > 0;

    final Widget content;
    if (body.isEmpty) {
      content = Text(
        l.settingsReleaseNotesNoneForVersion,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontStyle: FontStyle.italic,
        ),
      );
    } else if (structured != null) {
      content = _StructuredNotesBody(
        notes: structured,
        showAll: widget.showAllSections,
        onShowAll: widget.onShowAllSections,
      );
    } else {
      content = SettingsCard(child: _MarkdownBody(text: body));
    }

    return DpadFocusable(
      focusNode: widget.focusNode,
      autofocus: true,
      // The pane always fills the page; revealing it would only jiggle it.
      autoScroll: false,
      // A tap should scroll/tap through (touch), not toggle sections.
      tapToSelect: false,
      onDirection: _onDirection,
      onSelect: hasCollapsed ? widget.onShowAllSections : null,
      builder: (context, state, child) => Scrollbar(
        controller: _scrollController,
        // The pane is the only thing focused while reading, so a visible
        // thumb is what tells a remote user where focus is.
        thumbVisibility: state.focused,
        child: child,
      ),
      child: SingleChildScrollView(
        controller: _scrollController,
        padding: const EdgeInsets.only(bottom: 24),
        child: Center(
          child: SizedBox(width: widget.contentWidth, child: content),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Structured changelog: categorized sections from the release body
// ---------------------------------------------------------------------------
//
// Every m3u-tv release body is the same generated shape:
//
//   ## What's Changed
//   ### Features
//   - Add something (`fae2f6e`)
//   - bump a dependency (#306) (`efa1234`)
//   ### Bug Fixes
//   ...
//
// so it's rendered as one card per category with the noise stripped (commit
// hashes, the redundant top heading) instead of as raw Markdown. Anything
// that doesn't fit falls back to [_MarkdownBody].

enum _SectionKind { features, fixes, performance, maintenance, other }

class _NotesItem {
  const _NotesItem(this.text, {this.refs = const [], this.bullet = true});

  final String text;

  /// PR/issue references pulled out of the line, e.g. `#306`.
  final List<String> refs;
  final bool bullet;
}

class _NotesSection {
  _NotesSection(this.title, this.kind);

  final String title;
  final _SectionKind kind;
  final items = <_NotesItem>[];

  /// Housekeeping sections start collapsed behind a "Show N more" row.
  bool get collapsible => kind == _SectionKind.maintenance;
}

class _StructuredNotes {
  const _StructuredNotes(this.sections);

  final List<_NotesSection> sections;

  int countOf(_SectionKind kind) => sections
      .where((s) => s.kind == kind)
      .fold(0, (sum, s) => sum + s.items.length);

  int get collapsibleCount => sections
      .where((s) => s.collapsible)
      .fold(0, (sum, s) => sum + s.items.length);

  static final _heading = RegExp(r'^(#{1,6})\s+(.*)$');
  static final _bullet = RegExp(r'^\s*(?:[-*+]|\d+\.)\s+(.*)$');
  static final _commitSuffix = RegExp(r'\s*\(`[0-9a-f]{7,40}`\)\s*$');
  static final _byAuthorPr = RegExp(
    r'\s+by\s+@[\w-]+\s+in\s+https?://\S+/pull/(\d+)\s*$',
  );
  static final _prRef = RegExp(r'\s*\(#(\d+)\)');

  /// Returns null when [body] isn't a categorized changelog (no category
  /// headings with items under them), so the caller can fall back.
  static _StructuredNotes? tryParse(String body) {
    if (body.contains('```')) return null;
    final sections = <_NotesSection>[];
    _NotesSection? current;

    for (final raw in body.replaceAll('\r\n', '\n').split('\n')) {
      final line = raw.trim();
      if (line.isEmpty || RegExp(r'^([-*_])\1{2,}$').hasMatch(line)) {
        continue;
      }
      if (line.startsWith('**Full Changelog**')) continue;

      final heading = _heading.firstMatch(line);
      if (heading != null) {
        final title = heading.group(2)!.trim();
        if (_isWhatsChanged(title)) continue;
        current = _NotesSection(title, _classify(title));
        sections.add(current);
        continue;
      }

      // Text before the first category heading - fall back rather than
      // guess where it belongs.
      if (current == null) return null;

      final bullet = _bullet.firstMatch(raw);
      if (bullet != null) {
        current.items.add(_cleanItem(bullet.group(1)!));
      } else {
        current.items.add(_NotesItem(line, bullet: false));
      }
    }

    sections.removeWhere((s) => s.items.isEmpty);
    if (sections.isEmpty) return null;
    return _StructuredNotes(sections);
  }

  static bool _isWhatsChanged(String title) =>
      title.toLowerCase().replaceAll('’', "'") == "what's changed";

  static _SectionKind _classify(String title) {
    final t = title.toLowerCase();
    if (t.contains('feat') || t.contains('new') || t.contains('enhance')) {
      return _SectionKind.features;
    }
    if (t.contains('fix') || t.contains('bug')) return _SectionKind.fixes;
    if (t.contains('perf')) return _SectionKind.performance;
    if (t.contains('maint') ||
        t.contains('refactor') ||
        t.contains('chore') ||
        t.contains('doc') ||
        t.contains('test') ||
        t.contains('depend')) {
      return _SectionKind.maintenance;
    }
    return _SectionKind.other;
  }

  static _NotesItem _cleanItem(String raw) {
    final refs = <String>[];
    var text = raw.replaceFirst(_commitSuffix, '');
    final byAuthor = _byAuthorPr.firstMatch(text);
    if (byAuthor != null) {
      refs.add('#${byAuthor.group(1)}');
      text = text.substring(0, byAuthor.start);
    }
    text = text.replaceAllMapped(_prRef, (m) {
      refs.add('#${m.group(1)}');
      return '';
    });
    text = text.replaceAll(RegExp(r'\s{2,}'), ' ').trim();
    if (text.isNotEmpty) {
      text = text[0].toUpperCase() + text.substring(1);
    }
    return _NotesItem(text, refs: refs);
  }
}

class _StructuredNotesBody extends StatelessWidget {
  const _StructuredNotesBody({
    required this.notes,
    required this.showAll,
    required this.onShowAll,
  });

  final _StructuredNotes notes;
  final bool showAll;
  final VoidCallback onShowAll;

  @override
  Widget build(BuildContext context) {
    final scale = FontSizeScope.scaleOf(context);
    final children = <Widget>[];
    for (final section in notes.sections) {
      if (children.isNotEmpty) children.add(SizedBox(height: 12 * scale));
      children.add(
        _SectionCard(
          section: section,
          collapsed: section.collapsible && !showAll,
          onShowAll: onShowAll,
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.section,
    required this.collapsed,
    required this.onShowAll,
  });

  final _NotesSection section;
  final bool collapsed;
  final VoidCallback onShowAll;

  (IconData, Color) _style(ColorScheme scheme) => switch (section.kind) {
    _SectionKind.features => (Icons.auto_awesome, scheme.primary),
    _SectionKind.fixes => (Icons.bug_report_outlined, scheme.tertiary),
    _SectionKind.performance => (Icons.bolt, scheme.secondary),
    _SectionKind.maintenance => (
      Icons.build_outlined,
      scheme.onSurfaceVariant,
    ),
    _SectionKind.other => (Icons.notes, scheme.onSurfaceVariant),
  };

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scale = FontSizeScope.scaleOf(context);
    final (icon, accent) = _style(theme.colorScheme);
    final minor = section.kind == _SectionKind.maintenance;
    final itemStyle =
        (minor ? theme.textTheme.bodyMedium : theme.textTheme.bodyLarge)
            ?.copyWith(
              color: minor ? theme.colorScheme.onSurfaceVariant : null,
              height: 1.35,
            );
    final refStyle = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final badgeSize = 30 * scale;
    final contentIndent = badgeSize + 12 * scale;

    return SettingsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: badgeSize,
                height: badgeSize,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 17 * scale, color: accent),
              ),
              SizedBox(width: 12 * scale),
              Flexible(
                child: Text(
                  section.title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              SizedBox(width: 8 * scale),
              Text(
                '${section.items.length}',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          SizedBox(height: 10 * scale),
          if (collapsed)
            Padding(
              padding: EdgeInsets.only(left: contentIndent - 12),
              // Not a focus stop - the notes pane is the one D-pad target,
              // and its Select press does the same thing.
              child: ExcludeFocus(
                child: TextButton.icon(
                  onPressed: onShowAll,
                  icon: const Icon(Icons.expand_more),
                  label: Text(
                    l.settingsReleaseNotesShowMore(section.items.length),
                  ),
                ),
              ),
            )
          else
            for (final item in section.items)
              Padding(
                padding: EdgeInsets.only(
                  left: item.bullet ? contentIndent - 14 * scale : 0,
                  top: 3 * scale,
                  bottom: 3 * scale,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (item.bullet)
                      Container(
                        width: 6 * scale,
                        height: 6 * scale,
                        margin: EdgeInsets.only(
                          top: (itemStyle?.fontSize ?? 16) * 0.55,
                          right: 8 * scale,
                        ),
                        decoration: BoxDecoration(
                          color: accent,
                          shape: BoxShape.circle,
                        ),
                      ),
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          children: [
                            _inlineSpans(item.text, context, base: itemStyle),
                            for (final ref in item.refs)
                              TextSpan(text: '  $ref', style: refStyle),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Minimal Markdown renderer (fallback)
// ---------------------------------------------------------------------------
//
// For release bodies that aren't the categorized changelog shape. Handles
// headings, bullets, rules, quotes, fences and inline styles as plain
// non-interactive text - a full Markdown package pulls in its own
// focus/gesture handling that fights the D-pad focus model.

class _MarkdownBody extends StatelessWidget {
  const _MarkdownBody({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lines = text.replaceAll('\r\n', '\n').split('\n');
    final blocks = <Widget>[];
    var inFence = false;
    var pendingGap = false;
    final fenceBuffer = <String>[];

    void add(Widget block) {
      // Collapse runs of blank lines into one paragraph gap, and never lead
      // with one.
      if (pendingGap && blocks.isNotEmpty) {
        blocks.add(const SizedBox(height: 8));
      }
      pendingGap = false;
      blocks.add(block);
    }

    void flushFence() {
      if (fenceBuffer.isEmpty) return;
      add(
        Container(
          width: double.infinity,
          margin: const EdgeInsets.symmetric(vertical: 6),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            fenceBuffer.join('\n'),
            style: theme.textTheme.bodySmall?.copyWith(
              fontFamily: 'monospace',
            ),
          ),
        ),
      );
      fenceBuffer.clear();
    }

    for (final raw in lines) {
      final line = raw.trimRight();

      if (line.trimLeft().startsWith('```')) {
        if (inFence) {
          flushFence();
          inFence = false;
        } else {
          inFence = true;
        }
        continue;
      }
      if (inFence) {
        fenceBuffer.add(raw);
        continue;
      }

      if (line.trim().isEmpty) {
        pendingGap = true;
        continue;
      }

      final heading = RegExp(r'^(#{1,6})\s+(.*)$').firstMatch(line);
      if (heading != null) {
        final level = heading.group(1)!.length;
        final content = heading.group(2)!;
        add(
          Padding(
            padding: EdgeInsets.only(top: blocks.isEmpty ? 0 : 12, bottom: 4),
            child: Text.rich(
              _inlineSpans(content, context, base: _headingStyle(theme, level)),
            ),
          ),
        );
        continue;
      }

      if (RegExp(r'^\s*([-*+]|\d+\.)\s+').hasMatch(line)) {
        final match = RegExp(r'^(\s*)([-*+]|\d+\.)\s+(.*)$').firstMatch(line)!;
        final indent = match.group(1)!.length;
        final marker = match.group(2)!;
        final content = match.group(3)!;
        final bullet = RegExp(r'^\d+\.').hasMatch(marker) ? marker : '•';
        add(
          Padding(
            padding: EdgeInsets.only(left: 8.0 + indent * 4, top: 2, bottom: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$bullet ', style: theme.textTheme.bodyLarge),
                Expanded(
                  child: Text.rich(
                    _inlineSpans(
                      content,
                      context,
                      base: theme.textTheme.bodyLarge,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
        continue;
      }

      if (RegExp(r'^\s*([-*_])\1{2,}\s*$').hasMatch(line)) {
        add(const Divider(height: 20));
        continue;
      }

      if (line.trimLeft().startsWith('> ')) {
        add(
          Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.only(left: 12),
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                  color: theme.colorScheme.outlineVariant,
                  width: 3,
                ),
              ),
            ),
            child: Text.rich(
              _inlineSpans(
                line.trimLeft().substring(2),
                context,
                base: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        );
        continue;
      }

      add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Text.rich(
            _inlineSpans(line, context, base: theme.textTheme.bodyLarge),
          ),
        ),
      );
    }

    if (inFence) flushFence();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: blocks,
    );
  }

  TextStyle? _headingStyle(ThemeData theme, int level) => switch (level) {
    1 => theme.textTheme.titleLarge,
    2 => theme.textTheme.titleMedium,
    _ => theme.textTheme.titleSmall,
  }?.copyWith(fontWeight: FontWeight.w700);
}

/// Parses `**bold**`, `*italic*` / `_italic_`, `` `code` ``, `[text](url)`
/// and bare `http(s)://` links into styled spans. Links render as plain text
/// (not link-coloured) since nothing here can open them.
TextSpan _inlineSpans(String text, BuildContext context, {TextStyle? base}) {
  final theme = Theme.of(context);
  final effectiveBase = base ?? theme.textTheme.bodyMedium;
  final spans = <TextSpan>[];
  final pattern = RegExp(
    r'(\*\*([^*]+)\*\*)'
    '|(`([^`]+)`)'
    r'|(\[([^\]]+)\]\((https?:\/\/[^)]+)\))'
    r'|((?<![*_\w])[*_]([^*_\n]+)[*_](?![*_\w]))'
    r'|(https?:\/\/[^\s)]+)',
  );

  var index = 0;
  for (final match in pattern.allMatches(text)) {
    if (match.start > index) {
      spans.add(
        TextSpan(
          text: text.substring(index, match.start),
          style: effectiveBase,
        ),
      );
    }
    if (match.group(2) != null) {
      spans.add(
        TextSpan(
          text: match.group(2),
          style: effectiveBase?.copyWith(fontWeight: FontWeight.w700),
        ),
      );
    } else if (match.group(4) != null) {
      spans.add(
        TextSpan(
          text: match.group(4),
          style: effectiveBase?.copyWith(
            fontFamily: 'monospace',
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
          ),
        ),
      );
    } else if (match.group(6) != null) {
      spans.add(TextSpan(text: match.group(6), style: effectiveBase));
    } else if (match.group(9) != null) {
      spans.add(
        TextSpan(
          text: match.group(9),
          style: effectiveBase?.copyWith(fontStyle: FontStyle.italic),
        ),
      );
    } else if (match.group(10) != null) {
      spans.add(
        TextSpan(
          text: match.group(10),
          style: effectiveBase?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    index = match.end;
  }
  if (index < text.length) {
    spans.add(TextSpan(text: text.substring(index), style: effectiveBase));
  }
  return TextSpan(children: spans);
}

// ---------------------------------------------------------------------------

int _compareVersion(String a, String b) {
  int part(String s) => int.tryParse(s.replaceAll(RegExp('[^0-9]'), '')) ?? 0;
  final pa = a.split('.').map(part).toList();
  final pb = b.split('.').map(part).toList();
  final length = pa.length > pb.length ? pa.length : pb.length;
  for (var i = 0; i < length; i++) {
    final x = i < pa.length ? pa[i] : 0;
    final y = i < pb.length ? pb[i] : 0;
    if (x != y) return x.compareTo(y);
  }
  return 0;
}

bool _isNewer(String candidate, String current) =>
    _compareVersion(candidate, current) > 0;
