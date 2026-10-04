import 'dart:io';

import '../connection/proxy.dart';
import '../http/ua.dart';

/// TikTok only sets ttwid on ~1 in 5-8 anonymous GETs — retry when it's absent.
const ttwidFetchAttempts = 8;
const ttwidRetryDelay = Duration(milliseconds: 750);

final _tiktokUrl = Uri.parse('https://www.tiktok.com/');

/// Fetch a fresh ttwid cookie via anonymous GET to tiktok.com, retrying up to
/// [ttwidFetchAttempts] times when the response carries no cookie. Transport
/// errors propagate immediately.
Future<String> fetchTtwid({
  Duration timeout = const Duration(seconds: 10),
  String proxy = '',
  String? userAgent,
}) async {
  final client = HttpClient();
  try {
    if (proxy.isNotEmpty) applyProxy(client, proxy);
    client.connectionTimeout = timeout;
    return await fetchTtwidFrom(
      client,
      _tiktokUrl,
      userAgent: userAgent ?? randomUa(),
      timeout: timeout,
      attempts: ttwidFetchAttempts,
      retryDelay: ttwidRetryDelay,
    );
  } finally {
    client.close();
  }
}

/// Retry core of [fetchTtwid], against any [url] (offline tests use a local server).
Future<String> fetchTtwidFrom(
  HttpClient client,
  Uri url, {
  required String userAgent,
  required Duration timeout,
  required int attempts,
  required Duration retryDelay,
}) async {
  client.userAgent = userAgent;
  for (var attempt = 1;; attempt++) {
    final request = await client.getUrl(url);
    request.followRedirects = true;
    final response = await request.close().timeout(timeout);
    await response.drain<void>();

    for (final cookie in response.cookies) {
      if (cookie.name == 'ttwid' && cookie.value.isNotEmpty) return cookie.value;
    }
    if (attempt >= attempts) {
      throw StateError(
        'ttwid: no ttwid cookie after $attempt attempts (last HTTP ${response.statusCode})',
      );
    }
    await Future<void>.delayed(retryDelay);
  }
}
