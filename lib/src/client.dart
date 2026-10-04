import 'dart:async';

import 'auth/ttwid.dart';
import 'connection/url.dart';
import 'connection/wss.dart';
import 'errors.dart';
import 'events/types.dart';
import 'http/api.dart';
import 'http/ua.dart';
import 'reconnect.dart';

const _defaultCdn = 'webcast-ws.tiktok.com';

class TikTokLiveClient {
  final String _username;
  String _cdnHost = _defaultCdn;
  Duration _timeout = const Duration(seconds: 10);
  Duration _heartbeatInterval = const Duration(seconds: 10);
  int _maxRetries = 5;
  Duration _staleTimeout = const Duration(seconds: 60);
  String _proxy = '';
  String? _userAgent;
  String? _cookies;
  String? _language;
  String? _region;
  bool _compress = true;
  Completer<void>? _stop;
  final _listeners = <String, List<void Function(TikTokEvent)>>{};

  TikTokLiveClient(this._username);

  TikTokLiveClient cdnEu() {
    _cdnHost = 'webcast-ws.eu.tiktok.com';
    return this;
  }

  TikTokLiveClient cdnUs() {
    _cdnHost = 'webcast-ws.us.tiktok.com';
    return this;
  }

  TikTokLiveClient cdn(String host) {
    _cdnHost = host;
    return this;
  }

  TikTokLiveClient timeout(Duration d) {
    _timeout = d;
    return this;
  }

  /// Interval between WSS heartbeats (default 10s). Also sent to TikTok as the
  /// `heartbeat_duration` URL param (ms).
  TikTokLiveClient heartbeatInterval(Duration d) {
    _heartbeatInterval = d;
    return this;
  }

  /// Max consecutive failed attempts (default 5); a 30s healthy session resets the count.
  TikTokLiveClient maxRetries(int n) {
    _maxRetries = n;
    return this;
  }

  TikTokLiveClient staleTimeout(Duration d) {
    _staleTimeout = d;
    return this;
  }

  TikTokLiveClient proxy(String url) {
    _proxy = url;
    return this;
  }

  /// Override the user agent for all requests (HTTP + WSS).
  ///
  /// When not set, a random UA from the built-in pool is picked on each
  /// reconnect attempt. This is recommended for reducing DEVICE_BLOCKED risk.
  TikTokLiveClient userAgent(String ua) {
    _userAgent = ua;
    return this;
  }

  /// Set session cookies for the WSS connection.
  ///
  /// Only required for fetching room metadata on age-restricted (18+) rooms.
  /// Not required for WSS connection, event streaming, or any other functionality.
  /// Cookie format: `sessionid=xxx; sid_tt=xxx`
  TikTokLiveClient cookies(String c) {
    _cookies = c;
    return this;
  }

  /// Override the language for all requests (HTTP query params, Accept-Language header).
  ///
  /// When not set, detected from the system locale via [systemLanguage()],
  /// falling back to `'en'` if detection fails.
  TikTokLiveClient language(String lang) {
    _language = lang;
    return this;
  }

  /// Override the region for all requests (browser_language param, Accept-Language header).
  ///
  /// When not set, detected from the system locale via [systemRegion()],
  /// falling back to `'US'` if detection fails.
  TikTokLiveClient region(String reg) {
    _region = reg;
    return this;
  }

  /// Enable or disable gzip compression on the WSS connection.
  ///
  /// When enabled (default), the `compress` query param is set to `gzip`.
  /// When disabled, it is set to an empty string. The `compress` key is
  /// always present in the URL. The decode layer already handles both
  /// compressed and uncompressed payloads via gzip magic-byte detection.
  TikTokLiveClient compress(bool enabled) {
    _compress = enabled;
    return this;
  }

  /// Register an event listener for the given event type.
  void on(String eventType, void Function(TikTokEvent) handler) {
    _listeners.putIfAbsent(eventType, () => []).add(handler);
  }

  void _emit(TikTokEvent event) {
    final handlers = _listeners[event.type];
    if (handlers != null) {
      for (final fn in handlers) {
        fn(event);
      }
    }
  }

  /// Connect to TikTok Live with auto-reconnection.
  ///
  /// Runs the whole session: the future completes with the room_id only after
  /// the final disconnect ([disconnect] or max retries exhausted). Listen for
  /// [EventType.connected] to know when the room was resolved.
  Future<String> connect() async {
    final room = await checkOnline(
      _username,
      timeout: _timeout,
      proxy: _proxy,
      userAgent: _userAgent,
      language: _language,
      region: _region,
    );
    _stop = Completer<void>();
    _emit(TikTokEvent(
      EventType.connected,
      {'room_id': room.roomId},
      room.roomId,
    ));

    // ttwid + UA are fetched once and reused across reconnects; rotated only on
    // DEVICE_BLOCKED, a ttwid failure, or a connection that died young.
    final budget = ReconnectBudget(_maxRetries);
    _Session? held;
    while (!_stopped) {
      held ??= await _freshSession();
      final session = held;
      var exit = SessionExit.noTtwid;
      var lived = Duration.zero;
      if (session != null) {
        final started = DateTime.now();
        exit = await _runSession(room.roomId, session);
        lived = DateTime.now().difference(started);
      }
      if (_stopped) break;

      final judgement = judge(exit, lived);
      if (judgement.rotate) held = null;
      final verdict = budget.record(judgement.end);
      if (verdict.giveUp) break;

      _emit(TikTokEvent(
        EventType.reconnecting,
        {
          'attempt': verdict.attempt,
          'max_retries': _maxRetries,
          'delay': verdict.delay.inSeconds,
        },
        room.roomId,
      ));
      await Future.any([Future<void>.delayed(verdict.delay), _stop!.future]);
    }

    _emit(TikTokEvent(EventType.disconnected, null, room.roomId));
    return room.roomId;
  }

  bool get _stopped => _stop?.isCompleted ?? true;

  /// Returns null when the ttwid fetch failed — a failed attempt, not an abort.
  Future<_Session?> _freshSession() async {
    final ua = _userAgent ?? randomUa();
    try {
      final ttwid =
          await fetchTtwid(timeout: _timeout, proxy: _proxy, userAgent: ua);
      return (ttwid: ttwid, ua: ua);
    } on Object catch (e) {
      _emit(TikTokEvent('error', {'error': 'ttwid acquisition failed: $e'}));
      return null;
    }
  }

  Future<SessionExit> _runSession(String roomId, _Session session) async {
    final wssUrl = buildWssUrl(
      _cdnHost,
      roomId,
      language: _language,
      region: _region,
      compress: _compress,
      heartbeatInterval: _heartbeatInterval,
    );
    try {
      await connectWss(
        wssUrl: wssUrl,
        ttwid: session.ttwid,
        roomId: roomId,
        onEvent: _emit,
        onError: (e) => _emit(TikTokEvent('error', {'error': '$e'})),
        stopSignal: _stop!,
        heartbeatInterval: _heartbeatInterval,
        staleTimeout: _staleTimeout,
        proxy: _proxy,
        userAgent: session.ua,
        cookies: _cookies,
        language: _language,
        region: _region,
      );
      return SessionExit.closed;
    } on DeviceBlockedError {
      return SessionExit.deviceBlocked;
    } on Object catch (e) {
      _emit(TikTokEvent('error', {'error': 'websocket error: $e'}));
      return SessionExit.errored;
    }
  }

  /// Clean disconnect — exits the reconnect loop.
  void disconnect() {
    if (_stop != null && !_stop!.isCompleted) {
      _stop!.complete();
    }
  }
}

typedef _Session = ({String ttwid, String ua});
