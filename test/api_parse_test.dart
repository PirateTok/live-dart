import 'package:piratetok_live/piratetok_live.dart';
import 'package:piratetok_live/src/http/api.dart' show parseCheckOnline;
import 'package:piratetok_live/src/http/audience.dart' show parseRoomAudience;
import 'package:test/test.dart';

const _audienceOk = '''
{"status_code": 0, "data": {"total": 1234, "anonymous": 56, "ranks": [
  {"rank": 1, "score": 900, "user": {
    "id": 111, "id_str": "7000000000000000111", "display_id": "viewer_one",
    "nickname": "Viewer One", "sec_uid": "MS4w-one",
    "avatar_thumb": {"url_list": ["https://p16.example/a.webp", "https://p19.example/a.webp"]},
    "follow_info": {"follower_count": 42},
    "verified": true, "is_follower": true, "is_following": false, "is_subscribe": true}},
  {"rank": 2, "score": 10},
  {"rank": 3, "score": 5, "user": {"id": 333, "display_id": "viewer_three", "nickname": "V3"}}
]}}''';

void main() {
  group('online_audience', () {
    test('parses roster skipping entries without user', () {
      final a = parseRoomAudience(_audienceOk, 200);
      expect(a.total, 1234);
      expect(a.anonymous, 56);
      expect(a.viewers, hasLength(2));
      expect(a.rawJson, _audienceOk);
      final one = a.viewers[0];
      expect([one.rank, one.score, one.userId, one.username, one.nickname, one.secUid],
          [1, 900, '7000000000000000111', 'viewer_one', 'Viewer One', 'MS4w-one']);
      expect(one.avatarUrl, 'https://p16.example/a.webp');
      expect(one.followerCount, 42);
      expect([one.verified, one.isFollower, one.isFollowing, one.isSubscriber],
          [true, true, false, true]);
      final three = a.viewers[1];
      expect(three.userId, '333');
      expect(three.avatarUrl, isNull);
      expect(three.followerCount, 0);
    });

    test('20003 is SessionRequired', () {
      expect(
          () => parseRoomAudience('{"status_code":20003,"data":{"message":"login"}}', 200),
          throwsA(isA<SessionRequiredError>()
              .having((e) => e.message, 'message', contains('session cookies'))));
    });

    test('other status is InvalidResponse with code and message', () {
      expect(
          () => parseRoomAudience('{"status_code":10011,"data":{"message":"room gone"}}', 200),
          throwsA(isA<InvalidResponseError>()
              .having((e) => e.message, 'message', contains('status_code=10011 room gone'))));
    });

    test('missing status or empty body is InvalidResponse', () {
      expect(() => parseRoomAudience('{"data":{}}', 200), throwsA(isA<InvalidResponseError>()));
      expect(() => parseRoomAudience('', 403),
          throwsA(isA<InvalidResponseError>().having((e) => e.message, 'message', contains('HTTP 403'))));
    });
  });

  group('check_online', () {
    test('exposes anchor id', () {
      final r = parseCheckOnline('someone',
          '{"statusCode":0,"data":{"user":{"id":"6900000000000000001","roomId":"7300000000000000001","status":2},"liveRoom":{"status":2}}}',
          200);
      expect(r.roomId, '7300000000000000001');
      expect(r.anchorId, '6900000000000000001');
    });

    test('error mapping', () {
      expect(() => parseCheckOnline('x', '{"statusCode":19881007}', 200),
          throwsA(isA<UserNotFoundError>()));
      expect(() => parseCheckOnline('x', '{"statusCode":4242}', 200),
          throwsA(isA<TikTokApiError>().having((e) => e.code, 'code', 4242)));
      expect(() => parseCheckOnline('x', '{"statusCode":0,"data":{"user":{"roomId":"0"}}}', 200),
          throwsA(isA<HostNotOnlineError>()));
      expect(() => parseCheckOnline('x', '{"statusCode":0,"data":{"user":{"roomId":"7","status":4}}}', 200),
          throwsA(isA<HostNotOnlineError>()));
      expect(() => parseCheckOnline('x', '<html>', 200),
          throwsA(isA<TikTokBlockedError>().having((e) => e.statusCode, 'statusCode', 200)));
      expect(() => parseCheckOnline('x', '', 200), throwsA(isA<TikTokBlockedError>()));
    });
  });
}
