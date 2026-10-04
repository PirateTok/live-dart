import 'dart:convert';
import 'dart:io';

import '../errors.dart';
import 'api.dart';
import '../connection/proxy.dart';
import 'ua.dart';

const _statusSessionRequired = 20003;

/// The full viewer roster of a live room.
class RoomAudience {
  final int total;
  final int anonymous;
  final List<AudienceViewer> viewers;
  final String rawJson;

  const RoomAudience({
    required this.total,
    required this.anonymous,
    required this.viewers,
    required this.rawJson,
  });
}

/// One named viewer in the roster.
class AudienceViewer {
  final int rank;
  final int score;
  final String userId;
  final String username;
  final String nickname;
  final String secUid;
  final String? avatarUrl;
  final int followerCount;
  final bool verified;

  /// Follows the streamer.
  final bool isFollower;

  /// The streamer follows them.
  final bool isFollowing;
  final bool isSubscriber;

  const AudienceViewer({
    required this.rank,
    required this.score,
    required this.userId,
    required this.username,
    required this.nickname,
    required this.secUid,
    required this.avatarUrl,
    required this.followerCount,
    required this.verified,
    required this.isFollower,
    required this.isFollowing,
    required this.isSubscriber,
  });
}

/// Fetch the full audience roster: every named viewer currently in the room —
/// the whole viewer panel, not just the top-3 box (for that, see
/// [topViewers] on a `roomUserSeq` event, which needs no cookies).
///
/// TikTok gates this endpoint behind a login: pass session [cookies]
/// (`sessionid=xxx; sid_tt=xxx`) or you get [SessionRequiredError]. No ttwid,
/// msToken, or signing needed.
///
/// [anchorId] is the streamer's user ID ([RoomIdResult.anchorId]). Pass null
/// to resolve it from room info (one extra request).
Future<RoomAudience> fetchRoomAudience(
  String roomId, {
  String? anchorId,
  Duration timeout = const Duration(seconds: 10),
  String cookies = '',
  String proxy = '',
  String? userAgent,
  String? language,
  String? region,
}) async {
  final anchor = anchorId != null && anchorId.isNotEmpty
      ? anchorId
      : _ownerId(await fetchRoomInfo(
          roomId,
          timeout: timeout,
          cookies: cookies,
          proxy: proxy,
          userAgent: userAgent,
          language: language,
          region: region,
        ));
  final lang = language ?? systemLanguage();
  final reg = region ?? systemRegion();
  final uri = Uri.https('webcast.tiktok.com', '/webcast/ranklist/online_audience/', {
    'aid': '1988',
    'app_name': 'tiktok_web',
    'device_platform': 'web_pc',
    'app_language': lang,
    'browser_language': '$lang-$reg',
    'channel': 'tiktok_web',
    'room_id': roomId,
    'anchor_id': anchor,
  });

  final client = HttpClient();
  try {
    if (proxy.isNotEmpty) applyProxy(client, proxy);
    client.connectionTimeout = timeout;
    final request = await client.getUrl(uri);
    request.headers.set('User-Agent', userAgent ?? randomUa());
    request.headers.set('Referer', 'https://www.tiktok.com/');
    if (cookies.isNotEmpty) request.headers.set('Cookie', cookies);
    final response = await request.close().timeout(timeout);
    final body = await response.transform(utf8.decoder).join();
    return parseRoomAudience(body, response.statusCode);
  } finally {
    client.close();
  }
}

String _ownerId(RoomInfo info) {
  final root = json.decode(info.rawJson);
  final data = root is Map<String, dynamic> ? root['data'] : null;
  final owner = data is Map<String, dynamic> ? data['owner'] : null;
  final id = owner is Map<String, dynamic> ? '${owner['id_str'] ?? ''}' : '';
  if (id.isEmpty) throw InvalidResponseError('no owner id in room info');
  return id;
}

RoomAudience parseRoomAudience(String body, int httpStatus) {
  if (body.isEmpty) {
    throw InvalidResponseError(
        'empty response from online_audience (HTTP $httpStatus)');
  }
  final root = json.decode(body);
  if (root is! Map<String, dynamic> || root['status_code'] is! int) {
    throw InvalidResponseError('no status_code in online_audience response');
  }
  final code = root['status_code'] as int;
  final data = root['data'];
  if (code == _statusSessionRequired) {
    throw SessionRequiredError(
        'audience roster needs login — pass session cookies to fetchRoomAudience()');
  }
  if (code != 0) {
    final msg = data is Map<String, dynamic> ? '${data['message'] ?? ''}' : '';
    throw InvalidResponseError('online_audience status_code=$code $msg');
  }
  if (data is! Map<String, dynamic>) {
    throw InvalidResponseError("missing 'data' in online_audience");
  }

  final ranks = data['ranks'];
  final viewers = <AudienceViewer>[
    if (ranks is List)
      for (final rank in ranks)
        if (rank is Map<String, dynamic> && rank['user'] is Map<String, dynamic>)
          _viewer(rank, rank['user'] as Map<String, dynamic>),
  ];
  return RoomAudience(
    total: _int(data['total']),
    anonymous: _int(data['anonymous']),
    viewers: viewers,
    rawJson: body,
  );
}

AudienceViewer _viewer(Map<String, dynamic> rank, Map<String, dynamic> user) {
  final idStr = '${user['id_str'] ?? ''}';
  final avatar = user['avatar_thumb'];
  final urls = avatar is Map<String, dynamic> ? avatar['url_list'] : null;
  final follow = user['follow_info'];
  return AudienceViewer(
    rank: _int(rank['rank']),
    score: _int(rank['score']),
    userId: idStr.isNotEmpty ? idStr : '${user['id'] ?? ''}',
    username: '${user['display_id'] ?? ''}',
    nickname: '${user['nickname'] ?? ''}',
    secUid: '${user['sec_uid'] ?? ''}',
    avatarUrl: urls is List && urls.isNotEmpty && urls.first is String
        ? urls.first as String
        : null,
    followerCount:
        follow is Map<String, dynamic> ? _int(follow['follower_count']) : 0,
    verified: user['verified'] == true,
    isFollower: user['is_follower'] == true,
    isFollowing: user['is_following'] == true,
    isSubscriber: user['is_subscribe'] == true,
  );
}

int _int(Object? v) => v is int ? v : 0;
