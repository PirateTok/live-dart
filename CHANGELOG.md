## 0.2.0

- ttwid fetch retries up to 8× (750 ms apart) when TikTok omits the cookie; transport errors still propagate.
- Reconnect loop: a ttwid or WSS failure is a failed attempt (`reconnecting`, backoff) instead of aborting `connect()`.
- ttwid + UA are reused across reconnects (same UA for ttwid and WSS) and rotated only on DEVICE_BLOCKED
  or a connection that died within 30 s; `maxRetries` counts consecutive failures, reset after a 30 s healthy session.
- `heartbeatInterval()` builder (default 10 s), also fed into the `heartbeat_duration` WSS URL param.
- `RoomIdResult.anchorId`; `RoomInfo.rawJson`.
- `roomUserSeq` decodes `ranksList`, `seatsList`, `anonymous`; `total` renamed `viewerCount`. New `topViewers(data)`.
- Gift helpers `isComboGift(data)`, `isStreakOver(data)`, `diamondTotal(data)`.
- `fetchRoomAudience` (full viewer roster, login-gated) + `SessionRequiredError` / `InvalidResponseError`; `audience` example.
- `unknown` events carry the raw `payload` bytes.
- `.compress()` builder (from the unreleased tree).
- Replay tests fail on missing testdata instead of passing silently.
- Homepage: https://piratetok.rosint.org

## 0.1.5

- Add `.language()` and `.region()` builder methods for locale override
- Use detected system locale everywhere (HTTP, WSS, SIGI) with en-US as fallback only
- Thread locale from client config through all transports

## 0.1.4

- Fix RoomVerifyMessage proto name prefix
- Add WSS CONNECT tunnel proxy support
- Add gift_streak example

## 0.1.3

- Publish to pub.dev

## 0.1.0

- Initial release
- 64 decoded event types (Tier A + B), unknown passthrough for the rest
- Raw WebSocket implementation (RFC 6455) -- zero dependency on `dart:io` WebSocket
- Hand-written protobuf codec (reader/writer) -- no codegen, no .proto files
- Auto-reconnection with stale detection, exponential backoff
- DEVICE_BLOCKED self-healing (fresh ttwid + random UA on retry)
- User agent rotation pool (6 UAs, system timezone detection)
- Sub-routed convenience events (follow, share, join, liveEnded)
- Enriched User proto (badges, gifter level, fan club, follow info)
- CDN selection (EU/US/Global)
- Room info fetch with 18+ cookie support
