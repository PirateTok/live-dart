import 'dart:typed_data';

import 'package:piratetok_live/piratetok_live.dart';
import 'package:piratetok_live/src/connection/url.dart';
import 'package:piratetok_live/src/events/router.dart' as router;
import 'package:piratetok_live/src/proto/codec.dart';
import 'package:test/test.dart';

Uint8List _contributor(int rank, int score, int userId, String nick) {
  final user = protoWrite((w) {
    w.writeVarintField(1, userId);
    w.writeStringField(3, nick);
  });
  return protoWrite((w) {
    w.writeVarintField(1, score);
    w.writeMessageField(2, user);
    w.writeVarintField(3, rank);
  });
}

void main() {
  test('decodes ranksList and sorts top viewers by rank', () {
    final payload = protoWrite((w) {
      w.writeMessageField(2, _contributor(3, 10, 300, 'third'));
      w.writeMessageField(2, protoWrite((c) => c.writeVarintField(1, 999)));
      w.writeMessageField(2, _contributor(1, 5000, 100, 'first'));
      w.writeMessageField(2, _contributor(2, 1200, 200, 'second'));
      w.writeVarintField(3, 321);
      w.writeVarintField(7, 4567);
      w.writeVarintField(8, 12);
    });

    final events = router.decode('WebcastRoomUserSeqMessage', payload, '1');
    expect(events, hasLength(1));
    expect(events.first.type, EventType.roomUserSeq);
    final data = events.first.data!;
    expect((data['ranksList'] as List), hasLength(4));
    expect(data['viewerCount'], 321);
    expect(data['totalUser'], 4567);
    expect(data['anonymous'], 12);

    final top = topViewers(data);
    expect(top.map((c) => c['rank']), [1, 2, 3]);
    expect(top.map((c) => (c['user'] as Map)['nickname']), ['first', 'second', 'third']);
    expect(top.first['score'], 5000);
  });

  test('top viewers empty without ranks', () {
    expect(topViewers({}), isEmpty);
  });

  test('unknown keeps method and raw payload', () {
    final raw = Uint8List.fromList([1, 2, 3]);
    final evt = router.decode('WebcastKaraokeMessage', raw, '1').single;
    expect(evt.type, EventType.unknown);
    expect(evt.data!['method'], 'WebcastKaraokeMessage');
    expect(evt.data!['payload'], raw);
  });

  test('heartbeat_duration follows the interval', () {
    final url = buildWssUrl('h', '1',
        language: 'en', region: 'US', heartbeatInterval: const Duration(seconds: 7));
    expect(Uri.parse(url).queryParameters['heartbeat_duration'], '7000');
    expect(Uri.parse(buildWssUrl('h', '1', language: 'en', region: 'US'))
        .queryParameters['heartbeat_duration'], '10000');
  });
}
