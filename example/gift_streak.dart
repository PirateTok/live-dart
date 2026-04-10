// Gift streak tracker — shows per-event deltas for combo gifts.
//
// Usage:
//   dart run example/gift_streak.dart <username>

import 'dart:io';

import 'package:piratetok_live/piratetok_live.dart';

void main(List<String> args) async {
  if (args.isEmpty) {
    print('usage: dart run example/gift_streak.dart <username>');
    exit(1);
  }

  final client = TikTokLiveClient(args[0]).cdnEu();
  final tracker = GiftStreakTracker();
  var totalDiamonds = 0;

  // Clean shutdown on Ctrl+C
  ProcessSignal.sigint.watch().listen((_) {
    print('\ndisconnecting...');
    client.disconnect();
  });

  client.on(EventType.connected, (evt) {
    print('connected to room ${evt.data?['room_id']}\n');
  });

  client.on(EventType.gift, (evt) {
    final data = evt.data;
    if (data == null) return;

    final e = tracker.process(data);

    final user = data['user'] as Map<String, dynamic>?;
    final nick = user?['uniqueId'] ?? user?['nickname'] ?? '?';
    final gift = data['gift'] as Map<String, dynamic>?;
    final name = gift?['name'] ?? '?';

    if (e.isFinal) {
      totalDiamonds += e.totalDiamondCount;
      print('[FINAL] streak=${e.streakId} $nick -> $name x${e.totalGiftCount}'
          ' — ${e.totalDiamondCount} diamonds');
      print('        running total: $totalDiamonds diamonds\n');
    } else if (e.eventGiftCount > 0) {
      print('[ongoing] streak=${e.streakId} $nick -> $name'
          ' +${e.eventGiftCount} (+${e.eventDiamondCount} dmnd)');
    }
  });

  client.on(EventType.liveEnded, (evt) {
    print('[stream ended]');
  });

  client.on(EventType.reconnecting, (evt) {
    print('[reconnecting] attempt ${evt.data?['attempt']}'
        '/${evt.data?['max_retries']} in ${evt.data?['delay']}s');
  });

  client.on(EventType.disconnected, (evt) {
    print('\nfinal total: $totalDiamonds diamonds');
    print('active streaks at disconnect: ${tracker.activeStreaks}');
  });

  await client.connect();
  exit(0);
}
