import 'dart:io';

import 'package:piratetok_live/piratetok_live.dart';

void main(List<String> args) async {
  if (args.isEmpty) {
    print('usage: dart run example/stream_info.dart <username> [cookies]');
    exit(1);
  }

  final username = args[0];
  final cookies = args.length > 1 ? args[1] : '';

  final RoomIdResult room;
  try {
    room = await checkOnline(username);
  } on HostNotOnlineError {
    print('$username is not live');
    exit(1);
  } on UserNotFoundError {
    print('$username does not exist');
    exit(1);
  }

  print('room_id: ${room.roomId}');

  try {
    final info = await fetchRoomInfo(room.roomId, cookies: cookies);
    print('title:      ${info.title}');
    print('viewers:    ${info.viewers}');
    print('likes:      ${info.likes}');
    print('total_user: ${info.totalUser}');

    if (info.streamUrl != null) {
      final s = info.streamUrl!;
      print('flv_origin: ${s.flvOrigin.isEmpty ? '(none)' : s.flvOrigin}');
      print('flv_hd:     ${s.flvHd.isEmpty ? '(none)' : s.flvHd}');
      print('flv_sd:     ${s.flvSd.isEmpty ? '(none)' : s.flvSd}');
      print('flv_ld:     ${s.flvLd.isEmpty ? '(none)' : s.flvLd}');
      print('flv_audio:  ${s.flvAudio.isEmpty ? '(none)' : s.flvAudio}');
    } else {
      print('no stream URLs available');
    }
  } on AgeRestrictedError {
    print('18+ room — pass session cookies: sessionid=xxx;sid_tt=xxx');
    exit(1);
  }
}
