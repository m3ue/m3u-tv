import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:m3u_tv/services/xtream_http_transport_common.dart';
import 'package:m3u_tv/services/xtream_service.dart';

XtreamTransport createDefaultXtreamTransport() {
  // Bounds only the socket connect (the OS default runs to a minute or more
  // against an unreachable host). Deliberately no response timeout: this
  // client also downloads whole catalogs, which a large playlist can take a
  // long time to generate.
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
  return (XtreamRequest request) => _send(client, request);
}

Future<Object?> _send(HttpClient client, XtreamRequest request) async {
  final uri = buildXtreamUri(request);
  final httpRequest = request.method == 'POST'
      ? await client.postUrl(uri)
      : await client.getUrl(uri);

  for (final header in request.headers.entries) {
    httpRequest.headers.set(header.key, header.value);
  }

  if (request.method == 'POST' && request.body.isNotEmpty) {
    final bytes = utf8.encode(jsonEncode(request.body));
    httpRequest.headers.contentType = ContentType.json;
    httpRequest
      ..contentLength = bytes.length
      ..add(bytes);
  }

  final response = await httpRequest.close();
  // Kept as bytes: decoding to a String here would run the UTF-8 pass for a
  // whole catalog on the UI isolate, then copy the String to the parse
  // isolate.
  final body = BytesBuilder(copy: false);
  await response.forEach(body.add);
  return handleXtreamResponse(
    request: request,
    uri: uri,
    statusCode: response.statusCode,
    reasonPhrase: response.reasonPhrase,
    bytes: body.takeBytes(),
  );
}
