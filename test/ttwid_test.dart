// Offline: a local responder omits the ttwid cookie N times, then sets it.

import 'dart:io';

import 'package:piratetok_live/src/auth/ttwid.dart';
import 'package:test/test.dart';

void main() {
  late HttpServer server;
  late int hits;

  Future<Uri> serve(int missesBeforeCookie) async {
    hits = 0;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) {
      hits++;
      req.response.headers.add('Set-Cookie', 'tt_csrf_token=abc; Path=/');
      if (hits > missesBeforeCookie) {
        req.response.headers.add('Set-Cookie', 'ttwid=1%7Cfresh; Path=/; HttpOnly');
      }
      req.response.close();
    });
    return Uri.parse('http://127.0.0.1:${server.port}/');
  }

  Future<String> fetch(Uri url, {Duration delay = Duration.zero}) async {
    final client = HttpClient();
    try {
      return await fetchTtwidFrom(client, url,
          userAgent: 'test-ua',
          timeout: const Duration(seconds: 5),
          attempts: ttwidFetchAttempts,
          retryDelay: delay);
    } finally {
      client.close(force: true);
    }
  }

  tearDown(() => server.close(force: true));

  test('missing cookie then cookie succeeds', () async {
    expect(await fetch(await serve(5)), '1%7Cfresh');
    expect(hits, 6);
  });

  test('first response with cookie does not retry', () async {
    expect(await fetch(await serve(0)), '1%7Cfresh');
    expect(hits, 1);
  });

  test('never a cookie fails after 8 attempts', () async {
    final url = await serve(1 << 30);
    await expectLater(
        fetch(url),
        throwsA(isA<StateError>()
            .having((e) => e.message, 'message', contains('after 8 attempts'))));
    expect(hits, 8);
  });

  test('transport error propagates without retry', () async {
    final url = await serve(0);
    await server.close(force: true);
    final sw = Stopwatch()..start();
    await expectLater(fetch(url, delay: const Duration(seconds: 1)),
        throwsA(isA<SocketException>()));
    expect(sw.elapsed, lessThan(const Duration(seconds: 1)));
  });

  test('defaults match reference', () {
    expect(ttwidFetchAttempts, 8);
    expect(ttwidRetryDelay, const Duration(milliseconds: 750));
  });
}
