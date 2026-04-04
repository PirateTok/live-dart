import 'dart:io';

import '../http/ua.dart';

/// Fetch a fresh ttwid cookie via anonymous GET to tiktok.com.
Future<String> fetchTtwid({
  Duration timeout = const Duration(seconds: 10),
  String proxy = '',
  String? userAgent,
}) async {
  final ua = userAgent ?? randomUa();
  final client = HttpClient();
  try {
    if (proxy.isNotEmpty) {
      final proxyUri = Uri.parse(proxy);
      client.findProxy = (_) =>
          'PROXY ${proxyUri.host}:${proxyUri.port}';
    }
    client.connectionTimeout = timeout;
    client.userAgent = ua;

    final request = await client.getUrl(Uri.parse('https://www.tiktok.com/'));
    request.followRedirects = true;
    final response = await request.close().timeout(timeout);
    // Drain the response body
    await response.drain<void>();

    for (final cookie in response.cookies) {
      if (cookie.name == 'ttwid') return cookie.value;
    }

    throw StateError('ttwid: no ttwid cookie in response');
  } finally {
    client.close();
  }
}
