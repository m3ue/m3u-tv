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
}
