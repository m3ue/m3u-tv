// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get navHome => '主页';

  @override
  String get navSearch => '搜索';

  @override
  String get navLiveTv => '直播电视';

  @override
  String get navVod => '电影';

  @override
  String get navSeries => '剧集';

  @override
  String get navDvr => '录像';

  @override
  String get navRequests => '请求';

  @override
  String get navNotifications => '通知';

  @override
  String get navSettings => '设置';

  @override
  String get navMore => '更多';

  @override
  String get notificationsDesktopOpen => '打开';

  @override
  String get appBackToExit => '再次按返回键退出';

  @override
  String appRecordingScheduled(String title) {
    return '录制已安排：$title';
  }

  @override
  String appRecordingFailed(String error) {
    return '无法安排录制：$error';
  }

  @override
  String get appNotConfigured => '请在设置中连接您的服务';

  @override
  String get cancel => '取消';

  @override
  String get disconnect => '断开连接';

  @override
  String get unknown => '未知';

  @override
  String get admin => '管理员';

  @override
  String get liveTvSearchHint => '搜索直播电视…';

  @override
  String get liveTvNoChannels => '暂无可用频道';

  @override
  String get liveTvAllChannels => '全部频道';

  @override
  String get liveTvFavorites => '★ 收藏';

  @override
  String get liveTvNoProgram => '暂无节目信息';

  @override
  String get liveTvNext => '下一个';

  @override
  String get liveTvRecord => '录制';

  @override
  String get liveTvRecording => '录制中';

  @override
  String get liveTvFavorite => '收藏';

  @override
  String get liveTvRemoveFavorite => '取消收藏';

  @override
  String get catchupBadgeAvailable => '可回看';

  @override
  String catchupBadgeAvailableDays(int days) {
    return '可回看 $days 天';
  }

  @override
  String get catchupProgramReplayable => '可回看重播';

  @override
  String get epgPreviousDay => '前一天';

  @override
  String get epgNow => '现在';

  @override
  String get epgNextDay => '后一天';

  @override
  String get epgChannels => '频道';

  @override
  String get epgNoData => '暂无 EPG 数据';

  @override
  String get playerGoBack => '返回';

  @override
  String get playerResumeWatching => '继续观看';

  @override
  String get playerContinue => '继续';

  @override
  String playerFromTime(String time) {
    return '从 $time 开始';
  }

  @override
  String get playerStartFromBeginning => '从头开始';

  @override
  String get playerResume => '恢复播放';

  @override
  String get playerSkipPreviousTooltip => '上一个频道';

  @override
  String get playerSkipNextTooltip => '下一个频道';

  @override
  String get playerNowPlayingMovie => '电影';

  @override
  String get playerNowPlayingSeries => '剧集';

  @override
  String playerNowPlayingSeasonEpisode(int season, int episode) {
    return '第$season季 · 第$episode集';
  }

  @override
  String get playerCommercialSkipped => '已跳过广告';

  @override
  String get playerSkipCommercial => '跳过广告';

  @override
  String get searchHint => '搜索直播电视、电影和剧集…';

  @override
  String get searchSectionLiveTv => '直播电视';

  @override
  String get searchSectionMovies => '电影';

  @override
  String get searchSectionSeries => '剧集';

  @override
  String get vodSearchHint => '搜索电影…';

  @override
  String get seriesSearchHint => '搜索剧集…';

  @override
  String get settingsTitle => '设置';

  @override
  String get settingsGeneral => '通用';

  @override
  String get settingsIntegrations => '集成';

  @override
  String get settingsLanguage => '语言';

  @override
  String get settingsLanguageSystem => '系统语言';

  @override
  String get settingsLangEnglish => '英语';

  @override
  String get settingsLangGerman => '德语';

  @override
  String get settingsLangSpanish => '西班牙语';

  @override
  String get settingsLangFrench => '法语';

  @override
  String get settingsLangChinese => '中文（简体）';

  @override
  String get settingsConnection => '连接';

  @override
  String get settingsStatusConnected => '已连接';

  @override
  String get settingsStatusUnavailable => '不可用';

  @override
  String get settingsStatusLabel => '状态';

  @override
  String get settingsSourceLabel => '来源';

  @override
  String get settingsServerTimezone => '服务器时区';

  @override
  String get settingsLastError => '最近错误';

  @override
  String get settingsRetryConnection => '重试连接';

  @override
  String get settingsEditServer => '编辑服务器设置';

  @override
  String get settingsActiveViewer => '当前用户';

  @override
  String get settingsClearCacheTitle => '清除缓存并刷新？';

  @override
  String get settingsClearCacheBody => '所有缓存内容将被清除并从您的来源重新加载。';

  @override
  String get settingsClearCacheConfirm => '清除并刷新';

  @override
  String get settingsCacheCleared => '缓存已清除 — 内容正在后台刷新。';

  @override
  String get settingsContentCache => '内容缓存';

  @override
  String get settingsCacheSubtitle => '缓存内容即时加载，数据在后台自动刷新。';

  @override
  String get settingsEpgRefreshInterval => 'EPG 刷新间隔';

  @override
  String settingsEpgDurationMinutes(int count) {
    return '$count 分钟';
  }

  @override
  String get settingsEpgDurationHour => '1 小时';

  @override
  String settingsEpgDurationHours(int count) {
    return '$count 小时';
  }

  @override
  String get settingsManageViewers => '管理用户';

  @override
  String get settingsAddViewer => '添加新用户';

  @override
  String get settingsSwitchViewer => '切换用户';

  @override
  String get settingsViewerNameLabel => '用户名称';

  @override
  String get settingsCreate => '创建';

  @override
  String get settingsAccount => '账户';

  @override
  String get settingsProxyPlayback => '代理播放';

  @override
  String get settingsProxyPlaybackSubtitle =>
      '通过 m3u-editor 代理播放，并可为此设备选择转码配置。';

  @override
  String get settingsProxyUse => '使用代理';

  @override
  String get settingsProxyForced => '代理已在播放列表级别启用，无法关闭。';

  @override
  String get settingsProxyLiveProfile => '直播转码配置';

  @override
  String get settingsProxyVodProfile => '点播和剧集转码配置';

  @override
  String get settingsProxyProfileDefault => '默认';

  @override
  String get settingsProxyProfileDirect => '直连（不转码）';

  @override
  String get settingsProxyNoProfiles => '没有可用的转码配置——将使用直连代理播放。';

  @override
  String get settingsDvr => 'DVR';

  @override
  String get settingsDvrSubtitle => '录制内容播放设置。';

  @override
  String get settingsComskip => '广告跳过';

  @override
  String get settingsComskipSubtitle => '控制播放器在录制内容中检测到广告时的处理方式。';

  @override
  String get settingsComskipAutoSkip => '自动跳过广告';

  @override
  String get settingsDisconnectTitle => '断开连接？';

  @override
  String get settingsDisconnectBody => '您将被退出登录，需要重新输入凭据才能重新连接。';

  @override
  String get settingsDisconnectConfirm => '断开连接';

  @override
  String get settingsApp => '应用';

  @override
  String get settingsAppVersion => '版本';

  @override
  String get settingsAppUpdateStatus => '更新';

  @override
  String get settingsAppVersionChecking => '正在检查更新…';

  @override
  String get settingsAppUpToDate => '已是最新版本';

  @override
  String settingsAppUpdateAvailable(String version) {
    return '有可用更新：$version';
  }

  @override
  String get settingsAppViewRelease => '查看版本';

  @override
  String get settingsAppScanQr => '扫描以在手机上打开';

  @override
  String get settingsFillAllFields => '请填写所有字段';

  @override
  String get settingsConnectionSettings => '连接设置';

  @override
  String get settingsConnectionSettingsSubtitle => '输入您的 Xtream Codes 信息';

  @override
  String get settingsServerUrl => '服务器地址';

  @override
  String get settingsUsername => '用户名';

  @override
  String get settingsPassword => '密码';

  @override
  String get settingsConnect => '连接';

  @override
  String get settingsPairWithCode => '使用代码配对';

  @override
  String get settingsTabPair => '配对';

  @override
  String get settingsTabSignIn => '登录';

  @override
  String get settingsPairTabSubtitle => '输入您的服务器地址，然后使用代码配对此电视。';

  @override
  String get pairingEnterServerFirst => '请先输入您的服务器地址';

  @override
  String get pairingErrorGeneric => '配对失败或代码已过期，请重试。';

  @override
  String get pairingScanQr => '扫描以在手机上打开配对页面';

  @override
  String get pairingOpenBrowser => '在浏览器中打开';

  @override
  String get pairingPendingGoTo => '在您的手机或电脑上，访问：';

  @override
  String get pairingPendingEnterCode => '然后输入此代码：';

  @override
  String get pairingPendingWaiting => '等待批准…';

  @override
  String get homeContinueWatching => '继续观看';

  @override
  String get homeNoContinueWatching => '暂无可继续观看的内容';

  @override
  String get homeNoLiveTv => '暂无直播电视';

  @override
  String get homeFavoriteChannels => '收藏频道';

  @override
  String get homeNoFavoriteChannels => '暂无收藏频道';

  @override
  String get homeNoMovies => '暂无电影';

  @override
  String get homeLiveChannel => '直播频道';

  @override
  String get homeMovie => '电影';

  @override
  String get notificationsTitle => '通知';

  @override
  String get notificationsTabNotifications => '通知';

  @override
  String get notificationsTabChannelSettings => '频道设置';

  @override
  String get notificationsMarkAllRead => '全部标为已读';

  @override
  String get notificationsEmpty => '暂无通知';

  @override
  String get notificationsEmptyFiltered => '订阅频道暂无通知';

  @override
  String get notificationsChannelSubscriptions => '频道订阅';

  @override
  String get notificationsChannelSubtitle => '选择您希望接收的频道。全部不选则接收所有通知。';

  @override
  String get notificationsAllChannels => '全部频道';

  @override
  String get notificationsNoChannels => '暂无频道 — 收到通知后将在此显示。';

  @override
  String get notificationsJustNow => '刚刚';

  @override
  String notificationsMinutesAgo(int count) {
    return '$count分钟前';
  }

  @override
  String notificationsHoursAgo(int count) {
    return '$count小时前';
  }

  @override
  String notificationsDaysAgo(int count) {
    return '$count天前';
  }

  @override
  String notificationsReceivedAt(String time) {
    return '收到 $time';
  }

  @override
  String notificationsReadAt(String time) {
    return '已读 $time';
  }

  @override
  String get homeNoSeries => '暂无剧集';

  @override
  String homeSeason(int number) {
    return '第$number季';
  }

  @override
  String get traktWatchHistory => '观看历史';

  @override
  String get traktWatchHistorySubtitle => '将您的观看历史与 Trakt 同步，在各应用和服务间追踪进度。';

  @override
  String get traktNotConfigured => 'Trakt 客户端凭据未配置。';

  @override
  String get traktNotConfiguredHint =>
      '在 trakt.tv/oauth/applications 注册应用，并在构建时通过 --dart-define 设置 client ID 和 secret。';

  @override
  String get traktConnectPrompt => '连接您的 Trakt 账户，自动记录您的观看内容。';

  @override
  String get traktConnectButton => '连接 Trakt';

  @override
  String get traktScanQr => '扫描以在手机上打开';

  @override
  String get traktOpenBrowser => '在浏览器中打开';

  @override
  String get traktPendingGoTo => '在您的手机或电脑上，访问：';

  @override
  String get traktPendingEnterCode => '然后输入此代码：';

  @override
  String get traktPendingWaiting => '等待授权…';

  @override
  String get traktConnected => '已连接到 Trakt';

  @override
  String get traktDisconnectButton => '断开 Trakt';

  @override
  String get vodAllMovies => '全部电影';

  @override
  String get seriesAllSeries => '全部剧集';

  @override
  String homeConnectedSource(String label) {
    return '已连接来源：$label';
  }

  @override
  String get searchTypeToSearch => '输入以搜索';

  @override
  String get vodPlayMovie => '播放电影';

  @override
  String get vodContinueMovie => '继续播放';

  @override
  String get navAioStreams => 'AIOStreams';

  @override
  String get aiostreamsGetStreams => '获取播放源';

  @override
  String get aiostreamsLoadingStreams => '正在加载播放源…';

  @override
  String get aiostreamsNoStreams => '未找到播放源';

  @override
  String get aiostreamsSelectStream => '选择播放源';

  @override
  String get aiostreamsLoadMore => '加载更多';

  @override
  String get aiostreamsSearchHint => '搜索电影和剧集…';

  @override
  String get aiostrreamsCatalogEmpty => '暂无内容';

  @override
  String get aiostreamsToggleFavorite => '收藏';

  @override
  String get aiostreamsMyFavorites => '我的收藏';

  @override
  String get aiostreamsContinueWatching => '继续观看';

  @override
  String get aiostreamsSearch => '搜索 AIOStreams';

  @override
  String get aiostreamsSearchResults => '搜索结果';

  @override
  String get aiostreamsNoResults => '未找到结果';

  @override
  String get aiostreamsSearchAll => '全部';

  @override
  String get requestsTitle => '请求';

  @override
  String get requestsTabSearch => '搜索';

  @override
  String get requestsTabMyRequests => '我的请求';

  @override
  String get requestsSearchHint => '搜索电影和剧集…';

  @override
  String get requestsNoResults => '未找到结果';

  @override
  String get requestsAlreadyAvailable => '已可观看';

  @override
  String get requestsAlreadyRequested => '已请求';

  @override
  String get requestsRequestButton => '请求';

  @override
  String get requestsSeasonsHeading => '季';

  @override
  String get requestsSeasonSpecials => '特别篇';

  @override
  String get requestsSelectAllSeasons => '全选';

  @override
  String get requestsClearSeasons => '清除';

  @override
  String requestsSubmitted(String title) {
    return '已请求“$title”';
  }

  @override
  String requestsSubmittedPendingApproval(String title) {
    return '“$title”已提交等待批准';
  }

  @override
  String requestsSubmitFailed(String title, String error) {
    return '无法请求“$title”：$error';
  }

  @override
  String get requestsMyRequestsEmpty => '您还没有请求过任何内容';

  @override
  String get requestsDismiss => '移除';

  @override
  String requestsDismissFailed(String error) {
    return '无法移除请求：$error';
  }

  @override
  String get requestsStatusPendingApproval => '待批准';

  @override
  String get requestsStatusApproved => '已批准';

  @override
  String get requestsStatusRejected => '已拒绝';

  @override
  String get requestsStatusCompleted => '已完成';

  @override
  String get requestsStatusUnknown => '未知';

  @override
  String get dvrRecordingsTitle => 'DVR 录制';

  @override
  String get dvrRecordingsSubtitle => '已完成的录制和正在录制的节目';

  @override
  String get dvrNoRecordings => '没有可用的 DVR 录制';

  @override
  String get dvrNotConfigured => '请在设置中连接到您的服务';

  @override
  String get dvrCancel => '取消';

  @override
  String get dvrDelete => '删除';

  @override
  String dvrStopTitle(String title) {
    return '停止录制 — $title';
  }

  @override
  String get dvrStopMessage => '保留在录制列表中，还是立即删除？';

  @override
  String get dvrStopKeep => '保留录制';

  @override
  String get dvrStopDelete => '删除录制';

  @override
  String get dvrStopBack => '返回';

  @override
  String get dvrCancelSuccess => '录制已取消';

  @override
  String get dvrCancelFailed => '无法取消录制';

  @override
  String get dvrDeleteTitle => '删除录制？';

  @override
  String get dvrDeleteMessage => '此录制将被永久删除。';

  @override
  String get dvrDeleteDismiss => '保留';

  @override
  String get dvrDeleteConfirm => '删除录制';

  @override
  String get dvrDeleteSuccess => '录制已删除';

  @override
  String get dvrDeleteFailed => '无法删除录制';

  @override
  String get liveTvStopRecording => '停止录制';

  @override
  String get playerRecordNowTooltip => '录制当前节目';

  @override
  String get playerStopRecordingTooltip => '停止录制';

  @override
  String get dvrMoreActions => '更多操作';

  @override
  String get dvrPlay => '播放';

  @override
  String get dvrSelect => '选择';

  @override
  String get dvrStop => '停止';

  @override
  String get dvrStatusRecording => '正在录制';

  @override
  String get dvrStatusScheduled => '已计划';

  @override
  String get dvrStatusFailed => '失败';

  @override
  String get dvrExitSelection => '退出选择';

  @override
  String dvrSelectedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '已选择 $count 项',
      zero: '未选择任何项目',
    );
    return '$_temp0';
  }

  @override
  String get dvrStorageTitle => 'DVR 存储';

  @override
  String get dvrStorageUnlimited => '无限';

  @override
  String dvrStorageUsedUnlimited(String used) {
    return '已使用 $used';
  }

  @override
  String dvrStorageUsedWithQuota(String used, String quota) {
    return '已使用 $used，共 $quota';
  }

  @override
  String dvrStorageRecordingCount(int count) {
    return '$count 个录制';
  }

  @override
  String get dvrSeriesChannel => '频道';

  @override
  String get dvrSeriesStartEarly => '提前开始';

  @override
  String get dvrSeriesUseDefault => '使用默认';

  @override
  String dvrEpisodeCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 集',
      one: '1 集',
    );
    return '$_temp0';
  }

  @override
  String get dvrDeleteSeriesRule => '删除规则';

  @override
  String get dvrEditSeriesRule => '编辑规则';

  @override
  String get dvrUpdateSeriesRuleFailed => '无法更新剧集规则';

  @override
  String get dvrSeriesSave => '保存';

  @override
  String get dvrSeriesSecondsSuffix => '秒';

  @override
  String get dvrSeriesMode => '剧集模式';

  @override
  String get dvrUpdateSeriesRuleSuccess => '剧集规则已更新';

  @override
  String get dvrSeriesModeAll => '全部剧集';

  @override
  String get dvrSeriesMatchModeStartsWith => '开头匹配';

  @override
  String get dvrDeleteSeriesRuleConfirm => '确定删除此剧集规则？';

  @override
  String get dvrSeriesCancel => '取消';

  @override
  String get dvrDeleteSeriesRuleSuccess => '剧集规则已删除';

  @override
  String get dvrSeriesRulesTitle => '剧集规则';

  @override
  String get dvrSeriesMatchModeContains => '包含';

  @override
  String get dvrSeriesMatchModeExact => '精确';

  @override
  String get dvrSeriesModeUseDefault => '使用默认';

  @override
  String get dvrSeriesModeNewFlag => '仅新增';

  @override
  String get dvrDeleteSeriesRuleFailed => '无法删除剧集规则';

  @override
  String get dvrSeriesKeepLast => '保留最后';

  @override
  String get dvrSeriesModeUniqueSe => '唯一S-E';

  @override
  String get dvrSeriesAnyChannel => '任意频道';

  @override
  String get dvrSeriesMatchMode => '匹配模式';

  @override
  String get dvrSeriesEndLate => '延迟结束';

  @override
  String get dvrSeriesOptions => '选项';

  @override
  String dvrSeriesOptionsFor(String title) {
    return '选项：$title';
  }

  @override
  String get dvrSeriesAllEpisodesWarning =>
      '在任意频道录制全部剧集可能会产生重复——请使用仅新增或唯一S-E去重。';

  @override
  String get dvrSeriesRulesEmpty => '暂无剧集规则';

  @override
  String get dvrSeriesPriority => '优先级';

  @override
  String get epgRecordSeries => '录制整部剧集';

  @override
  String epgRecordSeriesSuccess(String title) {
    return '已为 $title 设置整剧录制';
  }

  @override
  String get epgRecordSeriesFailed => '无法设置整剧录制';

  @override
  String get epgRecordSeriesDuplicate => '整剧录制已设置';

  @override
  String get navShows => '剧集';

  @override
  String get showAiringNext => '下次播出';

  @override
  String get showAiringNone => 'EPG 中暂无即将播出的剧集';

  @override
  String showChannelCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 个频道',
      one: '1 个频道',
    );
    return '$_temp0';
  }

  @override
  String get showDeleteRule => '删除剧集规则';

  @override
  String showDeleteRuleConfirm(String title) {
    return '删除 $title 的剧集规则？未来剧集将不会被录制。已完成的录制不会被删除。';
  }

  @override
  String get showSeriesRuleActive => '剧集规则已启用';

  @override
  String get showDetailTitle => '节目详情';

  @override
  String showEpisodesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 集',
      one: '1 集',
    );
    return '$_temp0';
  }

  @override
  String get showRecordSeries => '录制整部剧集';

  @override
  String showRecordSeriesConfirm(String title, String channel) {
    return '在 $channel 录制 $title 的每一集？';
  }

  @override
  String showRecordSeriesFailed(String title) {
    return '无法为 $title 设置整剧录制';
  }

  @override
  String showRecordSeriesSuccess(String title) {
    return '已为 $title 设置整剧录制';
  }

  @override
  String showRecordSeriesDuplicate(String title) {
    return '已为 $title 设置过整剧录制';
  }

  @override
  String get showsError => '无法搜索剧集';

  @override
  String get showsNoResults => '未找到匹配的剧集';

  @override
  String get showsSearchError => '搜索失败';

  @override
  String get showsSearchHint => '按标题搜索剧集';

  @override
  String get showsTitle => '剧集';

  @override
  String showNotFound(String title) {
    return '未找到剧集“$title”';
  }
}
