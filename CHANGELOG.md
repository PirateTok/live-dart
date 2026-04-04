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
