// Replay test -- reads a binary WSS capture, processes it through the full
// decode pipeline, and asserts every value matches the manifest JSON.
//
// Skips if testdata is not available. Set PIRATETOK_TESTDATA env var or
// place captures in ../live-testdata/ or ../../live-rs/captures/.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:piratetok_live/src/connection/frames.dart';
import 'package:piratetok_live/src/events/router.dart' as router;
import 'package:piratetok_live/src/events/types.dart';
import 'package:piratetok_live/src/helpers/gift_streak.dart';
import 'package:piratetok_live/src/helpers/like_accumulator.dart';
import 'package:test/test.dart';

// --- Dart event type → manifest canonical name ---

const _eventTypeName = <String, String>{
  EventType.connected: 'Connected',
  EventType.disconnected: 'Disconnected',
  EventType.reconnecting: 'Reconnecting',
  EventType.chat: 'Chat',
  EventType.gift: 'Gift',
  EventType.like: 'Like',
  EventType.member: 'Member',
  EventType.social: 'Social',
  EventType.follow: 'Follow',
  EventType.share: 'Share',
  EventType.join: 'Join',
  EventType.roomUserSeq: 'RoomUserSeq',
  EventType.control: 'Control',
  EventType.liveEnded: 'LiveEnded',
  EventType.liveIntro: 'LiveIntro',
  EventType.roomMessage: 'RoomMessage',
  EventType.caption: 'Caption',
  EventType.goalUpdate: 'GoalUpdate',
  EventType.imDelete: 'ImDelete',
  EventType.rankUpdate: 'RankUpdate',
  EventType.poll: 'Poll',
  EventType.envelope: 'Envelope',
  EventType.roomPin: 'RoomPin',
  EventType.unauthorizedMember: 'UnauthorizedMember',
  EventType.linkMicMethod: 'LinkMicMethod',
  EventType.linkMicBattle: 'LinkMicBattle',
  EventType.linkMicArmies: 'LinkMicArmies',
  EventType.linkMessage: 'LinkMessage',
  EventType.linkLayer: 'LinkLayer',
  EventType.linkMicLayoutState: 'LinkMicLayoutState',
  EventType.giftPanelUpdate: 'GiftPanelUpdate',
  EventType.inRoomBanner: 'InRoomBanner',
  EventType.guide: 'Guide',
  EventType.emoteChat: 'EmoteChat',
  EventType.questionNew: 'QuestionNew',
  EventType.subNotify: 'SubNotify',
  EventType.barrage: 'Barrage',
  EventType.hourlyRank: 'HourlyRank',
  EventType.msgDetect: 'MsgDetect',
  EventType.linkMicFanTicket: 'LinkMicFanTicket',
  EventType.roomVerify: 'RoomVerify',
  EventType.oecLiveShopping: 'OecLiveShopping',
  EventType.giftBroadcast: 'GiftBroadcast',
  EventType.rankText: 'RankText',
  EventType.giftDynamicRestriction: 'GiftDynamicRestriction',
  EventType.viewerPicksUpdate: 'ViewerPicksUpdate',
  EventType.accessControl: 'AccessControl',
  EventType.accessRecall: 'AccessRecall',
  EventType.alertBoxAuditResult: 'AlertBoxAuditResult',
  EventType.bindingGift: 'BindingGift',
  EventType.boostCard: 'BoostCard',
  EventType.bottom: 'BottomMessage',
  EventType.gameRankNotify: 'GameRankNotify',
  EventType.giftPrompt: 'GiftPrompt',
  EventType.linkState: 'LinkState',
  EventType.linkMicBattlePunishFinish: 'LinkMicBattlePunishFinish',
  EventType.linkmicBattleTask: 'LinkmicBattleTask',
  EventType.marqueeAnnouncement: 'MarqueeAnnouncement',
  EventType.notice: 'Notice',
  EventType.notify: 'Notify',
  EventType.partnershipDropsUpdate: 'PartnershipDropsUpdate',
  EventType.partnershipGameOffline: 'PartnershipGameOffline',
  EventType.partnershipPunish: 'PartnershipPunish',
  EventType.perception: 'Perception',
  EventType.speaker: 'Speaker',
  EventType.subCapsule: 'SubCapsule',
  EventType.subPinEvent: 'SubPinEvent',
  EventType.subscriptionNotify: 'SubscriptionNotify',
  EventType.toast: 'Toast',
  EventType.system: 'SystemMessage',
  EventType.liveGameIntro: 'LiveGameIntro',
  EventType.unknown: 'Unknown',
};

String canonicalName(String dartType) => _eventTypeName[dartType] ?? dartType;

// --- testdata location ---

(String capturesDir, String manifestsDir)? _findTestdata() {
  final env = Platform.environment['PIRATETOK_TESTDATA'];
  if (env != null && env.isNotEmpty) {
    final d = Directory(env);
    if (d.existsSync()) {
      return ('$env/captures', '$env/manifests');
    }
  }
  // testdata/ in repo root
  const local = 'testdata';
  if (Directory('$local/captures').existsSync()) {
    return ('$local/captures', '$local/manifests');
  }
  return null;
}

// --- binary capture reader ---

List<Uint8List> _readCapture(String path) {
  final data = File(path).readAsBytesSync();
  final frames = <Uint8List>[];
  var pos = 0;
  while (pos + 4 <= data.length) {
    final len = data[pos] |
        (data[pos + 1] << 8) |
        (data[pos + 2] << 16) |
        (data[pos + 3] << 24);
    pos += 4;
    if (pos + len > data.length) {
      fail('truncated frame at offset ${pos - 4}');
    }
    frames.add(Uint8List.sublistView(data, pos, pos + len));
    pos += len;
  }
  return frames;
}

// --- replay engine ---

class _ReplayResult {
  int frameCount = 0;
  int messageCount = 0;
  int eventCount = 0;
  int decodeFailures = 0;
  int decompressFailures = 0;

  final payloadTypes = <String, int>{};
  final messageTypes = <String, int>{};
  final eventTypes = <String, int>{};

  int followCount = 0;
  int shareCount = 0;
  int joinCount = 0;
  int liveEndedCount = 0;

  final unknownTypes = <String, int>{};

  // like: (wireCount, wireTotal, accTotal, accumulated, wentBackwards)
  final likeEvents = <(int, int, int, int, bool)>[];

  // gift groups: groupId -> [(giftId, repeatCount, delta, isFinal, diamondTotal)]
  final giftGroups = <String, List<(int, int, int, bool, int)>>{};
  int comboCount = 0;
  int nonComboCount = 0;
  int streakFinals = 0;
  int negativeDeltasCount = 0;
}

_ReplayResult _replay(List<Uint8List> frames) {
  final r = _ReplayResult();
  r.frameCount = frames.length;

  final likeAcc = LikeAccumulator();
  final giftTracker = GiftStreakTracker();

  for (final raw in frames) {
    // Step 2: decode WebcastPushFrame
    final ({
      int seqId,
      int logId,
      String payloadEncoding,
      String payloadType,
      Uint8List payload,
    }) frame;
    try {
      frame = parsePushFrame(raw);
    } on Object {
      r.decodeFailures++;
      continue;
    }

    // Step 3: count payload_type
    r.payloadTypes[frame.payloadType] =
        (r.payloadTypes[frame.payloadType] ?? 0) + 1;

    if (frame.payloadType != 'msg') continue;

    // Step 4: gzip decompress if needed
    final Uint8List decompressed;
    try {
      decompressed = decompressIfGzipped(frame.payload);
    } on Object {
      r.decompressFailures++;
      continue;
    }

    // Step 4b: decode WebcastResponse
    final ({
      List<({String method, Uint8List payload, int msgId})> messages,
      Uint8List internalExt,
      bool needsAck,
    }) response;
    try {
      response = parseResponse(decompressed);
    } on Object {
      r.decodeFailures++;
      continue;
    }

    // Step 5: iterate messages
    for (final msg in response.messages) {
      r.messageCount++;
      r.messageTypes[msg.method] = (r.messageTypes[msg.method] ?? 0) + 1;

      // Route through the same event mapper as the live connection
      final events = router.decode(msg.method, msg.payload, '');

      // Capture the primary (raw) event data for helper processing
      final primaryData =
          events.isNotEmpty ? events.first.data : null;

      for (final evt in events) {
        r.eventCount++;
        final name = canonicalName(evt.type);
        r.eventTypes[name] = (r.eventTypes[name] ?? 0) + 1;

        // Sub-routed tracking
        switch (evt.type) {
          case EventType.follow:
            r.followCount++;
          case EventType.share:
            r.shareCount++;
          case EventType.join:
            r.joinCount++;
          case EventType.liveEnded:
            r.liveEndedCount++;
          case EventType.unknown:
            final method = evt.data?['method'] as String? ?? '';
            if (method.isNotEmpty) {
              r.unknownTypes[method] =
                  (r.unknownTypes[method] ?? 0) + 1;
            }
        }
      }

      // Like accumulator (step 8) -- reuse decoded data
      if (msg.method == 'WebcastLikeMessage' &&
          primaryData != null) {
        final wireCount = _intVal(primaryData, 'count');
        final wireTotal = _intVal(primaryData, 'total');
        final stats = likeAcc.process(primaryData);
        r.likeEvents.add((
          wireCount,
          wireTotal,
          stats.totalLikeCount,
          stats.accumulatedCount,
          stats.wentBackwards,
        ));
      }

      // Gift streak tracker (step 9) -- reuse decoded data
      if (msg.method == 'WebcastGiftMessage' &&
          primaryData != null) {
        // Match Rust: is_combo_gift() checks gift_details.gift_type == 1
        final gift = primaryData['gift'] as Map<String, dynamic>?;
        final isCombo = (gift?['type'] as int? ?? 0) == 1;
        if (isCombo) {
          r.comboCount++;
        } else {
          r.nonComboCount++;
        }

        final streak = giftTracker.process(primaryData);
        if (streak.isFinal) r.streakFinals++;
        if (streak.eventGiftCount < 0) r.negativeDeltasCount++;

        final groupId =
            (primaryData['groupId'] as int? ?? 0).toString();
        final giftId = _intVal(primaryData, 'giftId');
        final repeatCount = _intVal(primaryData, 'repeatCount');
        r.giftGroups.putIfAbsent(groupId, () => []).add((
          giftId,
          repeatCount,
          streak.eventGiftCount,
          streak.isFinal,
          streak.totalDiamondCount,
        ));
      }
    }
  }

  return r;
}

int _intVal(Map<String, dynamic> m, String key) {
  final v = m[key];
  if (v is int) return v;
  return 0;
}

// --- assertion runner ---

void _assertReplay(String name, _ReplayResult r, Map<String, dynamic> m) {
  expect(r.frameCount, m['frame_count'], reason: '$name: frame_count');
  expect(r.messageCount, m['message_count'], reason: '$name: message_count');
  expect(r.eventCount, m['event_count'], reason: '$name: event_count');
  expect(r.decodeFailures, m['decode_failures'],
      reason: '$name: decode_failures');
  expect(r.decompressFailures, m['decompress_failures'],
      reason: '$name: decompress_failures');

  // payload_types
  final expectedPt = (m['payload_types'] as Map<String, dynamic>)
      .map((k, v) => MapEntry(k, (v as num).toInt()));
  expect(r.payloadTypes, expectedPt, reason: '$name: payload_types');

  // message_types
  final expectedMt = (m['message_types'] as Map<String, dynamic>)
      .map((k, v) => MapEntry(k, (v as num).toInt()));
  expect(r.messageTypes, expectedMt, reason: '$name: message_types');

  // event_types
  final expectedEt = (m['event_types'] as Map<String, dynamic>)
      .map((k, v) => MapEntry(k, (v as num).toInt()));
  expect(r.eventTypes, expectedEt, reason: '$name: event_types');

  // sub_routed
  final sub = m['sub_routed'] as Map<String, dynamic>;
  expect(r.followCount, sub['follow'], reason: '$name: sub_routed.follow');
  expect(r.shareCount, sub['share'], reason: '$name: sub_routed.share');
  expect(r.joinCount, sub['join'], reason: '$name: sub_routed.join');
  expect(r.liveEndedCount, sub['live_ended'],
      reason: '$name: sub_routed.live_ended');

  // unknown_types
  final expectedUnk = (m['unknown_types'] as Map<String, dynamic>)
      .map((k, v) => MapEntry(k, (v as num).toInt()));
  expect(r.unknownTypes, expectedUnk, reason: '$name: unknown_types');

  // like accumulator
  _assertLikes(name, r, m['like_accumulator'] as Map<String, dynamic>);

  // gift streaks
  _assertGifts(name, r, m['gift_streaks'] as Map<String, dynamic>);
}

void _assertLikes(String name, _ReplayResult r, Map<String, dynamic> ml) {
  expect(r.likeEvents.length, ml['event_count'],
      reason: '$name: like event_count');

  final backwards = r.likeEvents.where((e) => e.$5).length;
  expect(backwards, ml['backwards_jumps'],
      reason: '$name: like backwards_jumps');

  if (r.likeEvents.isNotEmpty) {
    final last = r.likeEvents.last;
    expect(last.$3, ml['final_max_total'],
        reason: '$name: like final_max_total');
    expect(last.$4, ml['final_accumulated'],
        reason: '$name: like final_accumulated');
  }

  var accMono = true;
  var accumMono = true;
  for (var i = 1; i < r.likeEvents.length; i++) {
    if (r.likeEvents[i].$3 < r.likeEvents[i - 1].$3) accMono = false;
    if (r.likeEvents[i].$4 < r.likeEvents[i - 1].$4) accumMono = false;
  }
  expect(accMono, ml['acc_total_monotonic'],
      reason: '$name: like acc_total_monotonic');
  expect(accumMono, ml['accumulated_monotonic'],
      reason: '$name: like accumulated_monotonic');

  // event-by-event
  final expectedEvents = ml['events'] as List<dynamic>;
  expect(r.likeEvents.length, expectedEvents.length,
      reason: '$name: like events length');
  for (var i = 0; i < r.likeEvents.length; i++) {
    final got = r.likeEvents[i];
    final exp = expectedEvents[i] as Map<String, dynamic>;
    expect(got.$1, exp['wire_count'],
        reason: '$name: like[$i].wire_count');
    expect(got.$2, exp['wire_total'],
        reason: '$name: like[$i].wire_total');
    expect(got.$3, exp['acc_total'],
        reason: '$name: like[$i].acc_total');
    expect(got.$4, exp['accumulated'],
        reason: '$name: like[$i].accumulated');
    expect(got.$5, exp['went_backwards'],
        reason: '$name: like[$i].went_backwards');
  }
}

void _assertGifts(String name, _ReplayResult r, Map<String, dynamic> mg) {
  final totalGifts = r.comboCount + r.nonComboCount;
  expect(totalGifts, mg['event_count'], reason: '$name: gift event_count');
  expect(r.comboCount, mg['combo_count'], reason: '$name: gift combo_count');
  expect(r.nonComboCount, mg['non_combo_count'],
      reason: '$name: gift non_combo_count');
  expect(r.streakFinals, mg['streak_finals'],
      reason: '$name: gift streak_finals');
  expect(r.negativeDeltasCount, mg['negative_deltas'],
      reason: '$name: gift negative_deltas');

  // group-by-group
  final expectedGroups = mg['groups'] as Map<String, dynamic>;
  expect(r.giftGroups.length, expectedGroups.length,
      reason: '$name: gift groups count');

  for (final gid in r.giftGroups.keys) {
    final gotEvts = r.giftGroups[gid]!;
    final expEvts = (expectedGroups[gid] as List<dynamic>?) ??
        (throw TestFailure('$name: missing gift group $gid'));

    expect(gotEvts.length, expEvts.length,
        reason: '$name: gift group $gid length');

    for (var i = 0; i < gotEvts.length; i++) {
      final got = gotEvts[i];
      final exp = expEvts[i] as Map<String, dynamic>;
      expect(got.$1, exp['gift_id'],
          reason: '$name: gift[$gid][$i].gift_id');
      expect(got.$2, exp['repeat_count'],
          reason: '$name: gift[$gid][$i].repeat_count');
      expect(got.$3, exp['delta'],
          reason: '$name: gift[$gid][$i].delta');
      expect(got.$4, exp['is_final'],
          reason: '$name: gift[$gid][$i].is_final');
      expect(got.$5, exp['diamond_total'],
          reason: '$name: gift[$gid][$i].diamond_total');
    }
  }
}

// --- test runner ---

void _runCaptureTest(String name) {
  final testdata = _findTestdata();
  if (testdata == null) {
    // ignore: avoid_print
    print('SKIP $name: no testdata '
        '(set PIRATETOK_TESTDATA or clone live-testdata)');
    return;
  }

  final (capturesDir, manifestsDir) = testdata;
  final capPath = '$capturesDir/$name.bin';
  final manPath = '$manifestsDir/$name.json';

  if (!File(capPath).existsSync()) {
    // ignore: avoid_print
    print('SKIP $name: capture not found at $capPath');
    return;
  }
  if (!File(manPath).existsSync()) {
    // ignore: avoid_print
    print('SKIP $name: manifest not found at $manPath');
    return;
  }

  final manifestJson = File(manPath).readAsStringSync();
  final manifest = jsonDecode(manifestJson) as Map<String, dynamic>;

  final frames = _readCapture(capPath);
  final result = _replay(frames);

  _assertReplay(name, result, manifest);
}

void main() {
  test('replay calvinterest6', () => _runCaptureTest('calvinterest6'));
  test('replay happyhappygaltv', () => _runCaptureTest('happyhappygaltv'));
  test('replay fox4newsdallasfortworth',
      () => _runCaptureTest('fox4newsdallasfortworth'));
}
