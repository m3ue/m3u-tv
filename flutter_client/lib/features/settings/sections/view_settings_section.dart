import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:m3u_tv/app/app_shell.dart' show DeviceType;
import 'package:m3u_tv/features/settings/settings_ui.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/services/view_settings_service.dart';
import 'package:m3u_tv/shared/host_platform.dart';

// ---------------------------------------------------------------------------
// Appearance settings sub-page (layout, display, filters)
// ---------------------------------------------------------------------------

class ViewSettingsSection extends StatefulWidget {
  const ViewSettingsSection({
    super.key,
    required this.service,
    this.deviceType,
    this.onHandleTopLevelBack,
  });

  final ViewSettingsService service;
  final DeviceType? deviceType;
  final bool Function()? onHandleTopLevelBack;

  @override
  State<ViewSettingsSection> createState() => _ViewSettingsSectionState();
}

class _ViewSettingsSectionState extends State<ViewSettingsSection> {
  LiveTvLayout _liveTvLayout = LiveTvLayout.list;
  EpgStartView _epgStartView = EpgStartView.currentTime;
  EpgPreviewPlayback _epgPreviewPlayback = EpgPreviewPlayback.off;
  Duration _epgPreviewDelay = const Duration(
    seconds: ViewSettingsService.defaultEpgPreviewDelaySeconds,
  );
  ChannelColumnLayout _channelColumnLayout = ChannelColumnLayout.logoOnly;
  bool _rememberMediaSort = false;
  DefaultStartPage _defaultStartPage = DefaultStartPage.home;
  HomeScreenStyle _homeScreenStyle = HomeScreenStyle.simplified;
  bool _hdrEnabled = true;
  bool _matchRefreshRate = false;
  bool _deinterlace = false;
  bool _navigationSoundEnabled = true;
  OptimizeFor _optimizeFor = OptimizeFor.quality;
  AppFontSize _fontSize = AppFontSize.normal;

  // The mpv HDR override ships on the Linux and Windows desktop backends
  // only. Refresh-rate matching ships on Windows (DisplayModeManager),
  // Android (FrameRateManager), and tvOS (MpvPlayerCore.swift's
  // AVDisplayManager use, decoupled from its always-on HDR criteria so this
  // toggle actually controls it). Windows/Android default off -- the mode
  // switch briefly blanks/flashes the display; tvOS defaults on, since it
  // shipped unconditionally before this toggle existed (see
  // ViewSettingsService.matchRefreshRate's platform-aware default).
  static final bool _showHdrToggle =
      HostPlatform.isWindows || HostPlatform.isLinux;
  static final bool _showRefreshRateToggle =
      HostPlatform.isWindows || HostPlatform.isAndroid || _isTvOS;

  // Deinterlacing is an mpv filter. Android plays through ExoPlayer, which
  // has no filter chain (mpv there is only a fallback), so hide it there.
  static final bool _showDeinterlaceToggle = !HostPlatform.isAndroid;

  // Mirrors the tvOS/Android-TV detection duplicated in go_router_config.dart
  // and dvr_series_rule_options_screen.dart -- no shared helper exists yet.
  static bool get _isTvOS => HostPlatform.isTvOS;

  // The navigation click sound only ever plays on TV/desktop (see main.dart);
  // hide the toggle where it would have no effect.
  bool get _showNavigationSoundToggle =>
      widget.deviceType == DeviceType.tv ||
      widget.deviceType == DeviceType.desktop;

  // The guide's preview panel only exists on TV/desktop (touch devices open a
  // details sheet instead), and the preview player is a native one, so web
  // has nothing to play it with.
  bool get _showEpgPreviewPlayback => !kIsWeb && _showNavigationSoundToggle;

  @override
  void initState() {
    super.initState();
    widget.service.addListener(_refresh);
    unawaited(_refresh());
  }

  @override
  void dispose() {
    widget.service.removeListener(_refresh);
    super.dispose();
  }

  Future<void> _refresh() async {
    final layout = await widget.service.liveTvLayout();
    final startView = await widget.service.epgStartView();
    final epgPreviewPlayback = await widget.service.epgPreviewPlayback();
    final epgPreviewDelay = await widget.service.epgPreviewDelay();
    final channelColumnLayout = await widget.service.channelColumnLayout();
    final rememberMediaSort = await widget.service.rememberMediaSort();
    final defaultStartPage = await widget.service.defaultStartPage();
    final homeScreenStyle = await widget.service.homeScreenStyle();
    final hdrEnabled = await widget.service.hdrEnabled();
    final matchRefreshRate = await widget.service.matchRefreshRate();
    final deinterlace = await widget.service.deinterlace();
    final navigationSoundEnabled = await widget.service
        .navigationSoundEnabled();
    final optimizeFor = await widget.service.optimizeFor();
    final storedFontSize = await widget.service.fontSizeOrNull();
    final fontSize = AppFontSize.resolveDefault(
      stored: storedFontSize,
      isTv: widget.deviceType == DeviceType.tv,
    );
    if (!mounted) return;
    setState(() {
      _liveTvLayout = layout;
      _epgStartView = startView;
      _epgPreviewPlayback = epgPreviewPlayback;
      _epgPreviewDelay = epgPreviewDelay;
      _channelColumnLayout = channelColumnLayout;
      _rememberMediaSort = rememberMediaSort;
      _defaultStartPage = defaultStartPage;
      _homeScreenStyle = homeScreenStyle;
      _hdrEnabled = hdrEnabled;
      _matchRefreshRate = matchRefreshRate;
      _deinterlace = deinterlace;
      _navigationSoundEnabled = navigationSoundEnabled;
      _optimizeFor = optimizeFor;
      _fontSize = fontSize;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsSectionHeader(l.settingsSectionLayout),
        SettingsGroup(
          children: [
            SettingsRow(
              title: l.settingsDefaultStartPage,
              subtitle: _startPageLabel(l, _defaultStartPage),
              icon: Icons.home_outlined,
              trailing: const SettingsChevron(),
              onTap: () => unawaited(
                pushSettingsPicker<DefaultStartPage>(
                  context,
                  title: (context) =>
                      AppLocalizations.of(context).settingsDefaultStartPage,
                  onBack: widget.onHandleTopLevelBack,
                  selected: _defaultStartPage,
                  options: [
                    for (final page in DefaultStartPage.values)
                      SettingsPickerOption(
                        value: page,
                        label: _startPageLabel(l, page),
                      ),
                  ],
                  onSelected: widget.service.setDefaultStartPage,
                ),
              ),
            ),
            // The rich Home's spotlight follows D-pad/mouse focus, which touch
            // layouts don't have - they always render the simplified Home.
            if (_showNavigationSoundToggle)
              SettingsRow(
                title: l.settingsHomeScreenStyle,
                subtitle: _homeScreenStyleLabel(l, _homeScreenStyle),
                icon: Icons.dashboard_outlined,
                trailing: const SettingsChevron(),
                onTap: () => unawaited(
                  pushSettingsPicker<HomeScreenStyle>(
                    context,
                    title: (context) =>
                        AppLocalizations.of(context).settingsHomeScreenStyle,
                    onBack: widget.onHandleTopLevelBack,
                    selected: _homeScreenStyle,
                    options: [
                      for (final style in HomeScreenStyle.values)
                        SettingsPickerOption(
                          value: style,
                          label: _homeScreenStyleLabel(l, style),
                        ),
                    ],
                    onSelected: widget.service.setHomeScreenStyle,
                  ),
                ),
              ),
            SettingsRow(
              title: l.settingsLiveTvLayout,
              subtitle: _liveTvLayoutLabel(l, _liveTvLayout),
              icon: Icons.view_list_outlined,
              trailing: const SettingsChevron(),
              onTap: () => unawaited(
                pushSettingsPicker<LiveTvLayout>(
                  context,
                  title: (context) =>
                      AppLocalizations.of(context).settingsLiveTvLayout,
                  onBack: widget.onHandleTopLevelBack,
                  selected: _liveTvLayout,
                  options: [
                    SettingsPickerOption(
                      value: LiveTvLayout.list,
                      label: l.settingsLiveTvLayoutList,
                    ),
                    SettingsPickerOption(
                      value: LiveTvLayout.grid,
                      label: l.settingsLiveTvLayoutGrid,
                    ),
                    SettingsPickerOption(
                      value: LiveTvLayout.timeline,
                      label: l.settingsLiveTvLayoutTimeline,
                    ),
                  ],
                  onSelected: widget.service.setLiveTvLayout,
                ),
              ),
            ),
            SettingsRow(
              title: l.settingsLiveTvChannelColumn,
              subtitle: _channelColumnLabel(l, _channelColumnLayout),
              icon: Icons.view_column_outlined,
              trailing: const SettingsChevron(),
              onTap: () => unawaited(
                pushSettingsPicker<ChannelColumnLayout>(
                  context,
                  title: (context) => AppLocalizations.of(
                    context,
                  ).settingsLiveTvChannelColumn,
                  onBack: widget.onHandleTopLevelBack,
                  selected: _channelColumnLayout,
                  options: [
                    SettingsPickerOption(
                      value: ChannelColumnLayout.logoAndTitle,
                      label: l.settingsLiveTvChannelColumnLogoTitle,
                    ),
                    SettingsPickerOption(
                      value: ChannelColumnLayout.logoOnly,
                      label: l.settingsLiveTvChannelColumnLogoOnly,
                    ),
                    SettingsPickerOption(
                      value: ChannelColumnLayout.titleOnly,
                      label: l.settingsLiveTvChannelColumnTitleOnly,
                    ),
                  ],
                  onSelected: widget.service.setChannelColumnLayout,
                ),
              ),
            ),
            SettingsRow(
              title: l.settingsEpgStartView,
              subtitle: _epgStartViewLabel(l, _epgStartView),
              icon: Icons.calendar_view_day_outlined,
              trailing: const SettingsChevron(),
              onTap: () => unawaited(
                pushSettingsPicker<EpgStartView>(
                  context,
                  title: (context) =>
                      AppLocalizations.of(context).settingsEpgStartView,
                  onBack: widget.onHandleTopLevelBack,
                  selected: _epgStartView,
                  options: [
                    SettingsPickerOption(
                      value: EpgStartView.currentTime,
                      label: l.settingsEpgStartViewCurrentTime,
                    ),
                    SettingsPickerOption(
                      value: EpgStartView.primeTime,
                      label: l.settingsEpgStartViewPrimeTime,
                    ),
                  ],
                  onSelected: widget.service.setEpgStartView,
                ),
              ),
            ),
            if (_showEpgPreviewPlayback)
              SettingsRow(
                title: l.settingsEpgPreviewPlayback,
                subtitle: _epgPreviewPlaybackLabel(l, _epgPreviewPlayback),
                icon: Icons.smart_display_outlined,
                trailing: const SettingsChevron(),
                onTap: () => unawaited(
                  pushSettingsPicker<EpgPreviewPlayback>(
                    context,
                    title: (context) =>
                        AppLocalizations.of(context).settingsEpgPreviewPlayback,
                    onBack: widget.onHandleTopLevelBack,
                    selected: _epgPreviewPlayback,
                    options: [
                      for (final mode in EpgPreviewPlayback.values)
                        SettingsPickerOption(
                          value: mode,
                          label: _epgPreviewPlaybackLabel(l, mode),
                        ),
                    ],
                    onSelected: widget.service.setEpgPreviewPlayback,
                  ),
                ),
              ),
            if (_showEpgPreviewPlayback &&
                _epgPreviewPlayback == EpgPreviewPlayback.pauseToPlay)
              SettingsRow(
                title: l.settingsEpgPreviewDelay,
                subtitle: l.settingsEpgPreviewDelaySeconds(
                  _epgPreviewDelay.inSeconds,
                ),
                icon: Icons.timer_outlined,
                trailing: const SettingsChevron(),
                onTap: () => unawaited(
                  pushSettingsPicker<int>(
                    context,
                    title: (context) =>
                        AppLocalizations.of(context).settingsEpgPreviewDelay,
                    onBack: widget.onHandleTopLevelBack,
                    selected: _epgPreviewDelay.inSeconds,
                    options: [
                      for (final seconds
                          in ViewSettingsService.epgPreviewDelayOptions)
                        SettingsPickerOption(
                          value: seconds,
                          label: l.settingsEpgPreviewDelaySeconds(seconds),
                        ),
                    ],
                    onSelected: (seconds) => unawaited(
                      widget.service.setEpgPreviewDelay(
                        Duration(seconds: seconds),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),

        SettingsSectionHeader(l.settingsSectionDisplay),
        SettingsGroup(
          children: [
            if (_showHdrToggle)
              SettingsSwitchRow(
                title: l.settingsHdrMode,
                subtitle: l.settingsHdrModeHint,
                icon: Icons.hdr_on_outlined,
                value: _hdrEnabled,
                onChanged: widget.service.setHdrEnabled,
              ),
            if (_showRefreshRateToggle)
              SettingsSwitchRow(
                title: l.settingsMatchRefreshRate,
                subtitle: l.settingsMatchRefreshRateHint,
                icon: Icons.speed_outlined,
                value: _matchRefreshRate,
                onChanged: widget.service.setMatchRefreshRate,
              ),
            if (_showDeinterlaceToggle)
              SettingsSwitchRow(
                title: l.settingsDeinterlace,
                subtitle: l.settingsDeinterlaceHint,
                icon: Icons.reorder,
                value: _deinterlace,
                onChanged: widget.service.setDeinterlace,
              ),
            if (_showNavigationSoundToggle)
              SettingsSwitchRow(
                title: l.settingsNavigationSound,
                subtitle: l.settingsNavigationSoundHint,
                icon: Icons.volume_up_outlined,
                value: _navigationSoundEnabled,
                onChanged: widget.service.setNavigationSoundEnabled,
              ),
            SettingsRow(
              title: l.settingsOptimizeFor,
              subtitle: _optimizeForLabel(l, _optimizeFor),
              icon: Icons.tune,
              trailing: const SettingsChevron(),
              onTap: () => unawaited(
                pushSettingsPicker<OptimizeFor>(
                  context,
                  title: (context) =>
                      AppLocalizations.of(context).settingsOptimizeFor,
                  onBack: widget.onHandleTopLevelBack,
                  selected: _optimizeFor,
                  options: [
                    SettingsPickerOption(
                      value: OptimizeFor.quality,
                      label: l.settingsOptimizeForQuality,
                    ),
                    SettingsPickerOption(
                      value: OptimizeFor.speed,
                      label: l.settingsOptimizeForSpeed,
                    ),
                  ],
                  onSelected: widget.service.setOptimizeFor,
                ),
              ),
            ),
            SettingsRow(
              title: l.settingsFontSize,
              subtitle: _fontSizeLabel(l, _fontSize),
              icon: Icons.format_size,
              trailing: const SettingsChevron(),
              onTap: () => unawaited(
                pushSettingsPicker<AppFontSize>(
                  context,
                  title: (context) =>
                      AppLocalizations.of(context).settingsFontSize,
                  onBack: widget.onHandleTopLevelBack,
                  selected: _fontSize,
                  options: [
                    SettingsPickerOption(
                      value: AppFontSize.normal,
                      label: l.settingsFontSizeNormal,
                      icon: Icons.smartphone,
                    ),
                    SettingsPickerOption(
                      value: AppFontSize.large,
                      label: l.settingsFontSizeLarge,
                    ),
                    SettingsPickerOption(
                      value: AppFontSize.veryLarge,
                      label: l.settingsFontSizeVeryLarge,
                      icon: Icons.tv,
                    ),
                  ],
                  onSelected: widget.service.setFontSize,
                ),
              ),
            ),
          ],
        ),

        SettingsSectionHeader(l.settingsSectionFilters),
        SettingsGroup(
          children: [
            SettingsSwitchRow(
              title: l.settingsFilterPersistence,
              subtitle: _rememberMediaSort
                  ? l.settingsFilterPersistenceRemember
                  : l.settingsFilterPersistenceReset,
              icon: Icons.filter_alt_outlined,
              value: _rememberMediaSort,
              onChanged: widget.service.setRememberMediaSort,
            ),
          ],
        ),
      ],
    );
  }
}

String _startPageLabel(AppLocalizations l, DefaultStartPage page) =>
    switch (page) {
      DefaultStartPage.home => l.navHome,
      DefaultStartPage.search => l.navSearch,
      DefaultStartPage.liveTv => l.navLiveTv,
      DefaultStartPage.movies => l.navVod,
      DefaultStartPage.series => l.navSeries,
    };

String _homeScreenStyleLabel(AppLocalizations l, HomeScreenStyle style) =>
    switch (style) {
      HomeScreenStyle.simplified => l.settingsHomeScreenStyleSimplified,
      HomeScreenStyle.rich => l.settingsHomeScreenStyleRich,
    };

String _liveTvLayoutLabel(AppLocalizations l, LiveTvLayout layout) =>
    switch (layout) {
      LiveTvLayout.list => l.settingsLiveTvLayoutList,
      LiveTvLayout.grid => l.settingsLiveTvLayoutGrid,
      LiveTvLayout.timeline => l.settingsLiveTvLayoutTimeline,
    };

String _channelColumnLabel(AppLocalizations l, ChannelColumnLayout layout) =>
    switch (layout) {
      ChannelColumnLayout.logoAndTitle =>
        l.settingsLiveTvChannelColumnLogoTitle,
      ChannelColumnLayout.logoOnly => l.settingsLiveTvChannelColumnLogoOnly,
      ChannelColumnLayout.titleOnly => l.settingsLiveTvChannelColumnTitleOnly,
    };

String _epgStartViewLabel(AppLocalizations l, EpgStartView view) =>
    switch (view) {
      EpgStartView.currentTime => l.settingsEpgStartViewCurrentTime,
      EpgStartView.primeTime => l.settingsEpgStartViewPrimeTime,
    };

String _epgPreviewPlaybackLabel(
  AppLocalizations l,
  EpgPreviewPlayback mode,
) => switch (mode) {
  EpgPreviewPlayback.off => l.settingsEpgPreviewPlaybackOff,
  EpgPreviewPlayback.pauseToPlay => l.settingsEpgPreviewPlaybackPauseToPlay,
  EpgPreviewPlayback.clickToPreview =>
    l.settingsEpgPreviewPlaybackClickToPreview,
};

String _optimizeForLabel(AppLocalizations l, OptimizeFor optimizeFor) =>
    switch (optimizeFor) {
      OptimizeFor.quality => l.settingsOptimizeForQuality,
      OptimizeFor.speed => l.settingsOptimizeForSpeed,
    };

String _fontSizeLabel(AppLocalizations l, AppFontSize fontSize) =>
    switch (fontSize) {
      AppFontSize.normal => l.settingsFontSizeNormal,
      AppFontSize.large => l.settingsFontSizeLarge,
      AppFontSize.veryLarge => l.settingsFontSizeVeryLarge,
    };
