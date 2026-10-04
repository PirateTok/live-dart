import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// A socket tunnelled through a proxy, plus its single live subscription
/// (paused). Sockets are single-subscription streams: whoever continues
/// reading must take over [sub] (`onData` / `resume`), never `listen` again.
class Tunnel {
  final Socket socket;
  final StreamSubscription<Uint8List> sub;
  Tunnel(this.socket, this.sub);
}

/// Opens a TCP tunnel to [host]:[port] through [proxy]: HTTP CONNECT for
/// `http://` / `https://` (Basic auth from `user:pass@`), the SOCKS5 handshake
/// (RFC 1928, user/pass per RFC 1929) for `socks5://` / `socks5h://`.
Future<Tunnel> openTunnel(Uri proxy, String host, int port) async {
  final scheme = proxy.scheme.toLowerCase();
  final socks = scheme == 'socks5' || scheme == 'socks5h';
  if (!socks && scheme != 'http' && scheme != 'https') {
    throw ArgumentError.value(proxy.toString(), 'proxy',
        'unsupported proxy scheme "$scheme" (http, https, socks5, socks5h)');
  }
  final socket = await Socket.connect(
      proxy.host, proxy.hasPort ? proxy.port : (socks ? 1080 : (scheme == 'https' ? 443 : 80)));
  final reader = _Reader(socket);
  try {
    if (socks) {
      await _socks5(socket, reader, proxy, host, port);
    } else {
      await _httpConnect(socket, reader, proxy, host, port);
    }
  } on Object {
    socket.destroy();
    rethrow;
  }
  if (reader.buffered.isNotEmpty) {
    socket.destroy();
    throw const SocketException('proxy sent data before the tunnel was used');
  }
  reader.sub.pause();
  return Tunnel(socket, reader.sub);
}

/// [openTunnel], then TLS to [host] on top (Dart: pause, then secure).
Future<SecureSocket> openSecureTunnel(Uri proxy, String host, int port) async {
  final tunnel = await openTunnel(proxy, host, port);
  return SecureSocket.secure(tunnel.socket, host: host);
}

/// Routes every request of [client] through [proxy] (HTTP CONNECT with
/// credentials, or SOCKS5 with credentials).
void applyProxy(HttpClient client, String proxy) {
  final uri = Uri.parse(proxy);
  final scheme = uri.scheme.toLowerCase();
  if (scheme == 'socks5' || scheme == 'socks5h') {
    // every TikTok endpoint is https: SOCKS5 tunnel, then TLS on top
    client.connectionFactory = (target, proxyHost, proxyPort) {
      if (target.scheme != 'https') {
        throw ArgumentError.value(target.toString(), 'target', 'SOCKS5 is wired for https targets only');
      }
      final port = target.hasPort ? target.port : 443;
      return Future.value(
          ConnectionTask.fromSocket(openSecureTunnel(uri, target.host, port), () {}));
    };
    return;
  }
  if (scheme != 'http' && scheme != 'https') {
    throw ArgumentError.value(proxy, 'proxy',
        'unsupported proxy scheme "$scheme" (http, https, socks5, socks5h)');
  }
  final port = uri.hasPort ? uri.port : (scheme == 'https' ? 443 : 80);
  final auth = uri.userInfo.isEmpty ? '' : '${uri.userInfo}@';
  client.findProxy = (_) => 'PROXY $auth${uri.host}:$port';
}

String _basic(Uri proxy) {
  final parts = proxy.userInfo.split(':');
  final user = Uri.decodeComponent(parts.first);
  final pass = parts.length > 1 ? Uri.decodeComponent(parts.sublist(1).join(':')) : '';
  return base64Encode(utf8.encode('$user:$pass'));
}

Future<void> _httpConnect(
    Socket socket, _Reader reader, Uri proxy, String host, int port) async {
  final req = StringBuffer('CONNECT $host:$port HTTP/1.1\r\nHost: $host:$port\r\n');
  if (proxy.userInfo.isNotEmpty) {
    req.write('Proxy-Authorization: Basic ${_basic(proxy)}\r\n');
  }
  req.write('\r\n');
  socket.write(req.toString());
  await socket.flush();
  final head = await reader.takeHead();
  final status = head.split('\r\n').first;
  if (!RegExp(r'^HTTP/1\.[01] 200').hasMatch(status)) {
    throw SocketException('proxy CONNECT failed: $status');
  }
}

Future<void> _socks5(
    Socket socket, _Reader reader, Uri proxy, String host, int port) async {
  final withAuth = proxy.userInfo.isNotEmpty;
  final method = withAuth ? 0x02 : 0x00;
  socket.add([0x05, 0x01, method]);
  final greeting = await reader.take(2);
  if (greeting[0] != 0x05 || greeting[1] != method) {
    throw SocketException('socks5: proxy refused auth method $method');
  }
  if (withAuth) {
    final parts = proxy.userInfo.split(':');
    final user = utf8.encode(Uri.decodeComponent(parts.first));
    final pass = utf8.encode(
        parts.length > 1 ? Uri.decodeComponent(parts.sublist(1).join(':')) : '');
    socket.add([0x01, user.length, ...user, pass.length, ...pass]);
    final reply = await reader.take(2);
    if (reply[1] != 0x00) throw const SocketException('socks5: authentication failed');
  }
  final name = utf8.encode(host);
  socket.add([0x05, 0x01, 0x00, 0x03, name.length, ...name, port >> 8, port & 0xff]);
  final head = await reader.take(4);
  if (head[1] != 0x00) {
    throw SocketException('socks5: connect to $host:$port failed (reply ${head[1]})');
  }
  final skip = switch (head[3]) {
    0x01 => 4,
    0x04 => 16,
    0x03 => (await reader.take(1))[0],
    _ => throw SocketException('socks5: bad address type ${head[3]}'),
  };
  await reader.take(skip + 2);
}

/// Buffers the socket's single subscription so handshakes can read exact sizes.
class _Reader {
  late final StreamSubscription<Uint8List> sub;
  final buffered = <int>[];
  Completer<void>? _more;
  Object? _error;
  bool _done = false;

  _Reader(Socket socket) {
    sub = socket.listen((chunk) {
      buffered.addAll(chunk);
      _wake();
    }, onError: (Object e) {
      _error = e;
      _wake();
    }, onDone: () {
      _done = true;
      _wake();
    });
  }

  void _wake() {
    final more = _more;
    _more = null;
    more?.complete();
  }

  Future<void> _wait() async {
    if (_error != null) throw _error!;
    if (_done) throw const SocketException('proxy closed the connection');
    _more = Completer<void>();
    await _more!.future;
  }

  Future<Uint8List> take(int n) async {
    while (buffered.length < n) {
      await _wait();
    }
    final out = Uint8List.fromList(buffered.sublist(0, n));
    buffered.removeRange(0, n);
    return out;
  }

  Future<String> takeHead() async {
    while (true) {
      final s = latin1.decode(buffered);
      final idx = s.indexOf('\r\n\r\n');
      if (idx >= 0) {
        buffered.removeRange(0, idx + 4);
        return s.substring(0, idx);
      }
      await _wait();
    }
  }
}
