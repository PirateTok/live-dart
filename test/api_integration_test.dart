// HTTP API integration tests — H1-H4.
//
// Hits real TikTok endpoints. All tests skip when env vars are not set so
// `dart test` stays green in CI without network access.
//
// Gating env vars:
//   PIRATETOK_LIVE_TEST_USER         — TikTok username that is live during the run
//   PIRATETOK_LIVE_TEST_OFFLINE_USER — username that must NOT be live
//   PIRATETOK_LIVE_TEST_COOKIES      — browser cookie header for 18+ room info
//   PIRATETOK_LIVE_TEST_HTTP=1       — enables the nonexistent-user probe (safe to run anytime)

import 'dart:io';

import 'package:piratetok_live/src/errors.dart';
import 'package:piratetok_live/src/http/api.dart';
import 'package:test/test.dart';

/// Unlikely to be registered. TikTok must return user-not-found for this probe.
const _syntheticNonexistent =
    'piratetok_dart_nf_7a3c9e2f1b8d4a6c0e5f3a2b1d9c8e7';

const _timeout = Duration(seconds: 25);

void main() {
  // H1 — live user returns a valid room ID
  test(
    'checkOnline_liveUser_returnsRoomId',
    () async {
      final user = Platform.environment['PIRATETOK_LIVE_TEST_USER']!.trim();
      final result = await checkOnline(user, timeout: _timeout);
      expect(result.roomId, isNotEmpty);
      expect(result.roomId, isNot('0'));
    },
    skip: Platform.environment['PIRATETOK_LIVE_TEST_USER'] == null
        ? 'set PIRATETOK_LIVE_TEST_USER to a live TikTok username'
        : null,
  );

  // H2 — offline user throws HostNotOnlineError (not blocked, not not-found)
  test(
    'checkOnline_offlineUser_throwsHostNotOnline',
    () async {
      final user =
          Platform.environment['PIRATETOK_LIVE_TEST_OFFLINE_USER']!.trim();
      try {
        await checkOnline(user, timeout: _timeout);
        fail('expected HostNotOnlineError, got success');
      } on HostNotOnlineError catch (e) {
        // Correct error type. Verify message quality.
        expect(
          e.message.toLowerCase(),
          anyOf(
            contains('not online'),
            contains('offline'),
            contains('not currently live'),
          ),
          reason: 'error message must say "not online" or "offline"',
        );
      }
    },
    skip: Platform.environment['PIRATETOK_LIVE_TEST_OFFLINE_USER'] == null
        ? 'set PIRATETOK_LIVE_TEST_OFFLINE_USER to a known-offline TikTok username'
        : null,
  );

  // H3 — nonexistent user throws UserNotFoundError
  test(
    'checkOnline_nonexistentUser_throwsUserNotFound',
    () async {
      try {
        await checkOnline(_syntheticNonexistent, timeout: _timeout);
        fail('expected UserNotFoundError, got success');
      } on UserNotFoundError catch (e) {
        expect(e.username, equals(_syntheticNonexistent));
        expect(
          e.message.toLowerCase(),
          anyOf(
            contains('not found'),
            contains('does not exist'),
          ),
          reason: 'error message must say "not found" or "does not exist"',
        );
      }
    },
    skip: _httpGate(),
  );

  // H4 — live room returns room info with non-negative viewer count
  test(
    'fetchRoomInfo_liveRoom_returnsRoomInfo',
    () async {
      final user = Platform.environment['PIRATETOK_LIVE_TEST_USER']!.trim();
      final cookies =
          Platform.environment['PIRATETOK_LIVE_TEST_COOKIES'] ?? '';

      final room = await checkOnline(user, timeout: _timeout);
      final info = await fetchRoomInfo(
        room.roomId,
        timeout: _timeout,
        cookies: cookies,
      );

      expect(info.viewers, greaterThanOrEqualTo(0));
    },
    skip: Platform.environment['PIRATETOK_LIVE_TEST_USER'] == null
        ? 'set PIRATETOK_LIVE_TEST_USER to a live TikTok username'
        : null,
  );
}

String? _httpGate() {
  final v = Platform.environment['PIRATETOK_LIVE_TEST_HTTP'];
  if (v == null || v.isEmpty) {
    return 'set PIRATETOK_LIVE_TEST_HTTP=1 to call TikTok user/room for not-found probe';
  }
  if (v == '1' || v == 'true' || v == 'yes') return null;
  return 'set PIRATETOK_LIVE_TEST_HTTP=1 to enable not-found probe';
}
