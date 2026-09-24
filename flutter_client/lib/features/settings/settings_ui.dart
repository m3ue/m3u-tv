import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:m3u_tv/shared/app_button.dart';
import 'package:m3u_tv/shared/dpad_ink_well.dart';
import 'package:m3u_tv/shared/image_quality_scope.dart';

/// Mirrors `item_detail_scaffold.dart`/`dvr_series_rule_options_screen.dart`'s
/// identical constant/getter, duplicated narrowly here rather than shared:
/// settings sub-pages are pushed on the root Navigator (see
/// [pushSettingsSubpage]'s doc comment) so their leading back button needs
/// the same macOS traffic-light clearance.
bool get _isMacDesktopWindow => !kIsWeb && Platform.isMacOS;
const double _kMacTrafficLightInset = 72;

/// tvOS reports its overscan-safe area as real MediaQuery padding on every
/// edge. Settings sub-pages are pushed on the root Navigator, outside
/// AppShell's own TV/sidebar layout, which otherwise strips that padding, and
/// without the same treatment here, a pushed sub-page renders shrunk inward
/// on tvOS only. Mirrors `go_router_config.dart`'s `_topLevelSafeArea`,
/// duplicated here for the same reason this file can't import that one
/// (cycle risk / the value is trivial to redeclare).
bool get _isTvOS => !kIsWeb && Platform.operatingSystem == 'tvos';

Widget _topLevelSafeArea(Widget screen) => Builder(
  builder: (context) => _isTvOS
      ? MediaQuery.removePadding(
          context: context,
          removeTop: true,
          removeBottom: true,
          removeLeft: true,
          removeRight: true,
          child: screen,
        )
      : screen,
);

class _SettingsSubpagePopIntent extends Intent {
  const _SettingsSubpagePopIntent();
}

/// Rebinds Escape/GoBack to [onBack] (falling back to a plain root pop when
/// absent), scoped to just the wrapped subtree. A settings sub-page pushed
/// on the root Navigator is a sibling of AppShell, not a descendant, so
/// AppShell's own `Shortcuts`/`Actions` binding for hardware Back can't
/// reach it. Mirrors `go_router_config.dart`'s `_withTopLevelBackHandling`
/// and `dvr_series_rule_options_screen.dart`'s function of the same name.
Widget _withTopLevelBackHandling(bool Function()? onBack, Widget child) {
  return Shortcuts(
    shortcuts: <LogicalKeySet, Intent>{
      LogicalKeySet(LogicalKeyboardKey.escape):
          const _SettingsSubpagePopIntent(),
      LogicalKeySet(LogicalKeyboardKey.goBack):
          const _SettingsSubpagePopIntent(),
    },
    child: Builder(
      builder: (context) => Actions(
        actions: <Type, Action<Intent>>{
          _SettingsSubpagePopIntent: CallbackAction<_SettingsSubpagePopIntent>(
            onInvoke: (_) {
              if (onBack != null) {
                onBack();
              } else {
                Navigator.of(context, rootNavigator: true).maybePop();
              }
              return null;
            },
          ),
        },
        child: child,
      ),
    ),
  );
}

/// Corner radius shared by [SettingsGroup]/[SettingsCard] and every
/// [SettingsRow]'s own focus border, so a focused row's rounded corners
/// never mismatch (and get visibly clipped by) the group's outer
/// [ClipRRect].
const double kSettingsGroupRadius = 14;

/// Tells a [SettingsRow] which corners of its own focus border to round,
/// based on its position within an enclosing [SettingsGroup] (top row: top
/// corners only, bottom row: bottom corners only, middle rows: square).
///
/// A [ClipRRect] around a row can only ever remove pixels, never add them
/// back - a rounded-rect stroke already stops short of a corner's literal
/// point, so clipping a middle row down to "square" has no visible effect on
/// a border painted with a rounded radius. The radius has to be varied at
/// the paint site itself, which this scope carries down to each row.
class _RowBorderRadiusScope extends InheritedWidget {
  const _RowBorderRadiusScope({required this.radius, required super.child});

  final BorderRadius radius;

  static BorderRadius? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<_RowBorderRadiusScope>()
        ?.radius;
  }

  @override
  bool updateShouldNotify(_RowBorderRadiusScope oldWidget) =>
      radius != oldWidget.radius;
}

/// A single-line, icon + title/subtitle settings entry with a trailing
/// chevron, switch, or value (the grouped-list style used by most desktop
/// settings apps, and Plezy's), replacing this screen's old
/// title-plus-`Wrap`-of-pill-chips sections.
class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.trailing,
    this.onTap,
    this.destructive = false,
    this.autofocus = false,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool destructive;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scale = FontSizeScope.scaleOf(context);
    final titleColor = destructive ? theme.colorScheme.error : null;
    final content = Padding(
      padding: EdgeInsets.symmetric(
        horizontal: 16 * scale,
        vertical: 12 * scale,
      ),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(
              icon,
              size: 22 * scale,
              color: titleColor ?? theme.colorScheme.onSurfaceVariant,
            ),
            SizedBox(width: 16 * scale),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: titleColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (subtitle != null) ...[
                  SizedBox(height: 2 * scale),
                  Text(
                    subtitle!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[SizedBox(width: 12 * scale), trailing!],
        ],
      ),
    );

    if (onTap == null) return content;
    final borderRadius =
        _RowBorderRadiusScope.maybeOf(context) ??
        BorderRadius.circular(kSettingsGroupRadius);
    return DpadInkWell(
      autofocus: autofocus,
      onTap: onTap,
      borderRadius: borderRadius,
      child: content,
    );
  }
}

/// The trailing chevron for a [SettingsRow] that navigates to a sub-page.
class SettingsChevron extends StatelessWidget {
  const SettingsChevron({super.key});

  @override
  Widget build(BuildContext context) {
    return Icon(
      Icons.chevron_right,
      size: 24 * FontSizeScope.scaleOf(context),
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
  }
}

/// A boolean setting rendered as a real [Switch], replacing the old on/off
/// pill-pair (`_BooleanSetting`).
class SettingsSwitchRow extends StatelessWidget {
  const SettingsSwitchRow({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SettingsRow(
      title: title,
      subtitle: subtitle,
      icon: icon,
      trailing: Switch(value: value, onChanged: onChanged),
      onTap: () => onChanged(!value),
    );
  }
}

/// Groups related [SettingsRow]s into a single rounded card with hairline
/// dividers between rows, matching Plezy's settings-list grouping.
class SettingsGroup extends StatelessWidget {
  const SettingsGroup({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const radius = Radius.circular(kSettingsGroupRadius);
    return ClipRRect(
      borderRadius: const BorderRadius.all(radius),
      child: Material(
        color: theme.colorScheme.surfaceContainerHigh,
        child: Column(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0)
                Divider(
                  height: 1,
                  thickness: 1,
                  indent: 16,
                  color: theme.colorScheme.outlineVariant.withValues(
                    alpha: 0.3,
                  ),
                ),
              // Tells this row's own focus border (see [SettingsRow] /
              // [_RowBorderRadiusScope]) which corners to round: top row's
              // top corners, bottom row's bottom corners, square in between
              // - the attached-list look, landing exactly on the group's
              // own rounded corners at the ends.
              _RowBorderRadiusScope(
                radius: _cornerRadiusFor(i, children.length, radius),
                child: children[i],
              ),
            ],
          ],
        ),
      ),
    );
  }

  BorderRadius _cornerRadiusFor(int index, int length, Radius radius) {
    if (length == 1) return BorderRadius.all(radius);
    if (index == 0) return BorderRadius.vertical(top: radius);
    if (index == length - 1) return BorderRadius.vertical(bottom: radius);
    return BorderRadius.zero;
  }
}

/// A plain rounded card for settings content that doesn't fit the
/// row-per-line [SettingsGroup] shape (status readouts, the app version
/// card, the Trakt integration panel).
class SettingsCard extends StatelessWidget {
  const SettingsCard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(14),
      ),
      child: child,
    );
  }
}

/// A small muted label above a [SettingsGroup], e.g. "Connections" or
/// "Downloads" in Plezy's settings list.
class SettingsSectionHeader extends StatelessWidget {
  const SettingsSectionHeader(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
      child: Text(
        label,
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Matches the shared TV-layout gradient's dominant end tone, mirroring the
/// opaque backing `go_router_config.dart`'s top-level routes and
/// `dvr_series_rule_options_screen.dart`'s `openDvrSeriesRuleOptions` use.
/// A pushed route has a transparent `scaffoldBackgroundColor` (the theme
/// relies on AppShell's own gradient showing through) and no Scaffold at all
/// here, so without this the new page renders see-through over the old one
/// until the push transition finishes, then "snaps" opaque.
const Color _kSettingsSubpageBackground = Color(0xFF09090b);

/// A `Scaffold` + `AppBar` matching the app's other immersive top-level
/// pages byte-for-byte (`show_detail_screen.dart`,
/// `dvr_series_rule_options_screen.dart`): same `AppIconButton` back button,
/// `toolbarHeight`/`leadingWidth`/padding math, and macOS traffic-light
/// inset, so a pushed settings sub-page reads as the same kind of page
/// instead of a bespoke one-off header.
Widget _settingsSubpageScaffold(
  BuildContext context, {
  required String Function(BuildContext) title,
  required Widget body,
}) {
  final scale = FontSizeScope.scaleOf(context);
  final macInset = _isMacDesktopWindow ? _kMacTrafficLightInset : 0.0;
  return Scaffold(
    appBar: AppBar(
      title: Text(title(context)),
      automaticallyImplyLeading: false,
      toolbarHeight: kToolbarHeight * scale,
      leadingWidth: (56 * scale) + macInset,
      leading: Padding(
        padding: EdgeInsets.fromLTRB(
          8 * scale + macInset,
          8 * scale,
          8 * scale,
          8 * scale,
        ),
        child: AppIconButton(
          icon: Icons.arrow_back,
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
        ),
      ),
    ),
    body: Padding(padding: const EdgeInsets.all(24), child: body),
  );
}

/// Pushes [content] on the root Navigator as a full-screen, "immersive"
/// settings sub-page, covering AppShell's sidebar entirely, the same
/// top-level-route treatment applied to VOD/Series/AIOStreams detail and the
/// DVR series-rule-options screen (see `go_router_config.dart`'s top-level
/// routes and the `project_vod_series_toplevel_routes` memory for why): the
/// user has to explicitly back out of a nested settings page rather than
/// landing back on the plain settings list mid-navigation. [onBack] should
/// be the caller's `onHandleTopLevelBack` (from `AppShellState`, threaded
/// down through `SettingsScreen`) so Android TV's hardware Back dedupes
/// correctly instead of risking the spurious-second-back-press bug described
/// on `_withTopLevelBackHandling`.
Future<T?> _pushImmersive<T>(
  BuildContext context, {
  required bool Function()? onBack,
  required WidgetBuilder content,
}) {
  return Navigator.of(context, rootNavigator: true).push<T>(
    PageRouteBuilder<T>(
      pageBuilder: (context, animation, secondaryAnimation) => Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: _kSettingsSubpageBackground),
          _topLevelSafeArea(
            _withTopLevelBackHandling(onBack, Builder(builder: content)),
          ),
        ],
      ),
      transitionsBuilder: (context, animation, _, child) => SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(1, 0),
          end: Offset.zero,
        ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOut)),
        child: child,
      ),
    ),
  );
}

/// Pushes [builder] as a scrolling, immersive settings sub-page with the
/// app's standard back-button-and-title AppBar. [title] is a builder rather
/// than a plain `String` so the AppBar heading re-resolves against the
/// current locale on every rebuild - a fixed `String` gets baked in with
/// whatever language was active at the moment the row was tapped, and stays
/// stuck in that language until the page is popped and re-pushed even though
/// the body (which reads `AppLocalizations.of(context)` fresh each build)
/// updates immediately. See [_pushImmersive].
Future<T?> pushSettingsSubpage<T>(
  BuildContext context, {
  required String Function(BuildContext) title,
  required WidgetBuilder builder,
  bool Function()? onBack,
}) {
  return _pushImmersive<T>(
    context,
    onBack: onBack,
    content: (context) => _settingsSubpageScaffold(
      context,
      title: title,
      body: SingleChildScrollView(child: builder(context)),
    ),
  );
}

/// Like [pushSettingsSubpage], but gives [builder] the full remaining height
/// instead of wrapping it in a [SingleChildScrollView], for sub-pages that
/// manage their own scrolling/layout (e.g. the Release Notes master/detail
/// view).
Future<T?> pushSettingsSubpageFullHeight<T>(
  BuildContext context, {
  required String Function(BuildContext) title,
  required WidgetBuilder builder,
  bool Function()? onBack,
}) {
  return _pushImmersive<T>(
    context,
    onBack: onBack,
    content: (context) =>
        _settingsSubpageScaffold(context, title: title, body: builder(context)),
  );
}

/// One choice in a [pushSettingsPicker] list.
class SettingsPickerOption<T> {
  const SettingsPickerOption({
    required this.value,
    required this.label,
    this.icon,
  });

  final T value;
  final String label;
  final IconData? icon;
}

/// Pushes a single-select list picker sub-page (a row per option with a
/// checkmark on the current selection), replacing a `Wrap` of pill chips for
/// settings with more than a couple of options (language, layouts, EPG
/// refresh interval, transcoding profile, etc).
Future<void> pushSettingsPicker<T>(
  BuildContext context, {
  required String Function(BuildContext) title,
  required List<SettingsPickerOption<T>> options,
  required T selected,
  required ValueChanged<T> onSelected,
  bool Function()? onBack,
}) {
  return pushSettingsSubpage<void>(
    context,
    title: title,
    onBack: onBack,
    builder: (pageContext) => SettingsGroup(
      children: [
        for (final option in options)
          SettingsRow(
            title: option.label,
            icon: option.icon,
            trailing: option.value == selected
                ? Icon(
                    Icons.check,
                    color: Theme.of(pageContext).colorScheme.primary,
                  )
                : null,
            onTap: () {
              onSelected(option.value);
              Navigator.of(pageContext).pop();
            },
          ),
      ],
    ),
  );
}
