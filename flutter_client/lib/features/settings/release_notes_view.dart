import 'dart:async';

import 'package:dpad/dpad.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/services/app_version_service.dart';
import 'package:m3u_tv/services/release_notes_service.dart';
import 'package:m3u_tv/shared/app_button.dart';
import 'package:m3u_tv/shared/app_callout.dart';
import 'package:m3u_tv/shared/dpad_ink_well.dart';
import 'package:m3u_tv/shared/gradient_border_effect.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

/// Settings "What's New" tab: browse the recent `m3u-tv` GitHub releases and
/// see how the running version compares to the latest one. Master/detail so a
/// remote drives it on one axis - Up/Down moves through versions on the left
/// rail (the notes pane follows the selection), Right steps into the notes to
/// scroll them, Left steps back.
class ReleaseNotesView extends StatefulWidget {
  const ReleaseNotesView({
    super.key,
    this.releaseNotesService,
    this.appVersionService,
  });

  /// Injectable for tests; a real [ReleaseNotesService] is used otherwise.
  final ReleaseNotesService? releaseNotesService;
  final AppVersionService? appVersionService;

  @override
  State<ReleaseNotesView> createState() => _ReleaseNotesViewState();
}

class _ReleaseNotesViewState extends State<ReleaseNotesView> {
  static const _githubReleasesUrl = 'https://github.com/m3ue/m3u-tv/releases';

  late final ReleaseNotesService _service =
      widget.releaseNotesService ?? ReleaseNotesService();
  late final AppVersionService _versionService =
      widget.appVersionService ?? AppVersionService();

  // Lets the notes pane hand focus back to the rail on a Left press (spatial
  // traversal from the tall notes pane otherwise skips past the narrow rail
  // up to the settings tab bar). The rail owns the per-row focus nodes.
  final _railKey = GlobalKey<_VersionRailState>();

  // Holding Down through the rail must not re-render the notes on every step
  // (that steals focus and stutters). The row under focus is applied after a
  // short settle so a fast scrub only renders the version it lands on.
  Timer? _selectionDebounce;
  int? _pendingSelection;

  bool _loading = true;
  List<ReleaseNote> _releases = const [];
  String? _currentVersion;
  int _selectedIndex = 0;
  int _autofocusIndex = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _selectionDebounce?.cancel();
    super.dispose();
  }

  void _requestSelection(int index) {
    _pendingSelection = index;
    _selectionDebounce?.cancel();
    _selectionDebounce = Timer(const Duration(milliseconds: 140), () {
      if (!mounted) return;
      final next = _pendingSelection;
      if (next != null && next != _selectedIndex) {
        setState(() => _selectedIndex = next);
      }
    });
  }

  Future<void> _load({bool forceRefresh = false}) async {
    setState(() => _loading = true);
    final releases = await _service.fetch(forceRefresh: forceRefresh);
    final current = await _versionService.currentVersion();
    if (!mounted) return;
    final initial = _initialIndex(releases, current);
    setState(() {
      _loading = false;
      _releases = releases;
      _currentVersion = current;
      _selectedIndex = initial;
      _autofocusIndex = initial;
    });
  }

  int _initialIndex(List<ReleaseNote> releases, String? current) {
    if (current == null) return 0;
    final i = releases.indexWhere((r) => r.normalizedVersion == current);
    return i >= 0 ? i : 0;
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

    final selected = _releases[_selectedIndex];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _VersionSummary(
          currentVersion: _currentVersion,
          latest: _releases.first,
          newerCount: _newerCount(),
          onOpenGithub: _openGithub,
        ),
        const SizedBox(height: 16),
        Expanded(
          child: DpadRegion(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 300,
                  child: _VersionRail(
                    key: _railKey,
                    releases: _releases,
                    selectedIndex: _selectedIndex,
                    autofocusIndex: _autofocusIndex,
                    currentVersion: _currentVersion,
                    onRowFocused: _requestSelection,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _NotesPane(
                    note: selected,
                    onFocusRail: () =>
                        _railKey.currentState?.focusSelectedRow(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  int _newerCount() {
    final current = _currentVersion;
    if (current == null) return 0;
    return _releases
        .where((r) => _isNewer(r.normalizedVersion, current))
        .length;
  }

  void _openGithub() {
    unawaited(
      launchUrl(
        Uri.parse(_githubReleasesUrl),
        mode: LaunchMode.externalApplication,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Header: running version vs. latest
// ---------------------------------------------------------------------------

class _VersionSummary extends StatelessWidget {
  const _VersionSummary({
    required this.currentVersion,
    required this.latest,
    required this.newerCount,
    required this.onOpenGithub,
  });

  final String? currentVersion;
  final ReleaseNote latest;
  final int newerCount;
  final VoidCallback onOpenGithub;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 600;
            final info = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l.settingsReleaseNotesYouAreOn(
                    currentVersion ?? l.unknown,
                  ),
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  l.settingsReleaseNotesLatestIs(latest.tag),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                if (newerCount > 0)
                  _Pill(
                    label: l.settingsReleaseNotesNewerCount(newerCount),
                    background: theme.colorScheme.primaryContainer,
                    foreground: theme.colorScheme.onPrimaryContainer,
                    icon: Icons.arrow_upward,
                  )
                else
                  _Pill(
                    label: l.settingsReleaseNotesUpToDate,
                    background: theme.colorScheme.secondaryContainer,
                    foreground: theme.colorScheme.onSecondaryContainer,
                    icon: Icons.check,
                  ),
              ],
            );

            if (wide) {
              return Row(
                children: [
                  Expanded(child: info),
                  const SizedBox(width: 16),
                  _GithubLink(wide: true, onOpen: onOpenGithub),
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                info,
                const SizedBox(height: 12),
                _GithubLink(wide: false, onOpen: onOpenGithub),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// TV can't tap a link and tvOS has no in-app browser, so wide/TV layouts get
/// a QR code (scan on a phone) and narrow/mobile layouts get an Open button -
/// same split `_AppReleaseLink` uses on the General tab.
class _GithubLink extends StatelessWidget {
  const _GithubLink({required this.wide, required this.onOpen});

  final bool wide;
  final VoidCallback onOpen;

  static const _url = 'https://github.com/m3ue/m3u-tv/releases';

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);

    if (wide) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: QrImageView(
              data: _url,
              size: 120,
              backgroundColor: Colors.white,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            l.settingsReleaseNotesViewOnGithub,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      );
    }
    return AppButton(
      icon: Icons.open_in_new,
      label: l.settingsReleaseNotesViewOnGithub,
      onPressed: onOpen,
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.background,
    required this.foreground,
    this.icon,
  });

  final String label;
  final Color background;
  final Color foreground;
  final IconData? icon;

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
          if (icon != null) ...[
            Icon(icon, size: 14, color: foreground),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Left rail: version list
// ---------------------------------------------------------------------------

class _VersionRail extends StatefulWidget {
  const _VersionRail({
    super.key,
    required this.releases,
    required this.selectedIndex,
    required this.autofocusIndex,
    required this.currentVersion,
    required this.onRowFocused,
  });

  final List<ReleaseNote> releases;
  final int selectedIndex;
  final int autofocusIndex;
  final String? currentVersion;

  /// Called with the row index whenever a row gains focus or is tapped.
  final ValueChanged<int> onRowFocused;

  @override
  State<_VersionRail> createState() => _VersionRailState();
}

class _VersionRailState extends State<_VersionRail> {
  // Fixed row height. The rows set autoScroll: false so D-pad focus never
  // nudges the enclosing tab PageView (the same bounce the DVR row actions
  // hit); this rail scrolls itself to keep the focused row centred.
  static const _rowExtent = 80.0;

  final _controller = ScrollController();

  // One stable node per row index, never swapped between rows, so the parent
  // rebuilding on selection never disturbs which row holds focus.
  final _rowNodes = <int, FocusNode>{};

  FocusNode _nodeFor(int index) => _rowNodes.putIfAbsent(
    index,
    () => FocusNode(debugLabel: 'release-notes/row-$index'),
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _reveal(widget.selectedIndex, animate: false),
    );
  }

  @override
  void dispose() {
    for (final node in _rowNodes.values) {
      node.dispose();
    }
    _controller.dispose();
    super.dispose();
  }

  /// Pulls D-pad focus back onto the selected row (from the notes pane's Left
  /// press). Centres it first in case it had scrolled out of view.
  void focusSelectedRow() {
    _reveal(widget.selectedIndex, animate: false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _nodeFor(widget.selectedIndex).requestFocus();
    });
  }

  void _reveal(int index, {bool animate = true}) {
    if (!_controller.hasClients) return;
    final position = _controller.position;
    final target =
        (index * _rowExtent - (position.viewportDimension - _rowExtent) / 2)
            .clamp(position.minScrollExtent, position.maxScrollExtent);
    if ((target - position.pixels).abs() < 0.5) return;
    if (animate) {
      unawaited(
        _controller.animateTo(
          target,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
        ),
      );
    } else {
      _controller.jumpTo(target);
    }
  }

  void _onRowFocused(int index) {
    _reveal(index);
    widget.onRowFocused(index);
  }

  @override
  Widget build(BuildContext context) {
    return DpadRegion(
      child: ListView.builder(
        controller: _controller,
        itemExtent: _rowExtent,
        itemCount: widget.releases.length,
        itemBuilder: (context, i) {
          final release = widget.releases[i];
          final normalized = release.normalizedVersion;
          final current = widget.currentVersion;
          final _RailBadge badge;
          if (current != null && normalized == current) {
            badge = _RailBadge.current;
          } else if (current != null && _isNewer(normalized, current)) {
            badge = _RailBadge.newer;
          } else {
            badge = _RailBadge.none;
          }
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _VersionRow(
              note: release,
              selected: i == widget.selectedIndex,
              badge: badge,
              autofocus: i == widget.autofocusIndex,
              focusNode: _nodeFor(i),
              onFocused: () => _onRowFocused(i),
              onTap: () => widget.onRowFocused(i),
            ),
          );
        },
      ),
    );
  }
}

enum _RailBadge { none, current, newer }

class _VersionRow extends StatelessWidget {
  const _VersionRow({
    required this.note,
    required this.selected,
    required this.badge,
    required this.autofocus,
    required this.focusNode,
    required this.onFocused,
    required this.onTap,
  });

  final ReleaseNote note;
  final bool selected;
  final _RailBadge badge;
  final bool autofocus;
  final FocusNode focusNode;

  /// Fires when this row gains D-pad focus (drives live selection).
  final VoidCallback onFocused;

  /// Fires on a Select press / tap.
  final VoidCallback onTap;

  static const _radius = BorderRadius.all(Radius.circular(8));
  static const _effects = [GradientBorderEffect(borderRadius: _radius)];

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final published = note.publishedAt;
    final dateLabel = published != null
        ? DateFormat.yMMMd(
            Localizations.localeOf(context).toLanguageTag(),
          ).format(published.toLocal())
        : null;

    return DpadInkWell(
      autofocus: autofocus,
      autoScroll: false,
      focusNode: focusNode,
      effects: _effects,
      borderRadius: _radius,
      color: selected
          ? theme.colorScheme.primaryContainer
          : theme.colorScheme.surfaceContainerHigh,
      onTap: onTap,
      // Focusing a row (D-pad Up/Down) drives the live selection; the parent
      // debounces so a held scroll only renders the version it settles on.
      onFocusChange: (focused) {
        if (focused) onFocused();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    note.tag.isNotEmpty ? note.tag : note.name,
                    maxLines: 1,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: selected
                          ? theme.colorScheme.onPrimaryContainer
                          : theme.colorScheme.onSurface,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (badge == _RailBadge.current)
                  _Pill(
                    label: l.settingsReleaseNotesCurrentBadge,
                    background: theme.colorScheme.secondary,
                    foreground: theme.colorScheme.onSecondary,
                  )
                else if (badge == _RailBadge.newer)
                  _Pill(
                    label: l.settingsReleaseNotesNewBadge,
                    background: theme.colorScheme.primary,
                    foreground: theme.colorScheme.onPrimary,
                  ),
              ],
            ),
            if (dateLabel != null) ...[
              const SizedBox(height: 2),
              Text(
                dateLabel,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: selected
                      ? theme.colorScheme.onPrimaryContainer.withValues(
                          alpha: 0.8,
                        )
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Right pane: scrollable rendered notes
// ---------------------------------------------------------------------------

class _NotesPane extends StatefulWidget {
  const _NotesPane({required this.note, required this.onFocusRail});

  final ReleaseNote note;

  /// Invoked on a Left press to hand focus back to the version rail.
  final VoidCallback onFocusRail;

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

  /// Left hands focus back to the rail; Up/Down scroll the notes and only
  /// release focus (return false) once scrolled to that end; Right is left
  /// to normal traversal.
  bool _onDirection(TraversalDirection direction) {
    if (direction == TraversalDirection.left) {
      widget.onFocusRail();
      return true;
    }
    if (!_scrollController.hasClients) return false;
    final position = _scrollController.position;
    const step = 160.0;
    switch (direction) {
      case TraversalDirection.up:
        if (position.pixels <= position.minScrollExtent + 0.5) return false;
        _animateTo(position.pixels - step);
        return true;
      case TraversalDirection.down:
        if (position.pixels >= position.maxScrollExtent - 0.5) return false;
        _animateTo(position.pixels + step);
        return true;
      case TraversalDirection.left:
      case TraversalDirection.right:
        return false;
    }
  }

  void _animateTo(double offset) {
    final position = _scrollController.position;
    unawaited(
      _scrollController.animateTo(
        offset.clamp(position.minScrollExtent, position.maxScrollExtent),
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final body = widget.note.body.trim();

    return DpadFocusable(
      onDirection: _onDirection,
      // The pane always fills the visible right half; revealing it would only
      // nudge the enclosing tab PageView and bounce.
      autoScroll: false,
      builder: (context, state, child) => DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: state.focused
                ? theme.colorScheme.primary
                : theme.colorScheme.outlineVariant,
            width: state.focused ? 2 : 1,
          ),
        ),
        child: child,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SingleChildScrollView(
          controller: _scrollController,
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.note.name,
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              if (body.isEmpty)
                Text(
                  l.settingsReleaseNotesNoneForVersion,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontStyle: FontStyle.italic,
                  ),
                )
              else
                _MarkdownBody(text: body),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Minimal Markdown renderer
// ---------------------------------------------------------------------------
//
// GitHub release bodies are simple: `##` headings, `-`/`*` bullets, `**bold**`,
// `` `code` ``, `[text](url)` and bare links. A full Markdown package pulls in
// its own focus/gesture handling that fights the D-pad focus model, so this
// renders just those constructs as plain non-interactive text.

class _MarkdownBody extends StatelessWidget {
  const _MarkdownBody({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lines = text.replaceAll('\r\n', '\n').split('\n');
    final blocks = <Widget>[];
    var inFence = false;
    final fenceBuffer = <String>[];

    void flushFence() {
      if (fenceBuffer.isEmpty) return;
      blocks.add(
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
        blocks.add(const SizedBox(height: 8));
        continue;
      }

      final heading = RegExp(r'^(#{1,6})\s+(.*)$').firstMatch(line);
      if (heading != null) {
        final level = heading.group(1)!.length;
        final content = heading.group(2)!;
        blocks.add(
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
        blocks.add(
          Padding(
            padding: EdgeInsets.only(left: 8.0 + indent * 4, top: 2, bottom: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$bullet ', style: theme.textTheme.bodyMedium),
                Expanded(
                  child: Text.rich(
                    _inlineSpans(
                      content,
                      context,
                      base: theme.textTheme.bodyMedium,
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
        blocks.add(const Divider(height: 20));
        continue;
      }

      if (line.trimLeft().startsWith('> ')) {
        blocks.add(
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
                base: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        );
        continue;
      }

      blocks.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Text.rich(
            _inlineSpans(line, context, base: theme.textTheme.bodyMedium),
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

  /// Parses `**bold**`, `*italic*` / `_italic_`, `` `code` ``, `[text](url)`
  /// and bare `http(s)://` links into styled (non-interactive) spans.
  TextSpan _inlineSpans(
    String text,
    BuildContext context, {
    TextStyle? base,
  }) {
    final theme = Theme.of(context);
    final effectiveBase = base ?? theme.textTheme.bodyMedium;
    final spans = <TextSpan>[];
    final pattern = RegExp(
      r'(\*\*([^*]+)\*\*)'
      '|(`([^`]+)`)'
      r'|(\[([^\]]+)\]\((https?:\/\/[^)]+)\))'
      r'|((?<![*_])[*_]([^*_\n]+)[*_](?![*_]))'
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
        spans.add(
          TextSpan(
            text: match.group(6),
            style: effectiveBase?.copyWith(color: theme.colorScheme.primary),
          ),
        );
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
            style: effectiveBase?.copyWith(color: theme.colorScheme.primary),
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
