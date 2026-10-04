// F2 + F6 + F7 + F8 against a fake webcast server: frames, ack, what goes on
// the wire, and the same session through tunnelling CONNECT / SOCKS5 proxies.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:piratetok_live/src/connection/url.dart';
import 'package:piratetok_live/src/connection/wss.dart';
import 'package:piratetok_live/src/events/types.dart';
import 'package:piratetok_live/src/proto/codec.dart';
import 'package:test/test.dart';

import 'fakes.dart';

// non-UTF-8 on purpose: internal_ext is opaque bytes and must be echoed verbatim
final _ext = Uint8List.fromList([0xff, 0x00, 0x80, 0x7a, 0xc3]);

typedef _Seen = ({HttpHeaders headers, Uri uri, List<ProtoMap> frames});

Future<_Seen> _session({String proxy = ''}) async {
  final seen = Completer<_Seen>();
  final server = await FakeWebcast.start((req, ws) async {
    final frames = <ProtoMap>[];
    final push = protoWrite((w) {
      w.writeVarintField(2, 4242);
      w.writeStringField(7, 'msg');
      w.writeBytesField(8, protoWrite((r) {
        r.writeMessageField(1, protoWrite((m) {
          m.writeStringField(1, 'WebcastChatMessage');
          m.writeBytesField(2, protoWrite((c) => c.writeStringField(3, 'hello from fake')));
        }));
        r.writeBytesField(5, _ext);
        r.writeBoolField(9, true);
      }));
    });
    await for (final data in ws) {
      final f = protoRead(Uint8List.fromList(data as List<int>));
      frames.add(f);
      if (f.getString(7) == 'im_enter_room') ws.add(push);
      if (f.getString(7) == 'ack') {
        seen.complete((headers: req.headers, uri: req.uri, frames: frames));
        await ws.close();
      }
    }
  });
  addTearDown(server.close);

  final url = buildWssUrl('HOST', '7',
          language: 'ro', region: 'RO', compress: false, heartbeatInterval: const Duration(seconds: 2))
      .replaceFirst('wss://HOST', 'ws://127.0.0.1:${server.port}');
  final events = <TikTokEvent>[];
  await connectWss(
    wssUrl: url,
    ttwid: 'abc',
    roomId: '7',
    onEvent: events.add,
    onError: (e) => fail('session error: $e'),
    stopSignal: Completer<void>(),
    heartbeatInterval: const Duration(seconds: 2),
    staleTimeout: const Duration(seconds: 5),
    proxy: proxy,
    userAgent: 'UA-test/1.0',
    cookies: 'sessionid=s1',
    language: 'ro',
    region: 'RO',
  ).timeout(const Duration(seconds: 10));

  final chats = events.where((e) => e.type == EventType.chat).toList();
  expect(chats, hasLength(1));
  expect(chats.single.data!['content'], 'hello from fake');
  return seen.future.timeout(const Duration(seconds: 1));
}

void main() {
  test('session against fake webcast: frames, ack and wire params', () async {
    final s = await _session();
    expect(s.frames.take(2).map((f) => f.getString(7)), ['hb', 'im_enter_room']);
    final ack = s.frames.last;
    expect(ack.getString(7), 'ack');
    expect(ack.getVarint(2), 4242);
    expect(ack.getBytes(8), _ext);

    expect(s.headers.value('user-agent'), 'UA-test/1.0');
    expect(s.headers.value('cookie'), 'ttwid=abc; sessionid=s1');
    expect(s.headers.value('accept-language'), 'ro-RO,ro;q=0.9');
    expect(s.headers.value('origin'), 'https://www.tiktok.com');
    final q = s.uri.queryParameters;
    expect(q['room_id'], '7');
    expect(q['webcast_language'], 'ro');
    expect(q['app_language'], 'ro');
    expect(q['browser_language'], 'ro-RO');
    expect(q['compress'], '');
    expect(q['heartbeat_duration'], '2000');
  });

  test('same session through a tunnelling CONNECT proxy with credentials', () async {
    final p = await FakeProxy.connect(tunnel: true);
    addTearDown(p.close);
    final s = await _session(proxy: 'http://user:pw@127.0.0.1:${p.port}');
    expect(s.frames.last.getString(7), 'ack');
    expect(p.hits, hasLength(1));
    expect(p.hits.single.target, startsWith('127.0.0.1:'));
    expect(p.hits.single.auth, 'Basic ${base64Encode(utf8.encode('user:pw'))}');
  });

  test('same session through a tunnelling SOCKS5 proxy with credentials', () async {
    final p = await FakeProxy.socks5(tunnel: true);
    addTearDown(p.close);
    final s = await _session(proxy: 'socks5://user:pw@127.0.0.1:${p.port}');
    expect(s.frames.last.getString(7), 'ack');
    expect(p.hits.single.auth, 'user:pw');
  });
}
