// F6: ttwid, API and WSS all go through the configured proxy (HTTP CONNECT
// and SOCKS5), credentials included. The fakes refuse every tunnel.

import 'dart:async';
import 'dart:convert';

import 'package:piratetok_live/src/auth/ttwid.dart';
import 'package:piratetok_live/src/connection/wss.dart';
import 'package:piratetok_live/src/http/api.dart';
import 'package:test/test.dart';

import 'fakes.dart';

const _timeout = Duration(seconds: 3);
final _basic = 'Basic ${base64Encode(utf8.encode('user:pw'))}';

Future<void> _refused(Future<Object?> Function() call) async {
  await expectLater(call(), throwsA(anything));
}

Future<void> _wss(String proxy) => connectWss(
      wssUrl: 'wss://webcast-ws.tiktok.com/webcast/im/ws_proxy/ws_reuse_supplement/?room_id=7',
      ttwid: 'abc',
      roomId: '7',
      onEvent: (_) {},
      onError: (_) {},
      stopSignal: Completer<void>(),
      proxy: proxy,
      userAgent: 'ua',
      language: 'en',
      region: 'US',
    );

void main() {
  for (final (name, make, scheme, auth) in [
    ('CONNECT', FakeProxy.connect, 'http', _basic),
    ('SOCKS5', FakeProxy.socks5, 'socks5', 'user:pw'),
  ]) {
    group(name, () {
      late FakeProxy p;
      late String url;
      setUp(() async {
        p = await make();
        url = '$scheme://user:pw@127.0.0.1:${p.port}';
      });
      tearDown(() => p.close());

      test('ttwid goes through the proxy', () async {
        await _refused(() => fetchTtwid(timeout: _timeout, proxy: url, userAgent: 'ua'));
        expect(p.hits, [(target: 'www.tiktok.com:443', auth: auth)]);
      });

      test('API goes through the proxy', () async {
        await _refused(() => checkOnline('someone', timeout: _timeout, proxy: url, language: 'en', region: 'US'));
        await _refused(() => fetchRoomInfo('7', timeout: _timeout, proxy: url, language: 'en', region: 'US'));
        expect(p.hits, [
          (target: 'www.tiktok.com:443', auth: auth),
          (target: 'webcast.tiktok.com:443', auth: auth),
        ]);
      });

      test('WSS goes through the proxy', () async {
        await _refused(() => _wss(url));
        expect(p.hits, [(target: 'webcast-ws.tiktok.com:443', auth: auth)]);
      });
    });
  }

  test('unsupported proxy scheme fails loudly', () async {
    await expectLater(_wss('ftp://127.0.0.1:1'), throwsA(isA<ArgumentError>()));
  });
}
