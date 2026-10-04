// Fetches the full viewer roster of a live room, then exits.
//
// TikTok gates this endpoint behind a login, so session cookies are required:
//   dart run example/audience.dart <username> "sessionid=abc; sid_tt=abc"

import 'dart:io';

import 'package:piratetok_live/piratetok_live.dart';

void main(List<String> args) async {
  if (args.length < 2) {
    print('usage: dart run example/audience.dart <username> "sessionid=xxx; sid_tt=xxx"');
    exit(1);
  }
  final username = args[0];

  try {
    final room = await checkOnline(username);
    final audience = await fetchRoomAudience(
      room.roomId,
      anchorId: room.anchorId,
      cookies: args[1],
    );
    print('@$username — ${audience.total} in room (${audience.anonymous} anonymous), '
        '${audience.viewers.length} listed');
    for (final v in audience.viewers) {
      final tags = '${v.isSubscriber ? ' [sub]' : ''}${v.isFollower ? ' [follower]' : ''}';
      print('#${v.rank} @${v.username} (${v.nickname}) score=${v.score} '
          'followers=${v.followerCount}$tags');
    }
  } on SessionRequiredError catch (e) {
    print('$e\nhint: copy sessionid + sid_tt from browser DevTools while logged in');
    exit(1);
  } on PirateTokError catch (e) {
    print('error: $e');
    exit(1);
  }
}
