<p align="center">
  <img src="https://raw.githubusercontent.com/PirateTok/.github/main/profile/assets/og-banner-v2.png" alt="PirateTok" width="640" />
</p>

# piratetok_live

Connect to any TikTok Live stream and receive real-time events in Dart. No signing server, no API keys, zero dependencies.

```dart
import 'dart:io';
import 'package:piratetok_live/piratetok_live.dart';

void main() async {
  // Create client — zero dependencies, raw RFC 6455 WebSocket under the hood
  final client = TikTokLiveClient("username_here");

  // Register event handlers — data arrives as decoded protobuf maps
  client.on(EventType.chat, (evt) {
    final nick = evt.data?['user']?['uniqueId'] ?? '?';
    print('[chat] $nick: ${evt.data?['content']}');
  });

  client.on(EventType.gift, (evt) {
    final nick = evt.data?['user']?['uniqueId'] ?? '?';
    final gift = evt.data?['gift'] as Map<String, dynamic>?;
    final diamonds = gift?['diamondCount'] ?? 0;
    print('[gift] $nick sent ${gift?['name']} x${evt.data?['repeatCount']} ($diamonds diamonds)');
  });

  client.on(EventType.like, (evt) {
    final nick = evt.data?['user']?['uniqueId'] ?? '?';
    print('[like] $nick (${evt.data?['totalLikes']} total)');
  });

  // Connect — handles auth, room resolution, WSS, heartbeat, reconnection
  await client.connect();
  exit(0);
}
```

## Install

```
dart pub add piratetok_live
```

Requires Dart SDK >= 3.0.0. No external dependencies.

## Other languages

| Language | Install | Repo |
|:---------|:--------|:-----|
| **Rust** | `cargo add piratetok-live-rs` | [live-rs](https://github.com/PirateTok/live-rs) |
| **Go** | `go get github.com/PirateTok/live-go` | [live-go](https://github.com/PirateTok/live-go) |
| **Python** | `pip install piratetok-live-py` | [live-py](https://github.com/PirateTok/live-py) |
| **JavaScript** | `npm install piratetok-live-js` | [live-js](https://github.com/PirateTok/live-js) |
| **C#** | `dotnet add package PirateTok.Live` | [live-cs](https://github.com/PirateTok/live-cs) |
| **Java** | `com.piratetok:live` | [live-java](https://github.com/PirateTok/live-java) |
| **Lua** | `luarocks install piratetok-live-lua` | [live-lua](https://github.com/PirateTok/live-lua) |
| **Elixir** | `{:piratetok_live, "~> 0.1"}` | [live-ex](https://github.com/PirateTok/live-ex) |
| **C** | `#include "piratetok.h"` | [live-c](https://github.com/PirateTok/live-c) |
| **PowerShell** | `Install-Module PirateTok.Live` | [live-ps1](https://github.com/PirateTok/live-ps1) |
| **Shell** | `bpkg install PirateTok/live-sh` | [live-sh](https://github.com/PirateTok/live-sh) |

## Features

- **Zero signing dependency** -- no API keys, no signing server, no external auth
- **Zero external dependencies** -- only `dart:io`, `dart:async`, `dart:convert`, `dart:typed_data`
- **64 decoded event types** -- hand-written protobuf codec, no codegen
- **Raw WebSocket** -- custom RFC 6455 implementation, bypasses `dart:io` WebSocket quirks
- **Auto-reconnection** -- stale detection, exponential backoff, self-healing auth
- **DEVICE_BLOCKED self-healing** -- 2s retry with fresh credentials + random UA rotation
- **Enriched User data** -- badges, gifter level, moderator status, follow info, fan club
- **Sub-routed convenience events** -- `follow`, `share`, `join`, `liveEnded`

## Configuration

```dart
final client = TikTokLiveClient("username_here")
    .cdnEu()                             // EU / US / Global (default)
    .timeout(Duration(seconds: 15))
    .maxRetries(10)                       // default 5
    .staleTimeout(Duration(seconds: 90))  // default 60s
    .userAgent("custom UA string")        // default: random from pool
    .proxy("socks5://127.0.0.1:1080");
```

## Room info (optional, separate call)

```dart
import 'package:piratetok_live/piratetok_live.dart';

// Check if user is live
final result = await checkOnline("username_here");
print('room_id: ${result.roomId}');

// Fetch room metadata (title, viewers, stream URLs)
final info = await fetchRoomInfo(result.roomId);

// 18+ rooms -- pass session cookies from browser DevTools
final info18 = await fetchRoomInfo(result.roomId,
    cookies: "sessionid=abc; sid_tt=abc");
```

## How it works

1. Resolves username to room ID via TikTok JSON API
2. Authenticates and opens a direct WSS connection (raw RFC 6455 socket)
3. Sends protobuf heartbeats every 10s to keep alive
4. Decodes protobuf event stream into typed maps
5. Auto-reconnects on stale/dropped connections with fresh credentials + UA

All protobuf encoding/decoding is hand-written -- no `.proto` files, no codegen, no build-time tooling.

## Examples

```bash
dart run example/basic_chat.dart <username>       # connect + print chat events
dart run example/online_check.dart <username>     # check if user is live
dart run example/stream_info.dart <username>      # fetch room metadata + stream URLs
```

## License

0BSD
