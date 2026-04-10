// Multi-stream concurrent load test — M1.
//
// Connects N clients simultaneously (one per username from the env var),
// collects chat events for 60s, then disconnects all and waits for clean
// shutdown.
//
// Gate: PIRATETOK_LIVE_TEST_USERS (comma-separated, all must be live).
//
// Client config per session:
//   CDN: EU
//   HTTP timeout: 15s
//   Max retries: 5
//   Stale timeout: 120s  (longer than smoke tests — load test runs 60+ seconds)

import 'dart:async';
import 'dart:io';

import 'package:piratetok_live/src/client.dart';
import 'package:piratetok_live/src/events/types.dart';
import 'package:test/test.dart';

const _allConnectedTimeout = Duration(seconds: 120);
const _liveWindow = Duration(seconds: 60);
const _sessionJoinTimeout = Duration(seconds: 120);

String? _loadGate() {
  final v = Platform.environment['PIRATETOK_LIVE_TEST_USERS'];
  if (v == null || v.trim().isEmpty) {
    return 'set PIRATETOK_LIVE_TEST_USERS to a comma-separated list of live TikTok usernames';
  }
  return null;
}

List<String> _parseUsers() {
  final raw = Platform.environment['PIRATETOK_LIVE_TEST_USERS'] ?? '';
  return raw
      .split(',')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
}

TikTokLiveClient _buildClient(String user) => TikTokLiveClient(user)
    .cdnEu()
    .timeout(const Duration(seconds: 15))
    .maxRetries(5)
    .staleTimeout(const Duration(seconds: 120));

void main() {
  test(
    'multipleLiveClients_trackChatForOneMinute',
    () async {
      final users = _parseUsers();
      expect(users, isNotEmpty, reason: 'PIRATETOK_LIVE_TEST_USERS was empty');

      final n = users.length;
      final allConnected = Completer<void>();
      int connectedCount = 0;

      final clients = <TikTokLiveClient>[];
      final chatCounts = <String, int>{};
      final sessionFutures = <Future<void>>[];
      final sessionErrors = <String, Object?>{};

      for (final user in users) {
        chatCounts[user] = 0;

        final client = _buildClient(user);
        clients.add(client);

        client.on(EventType.connected, (_) {
          connectedCount++;
          if (connectedCount == n && !allConnected.isCompleted) {
            allConnected.complete();
          }
        });

        client.on(EventType.chat, (_) {
          chatCounts[user] = (chatCounts[user] ?? 0) + 1;
        });

        final fut = client.connect().then((_) {}).catchError((Object e) {
          sessionErrors[user] = e;
        });
        sessionFutures.add(fut);
      }

      // 1. Wait for all clients to reach CONNECTED.
      bool allReached;
      try {
        await allConnected.future.timeout(_allConnectedTimeout);
        allReached = true;
      } on TimeoutException {
        allReached = false;
      }

      try {
        expect(
          allReached,
          isTrue,
          reason:
              'only $connectedCount/$n clients connected within '
              '${_allConnectedTimeout.inSeconds}s',
        );

        // 2. Live window — collect events for 60 seconds.
        await Future<void>.delayed(_liveWindow);

        // 3. Disconnect all clients.
        for (final client in clients) {
          client.disconnect();
        }

        // 4. Await all session futures.
        bool allJoined;
        try {
          await Future.wait(sessionFutures).timeout(_sessionJoinTimeout);
          allJoined = true;
        } on TimeoutException {
          allJoined = false;
        }

        // 5. Report per-channel chat counts.
        for (final user in users) {
          // ignore: avoid_print
          print('[integration load] $user: ${chatCounts[user]} chat events '
              'in ${_liveWindow.inSeconds}s');
        }

        // 6. Assertions.
        expect(sessionErrors, isEmpty,
            reason: 'some sessions threw errors: $sessionErrors');

        expect(
          allJoined,
          isTrue,
          reason:
              'not all session futures resolved within '
              '${_sessionJoinTimeout.inSeconds}s after disconnect',
        );
      } finally {
        // Safety net: disconnect any client that may still be running.
        for (final client in clients) {
          client.disconnect();
        }
      }
    },
    timeout: Timeout(
      _allConnectedTimeout +
          _liveWindow +
          _sessionJoinTimeout +
          const Duration(seconds: 60),
    ),
    skip: _loadGate(),
  );
}
