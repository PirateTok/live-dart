import 'dart:io';

import 'package:piratetok_live/piratetok_live.dart';

void main(List<String> args) async {
  if (args.isEmpty) {
    print('usage: dart run example/online_check.dart <username>');
    exit(1);
  }

  final username = args[0];

  try {
    final result = await checkOnline(username);
    print('LIVE  $username  room_id=${result.roomId}');
  } on HostNotOnlineError {
    print('OFF   $username');
    exit(1);
  } on UserNotFoundError {
    print('404   $username does not exist');
    exit(1);
  } on TikTokBlockedError catch (e) {
    print('BLOCKED  HTTP ${e.statusCode}');
    exit(1);
  }
}
