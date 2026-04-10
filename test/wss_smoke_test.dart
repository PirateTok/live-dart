// WSS smoke tests — W1-W7, D1.
//
// Connects to a real live room over WSS and waits for specific event types.
// Inherently flaky: quiet streams may not produce all event types within the
// timeout window. That is acceptable — the tests prove the pipeline works
// end-to-end; intermittent timeouts on quiet streams are not failures.
//
// Gate: PIRATETOK_LIVE_TEST_USER (username that is live during the run).
//
// Client config for all tests:
//   CDN: EU
//   HTTP timeout: 15s
//   Max retries: 5
//   Stale timeout: 45s

import 'dart:async';
import 'dart:io';

import 'package:piratetok_live/src/client.dart';
import 'package:piratetok_live/src/events/types.dart';
import 'package:test/test.dart';

const _awaitTraffic = Duration(seconds: 90);
const _awaitChat = Duration(seconds: 120);
const _awaitGift = Duration(seconds: 180);
const _awaitLike = Duration(seconds: 120);
const _awaitJoin = Duration(seconds: 150);
const _awaitFollow = Duration(seconds: 180);
const _awaitSubscription = Duration(seconds: 240);

// D1: connect phase wait; disconnect join budget
const _awaitConnected = Duration(seconds: 90);
const _disconnectJoin = Duration(seconds: 20);

String? _userGate() {
  final v = Platform.environment['PIRATETOK_LIVE_TEST_USER'];
  if (v == null || v.isEmpty) {
    return 'set PIRATETOK_LIVE_TEST_USER to a live TikTok username';
  }
  return null;
}

TikTokLiveClient _buildClient(String user) => TikTokLiveClient(user)
    .cdnEu()
    .timeout(const Duration(seconds: 15))
    .maxRetries(5)
    .staleTimeout(const Duration(seconds: 45));

/// Core smoke-test helper. Creates a fresh client, registers listeners via
/// [setup], connects on a Future, and waits up to [await_] for [completer]
/// to complete. Disconnects and awaits client shutdown either way.
Future<void> _awaitWssEvent(
  String user, {
  required Duration await_,
  required void Function(TikTokLiveClient client, Completer<void> hit) setup,
  required String failMessage,
}) async {
  final hit = Completer<void>();
  Throwable? workerError;

  final client = _buildClient(user);
  setup(client, hit);

  final sessionFuture = client.connect().then((_) {}).catchError((Object e) {
    workerError = e;
  });

  try {
    bool got;
    try {
      await hit.future.timeout(await_);
      got = true;
    } on TimeoutException {
      got = false;
    }

    expect(workerError, isNull,
        reason: 'connect future failed: $workerError');
    expect(got, isTrue, reason: failMessage);
  } finally {
    client.disconnect();
    await sessionFuture.timeout(
      const Duration(seconds: 30),
      onTimeout: () {},
    );
  }
}

void main() {
  // W1 — any traffic within 90s
  test(
    'connect_receivesTrafficBeforeTimeout',
    () async {
      final user = Platform.environment['PIRATETOK_LIVE_TEST_USER']!.trim();
      await _awaitWssEvent(
        user,
        await_: _awaitTraffic,
        setup: (client, hit) {
          void trip(TikTokEvent _) {
            if (!hit.isCompleted) hit.complete();
          }

          client.on(EventType.roomUserSeq, trip);
          client.on(EventType.member, trip);
          client.on(EventType.chat, trip);
          client.on(EventType.like, trip);
          client.on(EventType.control, trip);
        },
        failMessage:
            'no room traffic within ${_awaitTraffic.inSeconds}s '
            '(quiet stream or block)',
      );
    },
    timeout: Timeout(_awaitTraffic + const Duration(seconds: 60)),
    skip: _userGate(),
  );

  // W2 — chat event within 120s
  test(
    'connect_receivesChatBeforeTimeout',
    () async {
      final user = Platform.environment['PIRATETOK_LIVE_TEST_USER']!.trim();
      await _awaitWssEvent(
        user,
        await_: _awaitChat,
        setup: (client, hit) {
          client.on(EventType.chat, (e) {
            if (hit.isCompleted) return;
            final data = e.data ?? {};
            final userMap = data['user'] as Map<String, dynamic>? ?? {};
            // ignore: avoid_print
            print('[integration test chat] '
                '${userMap['uniqueId'] ?? '?'}: ${data['content']}');
            hit.complete();
          });
        },
        failMessage:
            'no chat message within ${_awaitChat.inSeconds}s '
            '(quiet stream or block)',
      );
    },
    timeout: Timeout(_awaitChat + const Duration(seconds: 60)),
    skip: _userGate(),
  );

  // W3 — gift event within 180s
  test(
    'connect_receivesGiftBeforeTimeout',
    () async {
      final user = Platform.environment['PIRATETOK_LIVE_TEST_USER']!.trim();
      await _awaitWssEvent(
        user,
        await_: _awaitGift,
        setup: (client, hit) {
          client.on(EventType.gift, (e) {
            if (hit.isCompleted) return;
            final data = e.data ?? {};
            final gifter = data['user'] as Map<String, dynamic>? ?? {};
            final gift = data['gift'] as Map<String, dynamic>? ?? {};
            final diamonds = (gift['diamondCount'] as int?) ?? 0;
            final repeat = (data['repeatCount'] as int?) ?? 1;
            // ignore: avoid_print
            print('[integration test gift] '
                '${gifter['uniqueId'] ?? '?'} -> '
                '${gift['name'] ?? '?'} x$repeat ($diamonds diamonds each)');
            hit.complete();
          });
        },
        failMessage:
            'no gift within ${_awaitGift.inSeconds}s '
            '(quiet stream or no gifts — try a busier stream)',
      );
    },
    timeout: Timeout(_awaitGift + const Duration(seconds: 60)),
    skip: _userGate(),
  );

  // W4 — like event within 120s
  test(
    'connect_receivesLikeBeforeTimeout',
    () async {
      final user = Platform.environment['PIRATETOK_LIVE_TEST_USER']!.trim();
      await _awaitWssEvent(
        user,
        await_: _awaitLike,
        setup: (client, hit) {
          client.on(EventType.like, (e) {
            if (hit.isCompleted) return;
            final data = e.data ?? {};
            final liker = data['user'] as Map<String, dynamic>? ?? {};
            // ignore: avoid_print
            print('[integration test like] '
                '${liker['uniqueId'] ?? '?'} '
                'count=${data['count']} total=${data['total']}');
            hit.complete();
          });
        },
        failMessage:
            'no like within ${_awaitLike.inSeconds}s '
            '(quiet stream or block)',
      );
    },
    timeout: Timeout(_awaitLike + const Duration(seconds: 60)),
    skip: _userGate(),
  );

  // W5 — join sub-routed event within 150s
  test(
    'connect_receivesJoinBeforeTimeout',
    () async {
      final user = Platform.environment['PIRATETOK_LIVE_TEST_USER']!.trim();
      await _awaitWssEvent(
        user,
        await_: _awaitJoin,
        setup: (client, hit) {
          client.on(EventType.join, (e) {
            if (hit.isCompleted) return;
            final data = e.data ?? {};
            final member = data['user'] as Map<String, dynamic>? ?? {};
            // ignore: avoid_print
            print('[integration test join] ${member['uniqueId'] ?? '?'}');
            hit.complete();
          });
        },
        failMessage:
            'no join within ${_awaitJoin.inSeconds}s '
            '(try a busier stream)',
      );
    },
    timeout: Timeout(_awaitJoin + const Duration(seconds: 60)),
    skip: _userGate(),
  );

  // W6 — follow sub-routed event within 180s
  test(
    'connect_receivesFollowBeforeTimeout',
    () async {
      final user = Platform.environment['PIRATETOK_LIVE_TEST_USER']!.trim();
      await _awaitWssEvent(
        user,
        await_: _awaitFollow,
        setup: (client, hit) {
          client.on(EventType.follow, (e) {
            if (hit.isCompleted) return;
            final data = e.data ?? {};
            final follower = data['user'] as Map<String, dynamic>? ?? {};
            // ignore: avoid_print
            print('[integration test follow] ${follower['uniqueId'] ?? '?'}');
            hit.complete();
          });
        },
        failMessage:
            'no follow within ${_awaitFollow.inSeconds}s '
            '(follows are infrequent — try a growing stream)',
      );
    },
    timeout: Timeout(_awaitFollow + const Duration(seconds: 60)),
    skip: _userGate(),
  );

  // W7 — subscription-related event within 240s (disabled by default — too rare)
  test(
    'connect_receivesSubscriptionSignalBeforeTimeout',
    () async {
      final user = Platform.environment['PIRATETOK_LIVE_TEST_USER']!.trim();
      await _awaitWssEvent(
        user,
        await_: _awaitSubscription,
        setup: (client, hit) {
          void trip(TikTokEvent e) {
            if (!hit.isCompleted) {
              // ignore: avoid_print
              print('[integration test subscription] ${e.type}');
              hit.complete();
            }
          }

          client.on(EventType.subNotify, trip);
          client.on(EventType.subscriptionNotify, trip);
          client.on(EventType.subCapsule, trip);
          client.on(EventType.subPinEvent, trip);
        },
        failMessage:
            'no subscription-related event within ${_awaitSubscription.inSeconds}s '
            '(need subs/gifts on a sub-enabled stream)',
      );
    },
    timeout: Timeout(_awaitSubscription + const Duration(seconds: 60)),
    // Disabled by default — subscription events are too rare on most streams.
    skip: 'W7 disabled by default: '
        'subscription events are too rare — enable manually on a known sub stream',
  );

  // D1 — disconnect() unblocks the connect Future within 18s
  test(
    'disconnect_unblocksConnectFutureAfterConnected',
    () async {
      final user = Platform.environment['PIRATETOK_LIVE_TEST_USER']!.trim();
      final connected = Completer<void>();
      Object? workerError;

      final client = _buildClient(user);
      client.on(EventType.connected, (_) {
        if (!connected.isCompleted) connected.complete();
      });

      final sessionFuture = client.connect().then((_) {}).catchError((Object e) {
        workerError = e;
      });

      try {
        // Wait for CONNECTED or timeout.
        try {
          await connected.future.timeout(_awaitConnected);
        } on TimeoutException {
          fail('never reached connected state within '
              '${_awaitConnected.inSeconds}s '
              '(offline user or network)');
        }

        expect(workerError, isNull,
            reason: 'connect future failed before disconnect: $workerError');

        final t0 = DateTime.now();
        client.disconnect();

        // Session future must resolve within the join budget.
        bool joined;
        try {
          await sessionFuture.timeout(_disconnectJoin);
          joined = true;
        } on TimeoutException {
          joined = false;
        }

        expect(joined, isTrue,
            reason: 'connect future should resolve after disconnect()');
        final elapsed = DateTime.now().difference(t0);
        expect(elapsed.inMilliseconds, lessThan(18000),
            reason: 'worker join should finish quickly after disconnect()');
      } finally {
        client.disconnect();
        await sessionFuture.timeout(
          const Duration(seconds: 5),
          onTimeout: () {},
        );
      }
    },
    timeout: Timeout(_awaitConnected + _disconnectJoin + const Duration(seconds: 30)),
    skip: _userGate(),
  );
}

// ignore: avoid_shadowing_type_parameters
typedef Throwable = Object;
