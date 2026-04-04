import 'dart:async';
import 'dart:io';

import 'package:piratetok_live/src/auth/ttwid.dart';
import 'package:piratetok_live/src/connection/frames.dart';
import 'package:piratetok_live/src/connection/raw_ws.dart';
import 'package:piratetok_live/src/connection/url.dart';
import 'package:piratetok_live/src/http/api.dart';
import 'package:piratetok_live/src/http/ua.dart';

void main(List<String> args) async {
  if (args.isEmpty) {
    print('usage: dart run example/debug_rawws.dart <username>');
    exit(1);
  }

  final room = await checkOnline(args[0]);
  print('room_id: ${room.roomId}');

  final ttwid = await fetchTtwid();
  print('ttwid: ok');

  final cdnHost = 'webcast-ws.tiktok.com';
  final wssUrl = buildWssUrl(cdnHost, room.roomId);
  final ua = randomUa();

  print('connecting with RawWebSocket (bypasses dart:io WebSocket)...');
  final ws = await RawWebSocket.connect(
    wssUrl,
    headers: {
      'User-Agent': ua,
      'Cookie': 'ttwid=$ttwid',
      'Origin': 'https://www.tiktok.com',
      'Referer': 'https://www.tiktok.com/',
      'Accept-Language': 'en-US,en;q=0.9',
      'Accept-Encoding': 'gzip, deflate',
      'Cache-Control': 'no-cache',
    },
  );
  print('connected!');

  ws.send(buildHeartbeat(room.roomId));
  ws.send(buildEnterRoom(room.roomId));
  print('sent hb + enter_room');

  final hbTimer = Timer.periodic(Duration(seconds: 10), (_) {
    try {
      ws.send(buildHeartbeat(room.roomId));
    } catch (_) {}
  });

  var evtCount = 0;
  ws.stream.listen(
    (data) {
      try {
        final frame = parsePushFrame(data);
        if (frame.payloadType == 'msg') {
          final decompressed = decompressIfGzipped(frame.payload);
          final response = parseResponse(decompressed);
          if (response.needsAck && response.internalExt.isNotEmpty) {
            ws.send(buildAck(frame.logId, response.internalExt));
          }
          for (final msg in response.messages) {
            evtCount++;
            print('EVENT #$evtCount: ${msg.method} (${msg.payload.length}b)');
          }
          if (response.messages.isEmpty && evtCount == 0) {
            print('(initial cursor/ack)');
          }
        } else if (frame.payloadType == 'im_enter_room_resp') {
          print('enter_room accepted');
        } else if (frame.payloadType != 'hb') {
          print('frame: ${frame.payloadType}');
        }
      } catch (e) {
        print('ERR: $e');
      }
    },
    onDone: () =>
        print('DONE close=${ws.closeCode} reason=${ws.closeReason}'),
  );

  await Future.delayed(Duration(seconds: 30));
  print('\n=== $evtCount events in 30s ===');
  hbTimer.cancel();
  await ws.close();
  exit(0);
}
