// Profile lookup example — fetch HD avatars + profile metadata.
// Usage: dart run example/profile_lookup.dart [username]
import 'package:piratetok_live/piratetok_live.dart';

void main(List<String> args) async {
  final username = args.isNotEmpty ? args.first : 'tiktok';
  final cache = ProfileCache();

  print('Fetching profile for @$username...');
  try {
    final p = await cache.fetch(username);
    final room = p.roomId.isEmpty ? '(offline)' : p.roomId;
    final bio = p.bioLink ?? '(none)';

    print('  User ID:    ${p.userId}');
    print('  Nickname:   ${p.nickname}');
    print('  Verified:   ${p.verified}');
    print('  Followers:  ${p.followerCount}');
    print('  Videos:     ${p.videoCount}');
    print('  Avatar (thumb):  ${p.avatarThumb}');
    print('  Avatar (720):    ${p.avatarMedium}');
    print('  Avatar (1080):   ${p.avatarLarge}');
    print('  Bio link:   $bio');
    print('  Room ID:    $room');

    print('\nFetching @$username again (should be cached)...');
    final p2 = await cache.fetch(username);
    print('  [cached] ${p2.nickname} — ${p2.followerCount} followers');
  } on ProfilePrivateError {
    print('  @$username is a private account');
  } on ProfileNotFoundError {
    print('  @$username does not exist');
  } catch (e) {
    print('  [ERROR] $e');
  }
}
