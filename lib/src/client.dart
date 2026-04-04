import 'dart:async';

import 'auth/ttwid.dart';
import 'connection/url.dart';
import 'connection/wss.dart';
import 'errors.dart';
import 'events/types.dart';
import 'http/api.dart';

const _defaultCdn = 'webcast-ws.tiktok.com';

class TikTokLiveClient {
  final String _username;
  String _cdnHost = _defaultCdn;
  Duration _timeout = const Duration(seconds: 10);
  int _maxRetries = 5;
  Duration _staleTimeout = const Duration(seconds: 60);
  String _proxy = '';
  String? _userAgent;
  String? _cookies;
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

  /// Connect to TikTok Live with auto-reconnection. Returns room_id.
  Future<String> connect() async {
    final room = await checkOnline(
      _username,
      timeout: _timeout,
      proxy: _proxy,
      userAgent: _userAgent,
    );
    _stop = Completer<void>();
    _emit(TikTokEvent(
      EventType.connected,
      {'room_id': room.roomId},
      room.roomId,
    ));

    var attempt = 0;
    while (!(_stop?.isCompleted ?? true)) {
      final ttwid = await fetchTtwid(
        timeout: _timeout,
        proxy: _proxy,
        userAgent: _userAgent,
      );
      final wssUrl = buildWssUrl(_cdnHost, room.roomId);

      var isDeviceBlocked = false;
      try {
        await connectWss(
          wssUrl: wssUrl,
          ttwid: ttwid,
          roomId: room.roomId,
          onEvent: _emit,
          onError: (e) => _emit(TikTokEvent('error', {'error': '$e'})),
          stopSignal: _stop!,
          staleTimeout: _staleTimeout,
          proxy: _proxy,
          userAgent: _userAgent,
          cookies: _cookies,
        );
      } on DeviceBlockedError {
        isDeviceBlocked = true;
      }

      if (_stop?.isCompleted ?? true) break;

      attempt++;
      if (attempt > _maxRetries) break;

      final delay =
          isDeviceBlocked ? 2 : _backoffSeconds(attempt).clamp(2, 30);
      _emit(TikTokEvent(
        EventType.reconnecting,
        {
          'attempt': attempt,
          'max_retries': _maxRetries,
          'delay': delay,
        },
        room.roomId,
      ));
      await Future<void>.delayed(Duration(seconds: delay));
    }

    _emit(TikTokEvent(EventType.disconnected, null, room.roomId));
    return room.roomId;
  }

  /// Clean disconnect — exits the reconnect loop.
  void disconnect() {
    if (_stop != null && !_stop!.isCompleted) {
      _stop!.complete();
    }
  }

  static int _backoffSeconds(int attempt) => 1 << attempt; // 2,4,8,16,...
}
