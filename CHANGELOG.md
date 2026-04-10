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
