import 'dart:io';

import 'package:piratetok_live/piratetok_live.dart';

void main(List<String> args) async {
  if (args.isEmpty) {
    print('usage: dart run example/basic_chat.dart <username>');
    exit(1);
  }

  final client = TikTokLiveClient(args[0]).cdnEu();

  // Clean shutdown on Ctrl+C
  ProcessSignal.sigint.watch().listen((_) {
    print('\ndisconnecting...');
    client.disconnect();
  });

  client.on(EventType.connected, (evt) {
    print('connected to room ${evt.data?['room_id']}');
  });

  client.on(EventType.chat, (evt) {
    final user = evt.data?['user'] as Map<String, dynamic>?;
    final nick = user?['uniqueId'] ?? user?['nickname'] ?? '?';
    print('[chat] $nick: ${evt.data?['content'] ?? ''}');
  });

  client.on(EventType.gift, (evt) {
    final user = evt.data?['user'] as Map<String, dynamic>?;
    final nick = user?['uniqueId'] ?? user?['nickname'] ?? '?';
    final gift = evt.data?['gift'] as Map<String, dynamic>?;
    print('[gift] $nick sent ${gift?['name'] ?? '?'} x${evt.data?['repeatCount'] ?? 1}');
  });

  client.on(EventType.follow, (evt) {
    final user = evt.data?['user'] as Map<String, dynamic>?;
    final nick = user?['uniqueId'] ?? user?['nickname'] ?? '?';
    print('[follow] $nick');
  });

  client.on(EventType.join, (evt) {
    final user = evt.data?['user'] as Map<String, dynamic>?;
    final nick = user?['uniqueId'] ?? user?['nickname'] ?? '?';
    print('[join] $nick');
  });

  client.on(EventType.like, (evt) {
    final user = evt.data?['user'] as Map<String, dynamic>?;
    final nick = user?['uniqueId'] ?? user?['nickname'] ?? '?';
    print('[like] $nick x${evt.data?['count'] ?? 1}');
  });

  client.on(EventType.roomUserSeq, (evt) {
    print('[viewers] ${evt.data?['totalUser'] ?? '?'}');
  });

  client.on(EventType.liveEnded, (evt) {
    print('[stream ended]');
  });

  client.on(EventType.reconnecting, (evt) {
    print('[reconnecting] attempt ${evt.data?['attempt']}/${evt.data?['max_retries']} in ${evt.data?['delay']}s');
  });

  client.on(EventType.disconnected, (evt) {
    print('disconnected');
  });

  await client.connect();
  exit(0);
}
