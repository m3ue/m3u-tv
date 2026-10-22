import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:m3u_tv/services/xtream_http_transport_common.dart';
import 'package:m3u_tv/services/xtream_service.dart';

XtreamTransport createDefaultXtreamTransport() {
  // The browser's own networking: no connect timeout to set, and headers the
  // browser controls (User-Agent and the like) are silently dropped.
  final client = http.Client();
  return (XtreamRequest request) => _send(client, request);
}

Future<Object?> _send(http.Client client, XtreamRequest request) async {
  final uri = buildXtreamUri(request);
  final httpRequest = http.Request(request.method, uri)
    ..headers.addAll(request.headers);
  if (request.method == 'POST' && request.body.isNotEmpty) {
    httpRequest
      ..headers['content-type'] = 'application/json; charset=utf-8'
      ..bodyBytes = utf8.encode(jsonEncode(request.body));
  }
  final response = await http.Response.fromStream(
    await client.send(httpRequest),
  );
  return handleXtreamResponse(
    request: request,
    uri: uri,
    statusCode: response.statusCode,
    reasonPhrase: response.reasonPhrase,
    text: utf8.decode(response.bodyBytes, allowMalformed: true),
  );
}
