import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// A random PKCE code verifier, for the device login flows of public clients.
String generatePkceVerifier() {
  final random = Random.secure();
  final bytes = List<int>.generate(32, (_) => random.nextInt(256));
  return base64UrlEncode(bytes).replaceAll('=', '');
}

/// The S256 code challenge for [verifier].
String pkceChallenge(String verifier) => base64UrlEncode(
  sha256.convert(ascii.encode(verifier)).bytes,
).replaceAll('=', '');
