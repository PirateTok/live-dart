// Offline test doubles: proxies and a webcast WS server on 127.0.0.1.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

typedef ProxyHit = ({String target, String auth});

/// A fake proxy. With [tunnel] false it records the request and refuses;
/// with [tunnel] true it connects to the target and pipes bytes both ways.
class FakeProxy {
  final ServerSocket _server;
  final bool tunnel;
  final hits = <ProxyHit>[];

  FakeProxy._(this._server, this.tunnel);

  int get port => _server.port;

  static Future<FakeProxy> connect({bool tunnel = false}) async {
    final p = FakeProxy._(await ServerSocket.bind(InternetAddress.loopbackIPv4, 0), tunnel);
    p._server.listen((s) => p._serveConnect(s));
    return p;
  }

  static Future<FakeProxy> socks5({bool tunnel = false}) async {
    final p = FakeProxy._(await ServerSocket.bind(InternetAddress.loopbackIPv4, 0), tunnel);
    p._server.listen((s) => p._serveSocks5(s));
    return p;
  }

  Future<void> close() => _server.close();

  Future<void> _serveConnect(Socket client) async {
    final r = _Reader(client);
    try {
      while (true) {
        final head = await r.head();
        final lines = head.split('\r\n');
        final target = lines.first.split(' ')[1];
        final auth = lines
            .where((l) => l.toLowerCase().startsWith('proxy-authorization:'))
            .map((l) => l.substring(l.indexOf(':') + 1).trim())
            .firstOrNull;
        if (auth == null) {
          client.write('HTTP/1.1 407 Proxy Authentication Required\r\n'
              'Proxy-Authenticate: Basic realm="fake"\r\nContent-Length: 0\r\n\r\n');
          continue;
        }
        hits.add((target: target, auth: auth));
        if (!tunnel) {
          client.write('HTTP/1.1 502 Bad Gateway\r\nContent-Length: 0\r\nConnection: close\r\n\r\n');
          await client.close();
          return;
        }
        final parts = target.split(':');
        final upstream = await Socket.connect(parts[0], int.parse(parts[1]));
        client.write('HTTP/1.1 200 Connection established\r\n\r\n');
        _pipe(r, client, upstream);
        return;
      }
    } on Object {
      client.destroy();
    }
  }

  Future<void> _serveSocks5(Socket client) async {
    final r = _Reader(client);
    try {
      final head = await r.take(2);
      final methods = await r.take(head[1]);
      var auth = '';
      if (methods.contains(0x02)) {
        client.add([0x05, 0x02]);
        final ver = await r.take(2);
        final user = utf8.decode(await r.take(ver[1]));
        final pass = utf8.decode(await r.take((await r.take(1))[0]));
        auth = '$user:$pass';
        client.add([0x01, 0x00]);
      } else {
        client.add([0x05, 0x00]);
      }
      final req = await r.take(4);
      final host = req[3] == 0x03
          ? utf8.decode(await r.take((await r.take(1))[0]))
          : InternetAddress.fromRawAddress(Uint8List.fromList(await r.take(4))).address;
      final port = await r.take(2);
      final target = '$host:${port[0] << 8 | port[1]}';
      hits.add((target: target, auth: auth));
      if (!tunnel) {
        client.add([0x05, 0x05, 0x00, 0x01, 0, 0, 0, 0, 0, 0]);
        await client.close();
        return;
      }
      final upstream = await Socket.connect(host, port[0] << 8 | port[1]);
      client.add([0x05, 0x00, 0x00, 0x01, 127, 0, 0, 1, 0, 0]);
      _pipe(r, client, upstream);
    } on Object {
      client.destroy();
    }
  }

  void _pipe(_Reader r, Socket client, Socket upstream) {
    if (r.buf.isNotEmpty) upstream.add(r.buf);
    r.sub.onData(upstream.add);
    r.sub.onDone(() => upstream.destroy());
    upstream.listen(client.add, onDone: () => client.destroy(), onError: (_) => client.destroy());
  }
}

class _Reader {
  late final StreamSubscription<Uint8List> sub;
  final buf = <int>[];
  Completer<void>? _more;
  bool _done = false;

  _Reader(Socket s) {
    sub = s.listen((c) {
      buf.addAll(c);
      _wake();
    }, onDone: () {
      _done = true;
      _wake();
    });
  }

  void _wake() {
    final m = _more;
    _more = null;
    m?.complete();
  }

  Future<void> _wait() async {
    if (_done) throw const SocketException('eof');
    _more = Completer<void>();
    await _more!.future;
  }

  Future<List<int>> take(int n) async {
    while (buf.length < n) {
      await _wait();
    }
    final out = buf.sublist(0, n);
    buf.removeRange(0, n);
    return out;
  }

  Future<String> head() async {
    while (true) {
      final s = latin1.decode(buf);
      final i = s.indexOf('\r\n\r\n');
      if (i >= 0) {
        buf.removeRange(0, i + 4);
        return s.substring(0, i);
      }
      await _wait();
    }
  }
}

/// Plain ws:// webcast server: hands each upgraded socket + its request to [onClient].
class FakeWebcast {
  final HttpServer _server;
  FakeWebcast._(this._server);

  int get port => _server.port;

  static Future<FakeWebcast> start(
      Future<void> Function(HttpRequest req, WebSocket ws) onClient) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      final ws = await WebSocketTransformer.upgrade(req);
      await onClient(req, ws);
    });
    return FakeWebcast._(server);
  }

  Future<void> close() => _server.close(force: true);
}
