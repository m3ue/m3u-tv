import 'package:m3u_tv/services/json_isolate.dart';
import 'package:m3u_tv/services/xtream_service.dart';

// Shared by the dart:io and browser Xtream transports: everything after the
// HTTP exchange itself.

/// Maps an Xtream API response to the decoded body (or a raw-text wrapper),
/// throwing the XtreamService exceptions for error statuses and bodies.
Future<Object?> handleXtreamResponse({
  required XtreamRequest request,
  required Uri uri,
  required int statusCode,
  required String? reasonPhrase,
  required String text,
}) async {
  final isError = statusCode >= 400;
  if (text.isEmpty) {
    if (isError) {
      throw XtreamHttpException(
        statusCode: statusCode,
        reasonPhrase: reasonPhrase,
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
        statusCode: statusCode,
        reasonPhrase: reasonPhrase,
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
      statusCode: statusCode,
      reasonPhrase: reasonPhrase,
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

Uri buildXtreamUri(XtreamRequest request) {
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
