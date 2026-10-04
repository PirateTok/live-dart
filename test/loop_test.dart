// F4 + F5 at client level: the reconnect loop against fake ttwid / session / clock.

import 'dart:async';

import 'package:piratetok_live/src/events/types.dart';
import 'package:piratetok_live/src/reconnect.dart';
import 'package:test/test.dart';

class _Fakes {
  var freshCalls = 0;
  var runCalls = 0;
  final int freshFails;
  final SessionExit exit;
  final delays = <Duration>[];
  final events = <TikTokEvent>[];
  final stop = Completer<void>();

  _Fakes({this.freshFails = 0, this.exit = SessionExit.errored});

  Future<void> run(int maxRetries) => runReconnectLoop(
        roomId: '7',
        maxRetries: maxRetries,
        fresh: () async => ++freshCalls <= freshFails ? null : (ttwid: 't', ua: 'u'),
        run: (_) async {
          runCalls++;
          return exit;
        },
        delay: (d) async => delays.add(d),
        emit: events.add,
        stop: stop,
      );

  List<String> get types => events.map((e) => e.type).toList();
}

void main() {
  test('reconnecting per retry, then disconnected exactly once', () async {
    final f = _Fakes(freshFails: 2);
    await f.run(3);
    expect(f.types, [EventType.reconnecting, EventType.reconnecting, EventType.reconnecting, EventType.disconnected]);
    expect(f.events.take(3).map((e) => e.data!['attempt']), [1, 2, 3]);
    // 2 ttwid failures + 2 young-error sessions, each rotating → fresh every attempt
    expect((f.freshCalls, f.runCalls), (4, 2));
    expect(f.delays, const [Duration(seconds: 2), Duration(seconds: 4), Duration(seconds: 8)]);
  });

  test('clean close reuses ttwid + UA', () async {
    final f = _Fakes(exit: SessionExit.closed);
    await f.run(4);
    expect((f.freshCalls, f.runCalls), (1, 5));
    expect(f.types.where((t) => t == EventType.disconnected), hasLength(1));
  });

  test('device blocked rotates with the short delay', () async {
    final f = _Fakes(exit: SessionExit.deviceBlocked);
    await f.run(2);
    expect(f.freshCalls, 3);
    expect(f.delays.first, deviceBlockedDelay);
  });

  test('user stop disconnects once', () async {
    final stop = Completer<void>();
    final events = <TikTokEvent>[];
    await runReconnectLoop(
      roomId: '7',
      maxRetries: 5,
      fresh: () async => (ttwid: 't', ua: 'u'),
      run: (_) async {
        stop.complete();
        return SessionExit.closed;
      },
      delay: (d) => Future<void>.delayed(d),
      emit: events.add,
      stop: stop,
    );
    expect(events.map((e) => e.type), [EventType.disconnected]);
  });
}
