import 'dart:convert';
import 'dart:io';

import 'package:m3u_tv/services/json_isolate.dart';
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
    httpRequest
      ..contentLength = bytes.length
      ..add(bytes);
  }

  final response = await httpRequest.close();
  final text = await utf8.decodeStream(response);
  final isError = response.statusCode >= HttpStatus.badRequest;
  if (text.isEmpty) {
    if (isError) {
      throw XtreamHttpException(
        statusCode: response.statusCode,
        reasonPhrase: response.reasonPhrase,
        method: request.method,
        uri: uri,
      );
    }
    return null;
  }

  // Fast path: the caller decodes and maps the body itself on a background
  // isolate. Only for successful responses - an error body still needs
  // decoding here to extract the server message.
  if (request.wantsRawText && !isError) {
    return XtreamRawResponse(text);
  }

  final Object? body;
  try {
    body = await decodeJsonOffMainIsolate(text);
  } on FormatException {
    final serverMessage = _plainServerMessage(text);
    if (isError) {
      throw XtreamHttpException(
        statusCode: response.statusCode,
        reasonPhrase: response.reasonPhrase,
        method: request.method,
        uri: uri,
        serverMessage: serverMessage,
      );
    }
    throw XtreamResponseException(
      method: request.method,
      uri: uri,
      serverMessage: serverMessage,
    );
  }

  if (isError) {
    throw XtreamHttpException(
      statusCode: response.statusCode,
      reasonPhrase: response.reasonPhrase,
      method: request.method,
      uri: uri,
      serverMessage: _serverMessage(body),
      bodyJson: body,
    );
  }
  return body;
}

String? _plainServerMessage(String text) {
  final message = text.trim();
  if (message.isEmpty) return null;
  // HTML error pages (nginx, Apache, etc.) are not useful as-is; the HTTP
  // status line already conveys the error so we drop the body.
  if (message.startsWith('<!') ||
      message.startsWith('<html') ||
      message.startsWith('<HTML')) {
    return null;
  }
  return message.length <= 240 ? message : '${message.substring(0, 240)}...';
}

String? _serverMessage(Object? body) {
  if (body is! Map) return null;
  final json = body.cast<Object?, Object?>();
  final value =
      json['error'] ?? json['message'] ?? json['detail'] ?? json['error_code'];
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
