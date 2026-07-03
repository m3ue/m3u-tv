import 'package:flutter/widgets.dart';
import 'package:m3u_tv/navigation/app_router.dart';
import 'package:m3u_tv/services/app_state_controller.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/epg_service.dart';
import 'package:m3u_tv/services/xtream_service.dart';

/// Bridges AppShell navigation callbacks to go_router branch builders.
/// AppShell provides this in its build tree so nested route builders can call
/// [ContentActions.of] without changing feature screen constructor signatures.
class ContentActions extends InheritedWidget {
  const ContentActions({
    super.key,
    required this.appState,
    required this.onOpenPlayer,
    required this.onChannelSelect,
    required this.onCatchupSelect,
    required this.onVodSelect,
    required this.onSeriesSelect,
    required this.onProgressSelect,
    required this.onSidebarActivate,
    required this.buildTabScreen,
    required super.child,
  });

  final AppStateController appState;

  /// Opens the player overlay directly (used by detail screens' play buttons).
  final void Function(PlayerArgs) onOpenPlayer;

  /// Navigates to VOD details route (pushes `/vod/details/:id`).
  final void Function(VodItem) onVodSelect;

  final void Function(Channel) onChannelSelect;
  final void Function(Channel, EpgProgram) onCatchupSelect;

  /// Navigates to series details route (pushes `/series/details/:id`).
  final void Function(Series) onSeriesSelect;

  final void Function(Progress) onProgressSelect;
  final VoidCallback onSidebarActivate;

  /// Builds the full tab screen for the given routeName.
  /// Provided by AppShell so go_router branch builders don't need to import
  /// every feature screen directly.
  final Widget Function(String routeName) buildTabScreen;

  XtreamService get xtreamService => appState.xtreamService;
  EpgService get epgService => appState.epgService;
  List<Progress> get progressList => appState.progressList;

  static ContentActions of(BuildContext context) {
    final result = context.dependOnInheritedWidgetOfExactType<ContentActions>();
    assert(result != null, 'ContentActions not found in widget tree');
    return result!;
  }

  static ContentActions? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ContentActions>();

  @override
  bool updateShouldNotify(ContentActions oldWidget) =>
      // Only the appState instance ever changes. All callbacks are stable
      // method tearoffs from AppShellState — comparing them would always return
      // false (equal), but if any were closures they'd always return true and
      // flood every feature screen with unnecessary rebuilds on each tab switch.
      appState != oldWidget.appState;
}
