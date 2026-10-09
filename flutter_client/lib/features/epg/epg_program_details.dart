import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:m3u_tv/features/epg/epg_recording_state.dart';
import 'package:m3u_tv/features/epg/program_recording_indicator.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/epg_service.dart';
import 'package:m3u_tv/shared/app_button.dart';
import 'package:m3u_tv/shared/cached_media_thumbnail.dart';
import 'package:m3u_tv/shared/epg_icon_pill.dart';
import 'package:m3u_tv/shared/image_quality_scope.dart';

/// What activating (OK / tap) the guide's selection does.
enum EpgGuideAction {
  /// Tune the channel: the programme is airing, or there is no programme.
  watchLive,

  /// Start the catchup stream for a finished, still-retained programme.
  watchReplay,

  /// Open the channel's options (record, favorite, ...) for a programme
  /// that hasn't started yet.
  options,

  /// A finished programme with no catchup: nothing to play.
  none,
}

/// The guide cursor's target resolved against "now", so the preview panel,
/// the mobile details sheet and OK/tap activation all agree on what the
/// programme is and what selecting it does.
class EpgGuideSelection {
  const EpgGuideSelection({
    required this.channel,
    required this.program,
    required this.now,
    this.recordingState = EpgRecordingState.none,
  });

  final Channel channel;

  /// Null when the row has no programme at the cursor (no EPG data).
  final EpgProgram? program;
  final DateTime now;
  final EpgRecordingState recordingState;

  int get catchupRetentionDays => EpgService.effectiveCatchupRetentionDays(
    channel.catchupSupported,
    channel.catchupDays,
  );

  bool get isLive {
    final p = program;
    return p != null && !now.isBefore(p.start) && now.isBefore(p.end);
  }

  bool get isUpcoming => program?.start.isAfter(now) ?? false;

  bool get canReplay {
    final p = program;
    return p != null && EpgService.canReplay(catchupRetentionDays, p, now);
  }

  bool get hasProgramInfo => program != null && !program!.isPlaceholder;

  double get progress {
    final p = program;
    if (p == null) return 0;
    final total = p.end.difference(p.start).inSeconds;
    if (total <= 0) return 0;
    return (now.difference(p.start).inSeconds / total).clamp(0, 1).toDouble();
  }

  EpgGuideAction get action {
    final p = program;
    if (p == null || isLive) return EpgGuideAction.watchLive;
    if (canReplay) return EpgGuideAction.watchReplay;
    // The editor's filler blocks have nothing to record, so they tune the
    // channel like a row with no EPG data. Past ones still replay: catchup
    // is by time range, so the archive is real either way.
    if (p.isPlaceholder) return EpgGuideAction.watchLive;
    if (isUpcoming) return EpgGuideAction.options;
    return EpgGuideAction.none;
  }
}

String epgDurationLabel(AppLocalizations l10n, Duration duration) {
  final total = math.max(1, duration.inMinutes);
  if (total < 60) return l10n.epgDurationMinutes(total);
  final hours = total ~/ 60;
  final minutes = total % 60;
  return minutes == 0
      ? l10n.epgDurationHours(hours)
      : l10n.epgDurationHoursMinutes(hours, minutes);
}

String epgTimeLabel(BuildContext context, DateTime time) => DateFormat.jm(
  Localizations.localeOf(context).toLanguageTag(),
).format(time.toLocal());

String epgTimeRangeLabel(BuildContext context, EpgProgram program) =>
    '${epgTimeLabel(context, program.start)} - '
    '${epgTimeLabel(context, program.end)}';

/// "S2 E5", "Episode 5" or "Season 2", or null when the source carries no
/// episode numbering.
String? epgEpisodeLabel(AppLocalizations l10n, EpgProgram program) {
  final season = program.season;
  final episode = program.episode;
  if (season != null && episode != null) {
    return l10n.epgSeasonEpisode(season, episode);
  }
  if (episode != null) return l10n.epgEpisodeNumber(episode);
  if (season != null) return l10n.epgSeasonNumber(season);
  return null;
}

/// "Today" / "Tomorrow" / "Yesterday", else the localized weekday name.
String epgRelativeDayLabel(
  BuildContext context,
  DateTime day,
  DateTime today,
) {
  final l10n = AppLocalizations.of(context);
  final a = DateTime(day.year, day.month, day.day);
  final b = DateTime(today.year, today.month, today.day);
  // Calendar-day difference that ignores a DST hour either way.
  final delta = (a.difference(b).inHours / 24).round();
  return switch (delta) {
    0 => l10n.epgToday,
    1 => l10n.epgTomorrow,
    -1 => l10n.epgYesterday,
    _ => DateFormat.EEEE(
      Localizations.localeOf(context).toLanguageTag(),
    ).format(day),
  };
}

/// The guide's top preview panel on TV/desktop: artwork beside the
/// programme's status, title, episode, metadata chips and description.
class EpgProgramPreview extends StatelessWidget {
  const EpgProgramPreview({
    super.key,
    required this.selection,
    this.showKeyHints = true,
    this.okAction,
    this.okPreviews = false,
    this.canOpenOptions = true,
    this.artwork,
  });

  final EpgGuideSelection selection;

  /// Remote-control hints ("OK Watch live", "Hold OK More options").
  final bool showKeyHints;

  /// What OK does, when it differs from [EpgGuideSelection.action] (on the
  /// channel cell OK always tunes, whatever programme the preview shows).
  final EpgGuideAction? okAction;

  /// OK starts the live channel in the guide's preview player rather than
  /// full-screen, so the hint reads "Preview".
  final bool okPreviews;

  /// Replaces the programme artwork (the guide's preview player).
  final Widget? artwork;

  /// Whether holding OK opens anything, so the hint isn't offered when it
  /// would do nothing.
  final bool canOpenOptions;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: artwork ?? EpgProgramArtwork(selection: selection),
          ),
          const SizedBox(width: 24),
          Expanded(
            child: _ProgramInfo(
              selection: selection,
              expandDescription: true,
              footer: showKeyHints
                  ? _KeyHints(
                      selection: selection,
                      okAction: okAction ?? selection.action,
                      okPreviews: okPreviews,
                      canOpenOptions: canOpenOptions,
                    )
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}

/// Programme artwork, falling back to the channel logo. Swaps to a new
/// image only once the selection has rested on it briefly, so holding a
/// direction across a row doesn't start an image download per programme.
class EpgProgramArtwork extends StatefulWidget {
  const EpgProgramArtwork({super.key, required this.selection});

  final EpgGuideSelection selection;

  @override
  State<EpgProgramArtwork> createState() => _EpgProgramArtworkState();
}

class _EpgProgramArtworkState extends State<EpgProgramArtwork> {
  static const _settleDelay = Duration(milliseconds: 220);

  String? _shownUrl;
  Timer? _settleTimer;

  String? get _wantedUrl => widget.selection.program?.iconUrl;

  @override
  void initState() {
    super.initState();
    _shownUrl = _wantedUrl;
  }

  @override
  void didUpdateWidget(EpgProgramArtwork oldWidget) {
    super.didUpdateWidget(oldWidget);
    final wanted = _wantedUrl;
    // Cancel first: moving A -> B -> A inside the delay must drop B's timer,
    // or it lands B while A is wanted and the frame falls back to the logo.
    _settleTimer?.cancel();
    if (wanted == _shownUrl) return;
    _settleTimer = Timer(_settleDelay, () {
      if (mounted) setState(() => _shownUrl = wanted);
    });
  }

  @override
  void dispose() {
    _settleTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final selection = widget.selection;
    final url = _shownUrl;
    final logo = _ChannelLogoFallback(channel: selection.channel);
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: ColoredBox(
        color: colorScheme.surfaceContainerHighest,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (url != null && url == _wantedUrl) ...[
              _BlurredArtworkFill(key: ValueKey('fill-$url'), url: url),
              CachedMediaThumbnail(
                key: ValueKey(url),
                url: url,
                fit: BoxFit.contain,
                fallback: logo,
              ),
            ] else
              logo,
            if (selection.isLive)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: LinearProgressIndicator(
                  value: selection.progress,
                  minHeight: 4,
                  backgroundColor: Colors.black38,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A dimmed, blurred cover-fit copy of the artwork behind the contained
/// image, so art that isn't 16:9 (square or portrait icons from many XMLTV
/// sources) fills the frame instead of sitting between bars. Wide art covers
/// it completely. Decoded tiny since the blur throws the detail away anyway.
class _BlurredArtworkFill extends StatelessWidget {
  const _BlurredArtworkFill({super.key, required this.url});

  static const _decodeSize = 48.0;

  final String url;

  @override
  Widget build(BuildContext context) {
    // The dimming is drawn atop the image's own pixels only, so while the art
    // loads (or if it fails) the frame keeps the plain placeholder look.
    return ImageFiltered(
      imageFilter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
      child: ColorFiltered(
        colorFilter: const ColorFilter.mode(Colors.black38, BlendMode.srcATop),
        child: FittedBox(
          fit: BoxFit.cover,
          clipBehavior: Clip.hardEdge,
          child: CachedMediaThumbnail(
            url: url,
            width: _decodeSize,
            height: _decodeSize,
            fit: BoxFit.cover,
            fallback: const SizedBox.square(dimension: _decodeSize),
          ),
        ),
      ),
    );
  }
}

class _ChannelLogoFallback extends StatelessWidget {
  const _ChannelLogoFallback({required this.channel});

  final Channel channel;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final icon = LayoutBuilder(
      builder: (context, constraints) => Icon(
        Icons.live_tv,
        size: constraints.biggest.shortestSide * 0.6,
        color: colorScheme.onSurfaceVariant,
      ),
    );
    final logoUrl = channel.logoUrl;
    return Center(
      child: FractionallySizedBox(
        widthFactor: 0.5,
        heightFactor: 0.6,
        child: logoUrl == null || logoUrl.isEmpty
            ? icon
            : CachedMediaThumbnail(
                url: logoUrl,
                fit: BoxFit.contain,
                fallback: icon,
              ),
      ),
    );
  }
}

class _ProgramInfo extends StatelessWidget {
  const _ProgramInfo({
    required this.selection,
    this.expandDescription = false,
    this.compact = false,
    this.footer,
  });

  final EpgGuideSelection selection;

  /// Fill a fixed height with the footer pinned at the bottom, for the TV
  /// panel: the description gets whatever height is left (see
  /// [_AutoScrollText]). The details sheet sizes to its content and scrolls
  /// instead.
  final bool expandDescription;
  final bool compact;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context);
    final program = selection.program;
    final hasInfo = selection.hasProgramInfo;

    final title = hasInfo
        ? (program!.title.trim().isEmpty
              ? program.displayTitle
              : program.title.trim())
        : selection.channel.name;
    final episodeParts = <String>[
      if (hasInfo) ?epgEpisodeLabel(l10n, program!),
      if (hasInfo && (program!.subtitle?.trim().isNotEmpty ?? false))
        program.subtitle!.trim(),
    ];
    final description = hasInfo ? program!.description.trim() : '';

    final descriptionText = hasInfo ? description : l10n.epgNoData;
    final descriptionStyle =
        (compact ? theme.textTheme.bodyMedium : theme.textTheme.bodyLarge)
            ?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontStyle: hasInfo ? null : FontStyle.italic,
              height: 1.35,
            );
    final showDescription = hasInfo ? description.isNotEmpty : program != null;

    final header = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (program != null) _StatusLine(selection: selection),
        const SizedBox(height: 6),
        Text(
          title,
          style:
              (compact
                      ? theme.textTheme.titleLarge
                      : theme.textTheme.headlineSmall)
                  ?.copyWith(fontWeight: FontWeight.w600),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        if (episodeParts.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            episodeParts.join(' · '),
            style: theme.textTheme.titleMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
        if (_MetaChips.hasAny(selection)) ...[
          const SizedBox(height: 10),
          _MetaChips(selection: selection),
        ],
      ],
    );

    if (!expandDescription) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          header,
          if (showDescription) ...[
            const SizedBox(height: 10),
            Text(descriptionText, style: descriptionStyle),
          ],
          if (footer != null) ...[const SizedBox(height: 8), footer!],
        ],
      );
    }
    // Fixed-height panel: the footer stays pinned to the bottom, the header
    // takes what it needs (clipped if even that doesn't fit, on a short
    // window or a large font size) and the description fills the rest.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: ClipRect(
            child: CustomMultiChildLayout(
              delegate: _HeaderThenFillLayout(gap: 10),
              children: [
                LayoutId(id: _InfoSlot.header, child: header),
                if (showDescription)
                  LayoutId(
                    id: _InfoSlot.description,
                    child: _AutoScrollText(
                      // Fresh state (back at the top, waiting to rest) for
                      // each programme the cursor lands on.
                      key: ValueKey(
                        '${program?.channelId}|${program?.start.toIso8601String()}',
                      ),
                      text: descriptionText,
                      style: descriptionStyle,
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (footer != null) ...[const SizedBox(height: 8), footer!],
      ],
    );
  }
}

enum _InfoSlot { header, description }

/// Lays the header out at its natural height and gives the description a
/// tight box with whatever height is left below it (none when the header
/// already fills the panel).
class _HeaderThenFillLayout extends MultiChildLayoutDelegate {
  _HeaderThenFillLayout({required this.gap});

  final double gap;

  @override
  void performLayout(Size size) {
    final headerSize = layoutChild(
      _InfoSlot.header,
      BoxConstraints(maxWidth: size.width),
    );
    positionChild(_InfoSlot.header, Offset.zero);
    if (!hasChild(_InfoSlot.description)) return;
    final top = headerSize.height + gap;
    layoutChild(
      _InfoSlot.description,
      BoxConstraints.tightFor(
        width: size.width,
        height: math.max(0, size.height - top),
      ),
    );
    positionChild(_InfoSlot.description, Offset(0, top));
  }

  @override
  bool shouldRelayout(_HeaderThenFillLayout oldDelegate) =>
      oldDelegate.gap != gap;
}

/// The preview's description in the height the panel leaves it. Shows whole
/// lines only, fading out the last one when there is more. Once the cursor
/// has rested on the programme it slowly scrolls through the rest, pauses at
/// the end, returns to the top and starts over (the way Kodi shows plot
/// text), unless the platform asks for reduced motion.
class _AutoScrollText extends StatefulWidget {
  const _AutoScrollText({super.key, required this.text, this.style});

  final String text;
  final TextStyle? style;

  @override
  State<_AutoScrollText> createState() => _AutoScrollTextState();
}

class _AutoScrollTextState extends State<_AutoScrollText> {
  static const _restDelay = Duration(seconds: 3);
  static const _endPause = Duration(seconds: 3);
  static const _returnDuration = Duration(milliseconds: 700);
  static const _millisecondsPerLine = 2500;

  final _controller = ScrollController();
  Timer? _timer;
  bool _running = false;
  double _lineHeight = 1;

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  /// Starts the scroll loop the first time the text is found to overflow.
  void _startLoop() {
    if (_running || MediaQuery.disableAnimationsOf(context)) return;
    _running = true;
    _timer = Timer(_restDelay, _scrollDown);
  }

  Future<void> _scrollDown() async {
    if (!mounted || !_controller.hasClients) return;
    final position = _controller.position;
    final distance = position.maxScrollExtent - position.pixels;
    if (distance <= 0) {
      // A relayout gave the text room after all; build restarts the loop
      // if it overflows again.
      _running = false;
      return;
    }
    await _controller.animateTo(
      position.maxScrollExtent,
      duration: Duration(
        milliseconds: (distance / _lineHeight * _millisecondsPerLine).round(),
      ),
      curve: Curves.linear,
    );
    if (!mounted) return;
    _timer = Timer(_endPause, _scrollUp);
  }

  Future<void> _scrollUp() async {
    if (!mounted || !_controller.hasClients) return;
    await _controller.animateTo(
      0,
      duration: _returnDuration,
      curve: Curves.easeInOut,
    );
    if (!mounted) return;
    _timer = Timer(_restDelay, _scrollDown);
  }

  @override
  Widget build(BuildContext context) {
    final text = Text(widget.text, style: widget.style);
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: widget.text, style: widget.style),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout(maxWidth: constraints.maxWidth);
        final textHeight = painter.height;
        final lineHeight = painter.preferredLineHeight;
        painter.dispose();
        _lineHeight = lineHeight;

        final lines = (constraints.maxHeight / lineHeight).floor();
        if (lines < 1) return const SizedBox.shrink();
        if (textHeight <= constraints.maxHeight) {
          return Align(alignment: Alignment.topLeft, child: text);
        }
        _startLoop();

        final viewportHeight = lines * lineHeight;
        final fade = math.min(0.5, lineHeight * 0.9 / viewportHeight);
        return Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            height: viewportHeight,
            child: ListenableBuilder(
              listenable: _controller,
              builder: (context, child) {
                final position = _controller.hasClients
                    ? _controller.position
                    : null;
                final atTop = position == null || position.pixels <= 0.5;
                final atEnd =
                    position != null &&
                    position.hasContentDimensions &&
                    position.pixels >= position.maxScrollExtent - 0.5;
                return ShaderMask(
                  blendMode: BlendMode.dstIn,
                  shaderCallback: (bounds) => LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      if (atTop) Colors.white else Colors.transparent,
                      Colors.white,
                      Colors.white,
                      if (atEnd) Colors.white else Colors.transparent,
                    ],
                    stops: [0, fade, 1 - fade, 1],
                  ).createShader(bounds),
                  child: child,
                );
              },
              child: ScrollConfiguration(
                behavior: ScrollConfiguration.of(
                  context,
                ).copyWith(scrollbars: false, overscroll: false),
                child: SingleChildScrollView(
                  controller: _controller,
                  physics: const NeverScrollableScrollPhysics(),
                  child: text,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Status pill + time range + duration + time left / starts in.
class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.selection});

  final EpgGuideSelection selection;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context);
    final program = selection.program!;
    final now = selection.now;

    final start = program.start.toLocal();
    final isToday = DateUtils.isSameDay(start, now.toLocal());
    final locale = Localizations.localeOf(context).toLanguageTag();
    final day =
        '${epgRelativeDayLabel(context, start, now.toLocal())} '
        '${DateFormat.MMMd(locale).format(start)}';
    final parts = <String>[
      if (!isToday) day,
      epgTimeRangeLabel(context, program),
      epgDurationLabel(l10n, program.end.difference(program.start)),
      if (selection.isLive)
        l10n.epgTimeLeft(epgDurationLabel(l10n, program.end.difference(now)))
      else if (selection.isUpcoming)
        l10n.epgStartsIn(epgDurationLabel(l10n, program.start.difference(now)))
      else if (!selection.canReplay)
        l10n.epgEnded,
    ];

    final pill = selection.isLive
        ? EpgStatusPill.live(context)
        : selection.canReplay
        ? EpgStatusPill.replay(context)
        : null;

    return Row(
      children: [
        if (pill != null) ...[pill, const SizedBox(width: 10)],
        Flexible(
          child: Text(
            parts.join('  ·  '),
            style: theme.textTheme.titleSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

/// LIVE / REPLAY pill used in the preview panel and the details sheet.
class EpgStatusPill extends StatelessWidget {
  const EpgStatusPill({
    super.key,
    required this.label,
    required this.background,
    required this.foreground,
    this.icon,
  });

  factory EpgStatusPill.live(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return EpgStatusPill(
      label: AppLocalizations.of(context).epgLiveBadge,
      background: colorScheme.error,
      foreground: colorScheme.onError,
    );
  }

  factory EpgStatusPill.replay(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return EpgStatusPill(
      label: AppLocalizations.of(context).epgReplayBadge,
      background: colorScheme.tertiaryContainer,
      foreground: colorScheme.onTertiaryContainer,
      icon: Icons.replay_rounded,
    );
  }

  final String label;
  final Color background;
  final Color foreground;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelMedium?.copyWith(
      color: foreground,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.8,
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: foreground),
            const SizedBox(width: 4),
          ],
          Text(label, style: style),
        ],
      ),
    );
  }
}

class _MetaChips extends StatelessWidget {
  const _MetaChips({required this.selection});

  final EpgGuideSelection selection;

  static bool hasAny(EpgGuideSelection selection) {
    final p = selection.program;
    if (selection.recordingState != EpgRecordingState.none) return true;
    if (p == null || p.isPlaceholder) return false;
    return p.category != null ||
        p.rating != null ||
        p.year != null ||
        p.isNew ||
        p.isPremiere ||
        p.isRepeat;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    final program = selection.program;
    final showMeta = program != null && !program.isPlaceholder;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (selection.recordingState != EpgRecordingState.none)
          ProgramRecordingIndicator(state: selection.recordingState),
        if (showMeta && program.isNew)
          _MetaChip(
            label: l10n.epgBadgeNew,
            background: colorScheme.primaryContainer,
            foreground: colorScheme.onPrimaryContainer,
          ),
        if (showMeta && program.isPremiere)
          _MetaChip(
            label: l10n.epgBadgePremiere,
            background: colorScheme.primaryContainer,
            foreground: colorScheme.onPrimaryContainer,
          ),
        if (showMeta && program.isRepeat) _MetaChip(label: l10n.epgBadgeRepeat),
        if (showMeta && program.category != null)
          _MetaChip(label: program.category!),
        if (showMeta && program.rating != null)
          _MetaChip(label: program.rating!),
        if (showMeta && program.year != null)
          _MetaChip(label: '${program.year}'),
      ],
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.label, this.background, this.foreground});

  final String label;
  final Color? background;
  final Color? foreground;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final fg = foreground ?? colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: background ?? colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
        border: background == null
            ? Border.all(color: colorScheme.outlineVariant)
            : null,
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: fg,
          fontWeight: FontWeight.w600,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

/// "OK: Watch live" / "Hold OK: More options" remote hints.
class _KeyHints extends StatelessWidget {
  const _KeyHints({
    required this.selection,
    required this.okAction,
    required this.canOpenOptions,
    this.okPreviews = false,
  });

  final EpgGuideSelection selection;
  final EpgGuideAction okAction;
  final bool canOpenOptions;
  final bool okPreviews;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final primary = switch (okAction) {
      EpgGuideAction.watchLive =>
        okPreviews ? l10n.epgPreview : l10n.epgWatchLive,
      EpgGuideAction.watchReplay => l10n.epgWatchReplay,
      EpgGuideAction.options => l10n.epgMoreOptions,
      EpgGuideAction.none => null,
    };
    // Wraps rather than overflowing: on a narrow panel the hints drop
    // below the channel instead of sitting beside it.
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 16,
      runSpacing: 6,
      children: [
        _ChannelTag(channel: selection.channel),
        Wrap(
          spacing: 16,
          runSpacing: 4,
          children: [
            if (primary != null)
              _KeyHint(keyLabel: l10n.epgKeyOk, label: primary),
            if (canOpenOptions && okAction != EpgGuideAction.options)
              _KeyHint(keyLabel: l10n.epgKeyHoldOk, label: l10n.epgMoreOptions),
          ],
        ),
      ],
    );
  }
}

class _KeyHint extends StatelessWidget {
  const _KeyHint({required this.keyLabel, required this.label});

  final String keyLabel;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: colorScheme.outline),
          ),
          child: Text(
            keyLabel,
            style: theme.textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: theme.textTheme.labelLarge?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _ChannelTag extends StatelessWidget {
  const _ChannelTag({required this.channel});

  final Channel channel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final number = channel.channelNumber;
    final logoUrl = channel.logoUrl;
    final size = 24 * FontSizeScope.scaleOf(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (logoUrl != null && logoUrl.isNotEmpty) ...[
          CachedMediaThumbnail(
            url: logoUrl,
            width: size,
            height: size,
            fit: BoxFit.contain,
            fallback: Icon(Icons.tv, size: size),
          ),
          const SizedBox(width: 8),
        ],
        Flexible(
          child: Text(
            number == null ? channel.name : '$number  ${channel.name}',
            style: theme.textTheme.labelLarge?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (channel.catchupSupported) ...[
          const SizedBox(width: 8),
          EpgIconPill(
            color: colorScheme.tertiaryContainer,
            borderColor: colorScheme.tertiary.withValues(alpha: 0.55),
            child: Icon(
              Icons.history,
              size: 12,
              color: colorScheme.onTertiaryContainer,
            ),
          ),
        ],
      ],
    );
  }
}

/// Touch devices' programme details: there's no focus preview on a phone,
/// so tapping a programme opens this sheet with its full information and
/// the same actions OK / long-press give on a remote.
Future<void> showEpgProgramDetailsSheet(
  BuildContext context, {
  required EpgGuideSelection selection,
  required VoidCallback onWatchLive,
  VoidCallback? onWatchReplay,
  VoidCallback? onMoreOptions,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (sheetContext) {
      void run(VoidCallback action) {
        Navigator.of(sheetContext).pop();
        action();
      }

      final l10n = AppLocalizations.of(sheetContext);
      final canReplay = selection.canReplay && onWatchReplay != null;
      // A filler block ahead of now still offers Watch live: there is no
      // programme to wait for.
      final isUpcoming = selection.isUpcoming && selection.hasProgramInfo;
      return ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.85,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            key: const ValueKey('epg-program-details-sheet'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selection.program?.iconUrl != null) ...[
                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: EpgProgramArtwork(selection: selection),
                ),
                const SizedBox(height: 16),
              ],
              _ProgramInfo(
                selection: selection,
                compact: true,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Flexible(child: _ChannelTag(channel: selection.channel)),
                ],
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (canReplay)
                    AppButton(
                      icon: Icons.replay_rounded,
                      label: l10n.epgWatchReplay,
                      variant: AppButtonVariant.primary,
                      onPressed: () => run(onWatchReplay),
                    ),
                  if (!isUpcoming)
                    AppButton(
                      icon: Icons.live_tv,
                      label: l10n.epgWatchLive,
                      variant: canReplay
                          ? AppButtonVariant.tonal
                          : AppButtonVariant.primary,
                      onPressed: () => run(onWatchLive),
                    ),
                  if (onMoreOptions != null)
                    AppButton(
                      icon: Icons.more_horiz,
                      label: l10n.epgMoreOptions,
                      variant: isUpcoming
                          ? AppButtonVariant.primary
                          : AppButtonVariant.tonal,
                      onPressed: () => run(onMoreOptions),
                    ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}
