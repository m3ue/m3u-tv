import 'package:m3u_tv/services/domain_models.dart';

class M3UParseException implements Exception {
  const M3UParseException(this.message, {this.line});

  final String message;
  final int? line;

  @override
  String toString() => line == null ? message : 'Line $line: $message';
}

class M3UPlaylist {
  const M3UPlaylist({
    required this.channels,
    required this.categories,
    this.metadata = const {},
  });

  final List<Channel> channels;
  final List<Category> categories;
  final Map<String, String> metadata;
}

class M3UParser {
  M3UPlaylist parse(String text) {
    final lines = text.split(RegExp(r'\r?\n'));
    final firstContent = lines.indexWhere((line) => line.trim().isNotEmpty);
    if (firstContent == -1 ||
        !lines[firstContent].trimLeft().startsWith('#EXTM3U')) {
      throw const M3UParseException('Playlist must start with #EXTM3U');
    }

    final metadata = _parseAttributes(
      lines[firstContent].trim().replaceFirst('#EXTM3U', '').trim(),
    );
    final channels = <Channel>[];
    _PendingEntry? pending;
    var nextId = 1;

    for (var index = firstContent + 1; index < lines.length; index++) {
      final line = lines[index].trim();
      if (line.isEmpty) continue;

      if (line.startsWith('#EXTINF:')) {
        if (pending != null) {
          throw M3UParseException(
            'EXTINF entry is missing a stream URL',
            line: index + 1,
          );
        }
        pending = _PendingEntry.fromExtinf(line, index + 1);
        continue;
      }

      if (line.startsWith('#EXTVLCOPT:')) {
        pending?.headers.addAll(
          _parseVlcOption(line.substring('#EXTVLCOPT:'.length)),
        );
        continue;
      }

      if (line.startsWith('#EXTHTTP:')) {
        pending?.headers.addAll(
          _parseHeaderOption(line.substring('#EXTHTTP:'.length)),
        );
        continue;
      }

      if (line.startsWith('#')) continue;

      if (pending == null) {
        throw M3UParseException(
          'Stream URL has no preceding EXTINF metadata',
          line: index + 1,
        );
      }
      channels.add(pending.toChannel(nextId++, line));
      pending = null;
    }

    if (pending != null) {
      throw M3UParseException(
        'EXTINF entry is missing a stream URL',
        line: pending.line,
      );
    }

    final categoryNames = <String, String>{};
    for (final channel in channels) {
      final name = _normalizeGroup(channel.groupTitle);
      categoryNames.putIfAbsent(name.toLowerCase(), () => name);
    }
    final categories = categoryNames.values
        .map((name) => Category(id: _categoryId(name), name: name))
        .toList(growable: false);

    return M3UPlaylist(
      channels: channels,
      categories: categories,
      metadata: metadata,
    );
  }

  Map<String, String> _parseVlcOption(String option) {
    final parts = option.split('=');
    if (parts.length < 2) return const {};
    final key = parts.first.trim().toLowerCase();
    final value = parts.sublist(1).join('=').trim();
    return switch (key) {
      'http-user-agent' => {'User-Agent': value},
      'http-referrer' => {'Referer': value},
      'http-header' => _parseHeaderOption(value),
      _ => {key: value},
    };
  }

  Map<String, String> _parseHeaderOption(String option) {
    final separator = option.contains('=') ? '=' : ':';
    final index = option.indexOf(separator);
    if (index <= 0) return const {};
    return {
      option.substring(0, index).trim(): option.substring(index + 1).trim(),
    };
  }
}

class _PendingEntry {
  _PendingEntry({
    required this.line,
    required this.name,
    required this.attributes,
    required this.headers,
  });

  factory _PendingEntry.fromExtinf(String line, int lineNumber) {
    final commaIndex = line.indexOf(',');
    if (commaIndex == -1) {
      throw M3UParseException(
        'EXTINF entry is missing display name',
        line: lineNumber,
      );
    }
    final info = line.substring(0, commaIndex);
    final displayName = line.substring(commaIndex + 1).trim();
    return _PendingEntry(
      line: lineNumber,
      name: displayName,
      attributes: _parseAttributes(info),
      headers: <String, String>{},
    );
  }

  final int line;
  final String name;
  final Map<String, String> attributes;
  final Map<String, String> headers;

  Channel toChannel(int id, String streamUrl) {
    final group = _normalizeGroup(attributes['group-title']);
    final tvgName = attributes['tvg-name'];
    final catchupSource = attributes['catchup-source'];
    final catchupType = attributes['catchup'];
    final catchupSupported =
        catchupSource != null || (catchupType != null && catchupType != '0');
    return Channel(
      id: id,
      name: name.isNotEmpty ? name : (tvgName ?? 'Channel $id'),
      streamUrl: streamUrl,
      logoUrl: attributes['tvg-logo'],
      categoryId: _categoryId(group),
      groupTitle: group,
      epgChannelId: attributes['tvg-id'],
      tvgName: tvgName,
      headers: Map.unmodifiable(headers),
      catchupSupported: catchupSupported,
      catchupDays: int.tryParse(attributes['catchup-days'] ?? ''),
      catchupSource: catchupSource,
    );
  }
}

Map<String, String> _parseAttributes(String text) {
  final result = <String, String>{};
  final pattern = RegExp(r'([A-Za-z0-9_-]+)\s*=\s*("([^"]*)"|([^\s"]+))');
  for (final match in pattern.allMatches(text)) {
    result[match.group(1)!] = match.group(3) ?? match.group(4) ?? '';
  }
  return result;
}

String _normalizeGroup(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? 'Ungrouped' : trimmed;
}

String _categoryId(String name) => name
    .toLowerCase()
    .replaceAll(RegExp('[^a-z0-9]+'), '-')
    .replaceAll(RegExp(r'^-|-$'), '');
