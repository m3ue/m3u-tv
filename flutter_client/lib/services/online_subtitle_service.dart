import 'dart:io';

import 'package:m3u_tv/services/api_client.dart';
import 'package:path_provider/path_provider.dart';

/// One subtitle file offered by a subtitle add-on.
class OnlineSubtitle {
  const OnlineSubtitle({
    required this.id,
    required this.url,
    required this.language,
    required this.release,
    this.fileExtension = 'srt',
  });

  final String id;
  final String url;

  /// As the add-on sends it, usually ISO 639-2 (`eng`, `pob`).
  final String language;

  /// The release the subtitle was made for, shown to tell matches apart.
  final String release;
  final String fileExtension;
}

/// Thrown when a subtitle can't be searched for or downloaded.
class OnlineSubtitleException implements Exception {
  const OnlineSubtitleException(this.message);

  final String message;

  @override
  String toString() => 'OnlineSubtitleException: $message';
}

/// Finds and fetches subtitles through a Stremio subtitle add-on
/// (`GET <addon>/subtitles/<type>/<id>.json`), which needs no key or account.
///
/// Downloads go to a local file, not straight to the player: mpv's `sub-add`
/// runs on the caller's thread, which on Linux and Windows is the UI thread,
/// so a remote URL would freeze the app until the download finished.
class OnlineSubtitleService {
  OnlineSubtitleService({
    ApiClient? apiClient,
    Future<Directory> Function()? cacheDirectory,
  }) : _injectedApi = apiClient,
       _cacheDirectory = cacheDirectory ?? _defaultCacheDirectory;

  static const int _maxFileBytes = 5 * 1024 * 1024;
  static const Duration _keepFilesFor = Duration(days: 1);
  static const Set<String> _knownExtensions = {'srt', 'vtt', 'ass', 'ssa'};
  static final _imdbId = RegExp(r'^tt\d+$');

  final ApiClient? _injectedApi;
  final Future<Directory> Function() _cacheDirectory;
  ApiClient? _ownedApi;
  ApiClient get _api => _injectedApi ?? (_ownedApi ??= ApiClient());

  static Future<Directory> _defaultCacheDirectory() async {
    final temp = await getTemporaryDirectory();
    return Directory('${temp.path}/online_subtitles');
  }

  /// Whether [id] is something an add-on can look up.
  static bool isSearchableId(String? id) => id != null && _imdbId.hasMatch(id);

  /// Searches [addonUrl] for a movie, or an episode when both [season] and
  /// [episode] are given. Throws [OnlineSubtitleException] on failure; no
  /// matches is an empty list.
  Future<List<OnlineSubtitle>> search({
    required String addonUrl,
    required String imdbId,
    int? season,
    int? episode,
  }) async {
    if (!isSearchableId(imdbId)) {
      throw const OnlineSubtitleException('Not an IMDb id');
    }
    final isEpisode = season != null && episode != null;
    final path = isEpisode
        ? 'subtitles/series/$imdbId:$season:$episode.json'
        : 'subtitles/movie/$imdbId.json';
    final Object? decoded;
    try {
      final response = await _api.send('GET', Uri.parse('$addonUrl/$path'));
      if (response.statusCode >= 400) {
        throw OnlineSubtitleException('HTTP ${response.statusCode}');
      }
      decoded = await response.json();
    } on OnlineSubtitleException {
      rethrow;
    } on Object catch (_) {
      throw const OnlineSubtitleException('Search failed');
    }
    final entries = decoded is Map ? decoded['subtitles'] : null;
    if (entries is! List) return const [];
    final seenUrls = <String>{};
    return [
      for (final entry in entries)
        if (_parse(entry) case final subtitle?)
          if (seenUrls.add(subtitle.url)) subtitle,
    ];
  }

  OnlineSubtitle? _parse(Object? entry) {
    if (entry is! Map) return null;
    final url = entry['url'];
    final language = entry['lang'];
    if (url is! String || language is! String || language.isEmpty) return null;
    // An add-on's address is user-supplied, so never hand the player anything
    // but a web download.
    final uri = Uri.tryParse(url);
    if (uri == null || !(uri.isScheme('https') || uri.isScheme('http'))) {
      return null;
    }
    final fileName = entry['subtitleFileName'];
    final releaseName = entry['movieReleaseName'];
    final extension = fileName is String && fileName.contains('.')
        ? fileName.split('.').last.toLowerCase()
        : '';
    final id = '${entry['id'] ?? url.hashCode}';
    return OnlineSubtitle(
      id: id,
      url: url,
      language: language,
      release: releaseName is String && releaseName.isNotEmpty
          ? releaseName
          : (fileName is String && fileName.isNotEmpty ? fileName : id),
      fileExtension: _knownExtensions.contains(extension) ? extension : 'srt',
    );
  }

  /// Downloads [subtitle] and returns the local file's path. Throws
  /// [OnlineSubtitleException] on failure.
  Future<String> download(OnlineSubtitle subtitle) async {
    try {
      final response = await _api.send('GET', Uri.parse(subtitle.url));
      if (response.statusCode >= 400) {
        throw OnlineSubtitleException('HTTP ${response.statusCode}');
      }
      final bytes = response.bytes;
      if (bytes.isEmpty || bytes.length > _maxFileBytes) {
        throw const OnlineSubtitleException('Unexpected file size');
      }
      final directory = await _cacheDirectory();
      await directory.create(recursive: true);
      await _deleteOldFiles(directory);
      // The id comes from the add-on, so keep it out of the path's structure.
      final safeId = subtitle.id.replaceAll(RegExp('[^A-Za-z0-9_-]'), '_');
      final file = File(
        '${directory.path}/$safeId.${subtitle.fileExtension}',
      );
      await file.writeAsBytes(bytes, flush: true);
      return file.path;
    } on OnlineSubtitleException {
      rethrow;
    } on Object catch (_) {
      throw const OnlineSubtitleException('Download failed');
    }
  }

  Future<void> _deleteOldFiles(Directory directory) async {
    final cutoff = DateTime.now().subtract(_keepFilesFor);
    await for (final entity in directory.list()) {
      if (entity is! File) continue;
      try {
        if ((await entity.lastModified()).isBefore(cutoff)) {
          await entity.delete();
        }
      } on FileSystemException catch (_) {
        // A file another download is using, or already gone.
      }
    }
  }

  void dispose() => _ownedApi?.close();
}

/// The name of a subtitle [code] in its own language, or the code in capitals
/// when it isn't a known one. Add-ons send ISO 639-2, with `pob` for Brazilian
/// Portuguese.
String onlineSubtitleLanguageName(String code) =>
    _languageNames[code.toLowerCase()] ?? code.toUpperCase();

/// The add-on code for a device language such as `de`, if it's a known one.
String? onlineSubtitleCodeForLocale(String languageCode) =>
    _languageCodesByLocale[languageCode.toLowerCase()];

const _languageNames = <String, String>{
  'ara': 'العربية',
  'bul': 'Български',
  'cat': 'Català',
  'chi': '中文',
  'zho': '中文',
  'ze': '中文 / English',
  'zht': '繁體中文',
  'cze': 'Čeština',
  'ces': 'Čeština',
  'dan': 'Dansk',
  'dut': 'Nederlands',
  'nld': 'Nederlands',
  'eng': 'English',
  'est': 'Eesti',
  'fin': 'Suomi',
  'fre': 'Français',
  'fra': 'Français',
  'ger': 'Deutsch',
  'deu': 'Deutsch',
  'ell': 'Ελληνικά',
  'gre': 'Ελληνικά',
  'heb': 'עברית',
  'hin': 'हिन्दी',
  'hrv': 'Hrvatski',
  'hun': 'Magyar',
  'ice': 'Íslenska',
  'isl': 'Íslenska',
  'ind': 'Bahasa Indonesia',
  'ita': 'Italiano',
  'jpn': '日本語',
  'kor': '한국어',
  'lav': 'Latviešu',
  'lit': 'Lietuvių',
  'may': 'Bahasa Melayu',
  'msa': 'Bahasa Melayu',
  'nor': 'Norsk',
  'per': 'فارسی',
  'fas': 'فارسی',
  'pol': 'Polski',
  'por': 'Português',
  'pob': 'Português (Brasil)',
  'rum': 'Română',
  'ron': 'Română',
  'rus': 'Русский',
  'scc': 'Srpski',
  'srp': 'Srpski',
  'slo': 'Slovenčina',
  'slk': 'Slovenčina',
  'slv': 'Slovenščina',
  'spa': 'Español',
  'spl': 'Español (Latinoamérica)',
  'spn': 'Español (Latinoamérica)',
  'swe': 'Svenska',
  'tha': 'ไทย',
  'tur': 'Türkçe',
  'ukr': 'Українська',
  'vie': 'Tiếng Việt',
};

const _languageCodesByLocale = <String, String>{
  'ar': 'ara',
  'bg': 'bul',
  'ca': 'cat',
  'cs': 'cze',
  'da': 'dan',
  'de': 'ger',
  'el': 'ell',
  'en': 'eng',
  'es': 'spa',
  'et': 'est',
  'fa': 'per',
  'fi': 'fin',
  'fr': 'fre',
  'he': 'heb',
  'hi': 'hin',
  'hr': 'hrv',
  'hu': 'hun',
  'id': 'ind',
  'is': 'ice',
  'it': 'ita',
  'ja': 'jpn',
  'ko': 'kor',
  'lt': 'lit',
  'lv': 'lav',
  'ms': 'may',
  'nb': 'nor',
  'nl': 'dut',
  'nn': 'nor',
  'no': 'nor',
  'pl': 'pol',
  'pt': 'por',
  'ro': 'rum',
  'ru': 'rus',
  'sk': 'slo',
  'sl': 'slv',
  'sr': 'scc',
  'sv': 'swe',
  'th': 'tha',
  'tr': 'tur',
  'uk': 'ukr',
  'vi': 'vie',
  'zh': 'chi',
};
