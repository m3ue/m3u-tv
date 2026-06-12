import 'dart:convert';
import 'dart:io';

import 'xtream_service.dart';

XtreamTransport createDefaultXtreamTransport() {
  final client = HttpClient();
  return (XtreamRequest request) => _send(client, request);
}

Future<Object?> _send(HttpClient client, XtreamRequest request) async {
  final uri = _buildUri(request);
  final httpRequest = request.method == 'POST'
      ? await client.postUrl(uri)
      : await client.getUrl(uri);

  for (final header in request.headers.entries) {
    httpRequest.headers.set(header.key, header.value);
  }

  if (request.method == 'POST' && request.body.isNotEmpty) {
    final bytes = utf8.encode(jsonEncode(request.body));
    httpRequest.headers.contentType = ContentType.json;
    httpRequest.contentLength = bytes.length;
    httpRequest.add(bytes);
  }

  final response = await httpRequest.close();
  final text = await utf8.decodeStream(response);
  if (text.isEmpty) return null;
  final body = jsonDecode(text);
  if (response.statusCode >= HttpStatus.badRequest) {
    throw XtreamHttpException(
      statusCode: response.statusCode,
      reasonPhrase: response.reasonPhrase,
      method: request.method,
      uri: uri,
      serverMessage: _serverMessage(body),
    );
  }
  return body;
}

String? _serverMessage(Object? body) {
  if (body is! Map) return null;
  final json = body.cast<Object?, Object?>();
  final value = json['error'] ?? json['message'] ?? json['detail'] ?? json['error_code'];
  if (value == null) return null;
  return '$value';
}

Uri _buildUri(XtreamRequest request) {
  final base = Uri.parse(request.credentials.server);
  final path = base.path.endsWith('/player_api.php')
      ? base.path
      : '${base.path.replaceAll(RegExp(r'/+$'), '')}/player_api.php';
  final query = <String, String>{
    ...base.queryParameters,
    'username': request.credentials.username,
    'password': request.credentials.password,
    if (request.action != null) 'action': request.action!,
    ...request.params,
  };

  return base.replace(path: path, queryParameters: query);
}
