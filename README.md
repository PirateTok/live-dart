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
    print('[like] $nick x${evt.data?['count']} (${evt.data?['total']} total)');
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
    .heartbeatInterval(Duration(seconds: 10)) // default 10s, also sent as heartbeat_duration
    .maxRetries(10)                       // consecutive failures, default 5 (reset after a 30s healthy session)
    .staleTimeout(Duration(seconds: 90))  // default 60s
    .userAgent("custom UA string")        // default: random from pool
    .cookies("sessionid=xxx; sid_tt=xxx") // only for 18+ room info
    .language("en")                       // default: system locale
    .region("US")                         // default: system locale
    .compress(false)                      // disable gzip for WSS payloads (default true)
    .proxy("socks5://127.0.0.1:1080");
```

## Room info (optional, separate call)

```dart
import 'package:piratetok_live/piratetok_live.dart';

// Check if user is live
final result = await checkOnline("username_here");
print('room_id: ${result.roomId} anchor_id: ${result.anchorId}');

// Fetch room metadata (title, viewers, stream URLs)
final info = await fetchRoomInfo(result.roomId);

// 18+ rooms -- pass session cookies from browser DevTools
final info18 = await fetchRoomInfo(result.roomId,
    cookies: "sessionid=abc; sid_tt=abc");
```

## Viewers

Every `roomUserSeq` event carries the counters and the top-viewers box — no cookies needed:

```dart
client.on(EventType.roomUserSeq, (evt) {
  evt.data!['viewerCount']; // in the room right now (goes up and down)
  evt.data!['totalUser'];   // unique viewers over the whole stream (only grows)
  for (final c in topViewers(evt.data!)) { // usually top 3, sorted by rank
    print('#${c['rank']} ${(c['user'] as Map)['nickname']} (${c['score']})');
  }
});
```

The full audience roster is a separate call. TikTok gates it behind a login, so session cookies are
**required for this call only** — without them it throws `SessionRequiredError`:

```dart
final room = await checkOnline("username_here");
final audience = await fetchRoomAudience(room.roomId,
    anchorId: room.anchorId, cookies: "sessionid=abc; sid_tt=abc");
// audience.total, audience.anonymous, audience.viewers (rank, score, username, followerCount, ...)
```

Omit `anchorId` to resolve it from room info (one extra request).

## Helpers

Stateful helpers for common patterns. Exported from the main package, never imported by the core pipeline.

### GiftStreakTracker

Computes per-event gift deltas from TikTok's running totals. Combo gifts fire multiple events during a streak with cumulative `repeatCount` values -- this helper tracks active streaks and gives you the delta.

```dart
final tracker = GiftStreakTracker();

client.on(EventType.gift, (evt) {
  final e = tracker.process(evt.data!);
  if (e.isFinal) {
    print('streak done: ${e.totalGiftCount} gifts, ${e.totalDiamondCount} diamonds');
  } else if (e.eventGiftCount > 0) {
    print('ongoing: +${e.eventGiftCount} (+${e.eventDiamondCount} diamonds)');
  }
});
```

### LikeAccumulator

Monotonizes TikTok's inconsistent `total` field on like events. Different server shards send stale values causing backwards jumps -- this helper accumulates from the reliable per-event `count` field.

```dart
final likes = LikeAccumulator();

client.on(EventType.like, (evt) {
  final s = likes.process(evt.data!);
  print('${s.accumulatedCount} likes accumulated (server says ${s.totalLikeCount})');
});
```

### ProfileCache

Wraps sigi profile scraping with TTL cache and automatic ttwid management. Fetches HD avatars, follower counts, bio, verified status.

```dart
final cache = ProfileCache(ttlMs: 300000); // 5 min TTL (default)
final profile = await cache.fetch('username');
print('${profile.nickname} — ${profile.followerCount} followers');
```

## How it works

1. Resolves username to room ID via TikTok JSON API
2. Fetches a ttwid cookie (retried up to 8× — TikTok only sets it intermittently) and opens a direct WSS connection (raw RFC 6455 socket)
3. Sends protobuf heartbeats every `heartbeatInterval` (10s) to keep alive
4. Decodes protobuf event stream into typed maps
5. Auto-reconnects on stale/dropped connections, reusing ttwid + UA; both rotate only on DEVICE_BLOCKED or a connection that died within 30s
6. `connect()` runs the whole session — its future completes after the final disconnect; `EventType.connected` fires once the room is resolved

All protobuf encoding/decoding is hand-written -- no `.proto` files, no codegen, no build-time tooling.

## Examples

```bash
dart run example/basic_chat.dart <username>        # connect + print chat events
dart run example/online_check.dart <username>      # check if user is live
dart run example/stream_info.dart <username>       # fetch room metadata + stream URLs
dart run example/gift_streak.dart <username>       # gift combo tracking with diamond totals
dart run example/profile_lookup.dart [username]    # fetch profile metadata + avatars (cached)
dart run example/audience.dart <username> "sessionid=...; sid_tt=..."  # full viewer roster (login required)
```

## Replay testing

Deterministic cross-lib validation against binary WSS captures. Requires testdata from a separate repo:

```bash
git clone https://github.com/PirateTok/live-testdata testdata
dart test
```

Replay tests fail if testdata is not found — they never pass on missing data. Set `PIRATETOK_TESTDATA` to point to a custom location.
Offline unit tests (ttwid retry against a local responder, reconnect budget, top viewers, audience parsing) need no network.

## License

0BSD
