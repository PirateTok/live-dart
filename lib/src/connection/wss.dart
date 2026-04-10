import 'dart:async';
import 'dart:typed_data';

import '../errors.dart';
import '../events/router.dart' as router;
import '../events/types.dart';
import '../http/ua.dart';
import 'frames.dart';
import 'raw_ws.dart';

const _heartbeatInterval = Duration(seconds: 10);
const _defaultStaleTimeout = Duration(seconds: 60);

/// Connect to TikTok WSS, stream events until stopped or connection drops.
///
/// Throws [DeviceBlockedError] on DEVICE_BLOCKED handshake rejection.
/// Returns normally on clean close, stop, or stale timeout.
Future<void> connectWss({
  required String wssUrl,
  required String ttwid,
  required String roomId,
  required void Function(TikTokEvent) onEvent,
  required void Function(Object error) onError,
  required Completer<void> stopSignal,
  Duration staleTimeout = _defaultStaleTimeout,
  String proxy = '',
  String? userAgent,
  String? cookies,
}) async {
  final ua = userAgent ?? randomUa();
  final cookieHeader =
      cookies != null ? 'ttwid=$ttwid; $cookies' : 'ttwid=$ttwid';

  final headers = {
    'User-Agent': ua,
    'Cookie': cookieHeader,
    'Origin': 'https://www.tiktok.com',
    'Referer': 'https://www.tiktok.com/',
    'Accept-Language': 'en-US,en;q=0.9',
    'Accept-Encoding': 'gzip, deflate',
    'Cache-Control': 'no-cache',
  };

  // RawWebSocket throws DeviceBlockedError directly on DEVICE_BLOCKED.
  // Proxy uses CONNECT tunnel when specified.
  final ws = await RawWebSocket.connect(wssUrl, headers: headers, proxy: proxy);

  // Send initial heartbeat + enter room
  ws.send(buildHeartbeat(roomId));
  ws.send(buildEnterRoom(roomId));

  // Heartbeat timer
  final hbTimer = Timer.periodic(_heartbeatInterval, (_) {
    try {
      ws.send(buildHeartbeat(roomId));
    } on Object {
      // connection already closed
    }
  });

  // Stop listener
  stopSignal.future.then((_) {
    ws.close();
  });

  try {
    await for (final data in ws.stream.timeout(staleTimeout, onTimeout: (sink) {
      sink.close();
    })) {
      if (stopSignal.isCompleted) break;

      try {
        _processFrame(data, ws, roomId, onEvent);
      } on Object catch (err) {
        onError(err);
      }
    }
  } on Object {
    // timeout, socket error, or stream error — caller decides retry
  } finally {
    hbTimer.cancel();
    try {
      await ws.close();
    } on Object {
      // already closed
    }
  }
}

void _processFrame(
  Uint8List raw,
  RawWebSocket ws,
  String roomId,
  void Function(TikTokEvent) onEvent,
) {
  final frame = parsePushFrame(raw);

  if (frame.payloadType != 'msg') return;

  final decompressed = decompressIfGzipped(frame.payload);
  final response = parseResponse(decompressed);

  if (response.needsAck && response.internalExt.isNotEmpty) {
    try {
      ws.send(buildAck(frame.logId, response.internalExt));
    } on Object {
      // connection closing
    }
  }

  for (final msg in response.messages) {
    final events = router.decode(msg.method, msg.payload, roomId);
    for (final evt in events) {
      onEvent(evt);
    }
  }
}
