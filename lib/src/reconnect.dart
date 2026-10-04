import 'dart:async';

import 'events/types.dart';

const healthySession = Duration(seconds: 30);

/// ttwid + UA pair, reused across reconnects until rotated.
typedef LiveSession = ({String ttwid, String ua});

/// The reconnect loop with its side effects injected: [fresh] fetches ttwid +
/// UA (null = failed), [run] runs one WSS session, [delay] waits between
/// attempts (completes early once [stop] does). ttwid + UA are reused and
/// rotate only on DEVICE_BLOCKED, a ttwid failure, or a connection that died
/// young. Emits `reconnecting` per retry and `disconnected` exactly once, last.
Future<void> runReconnectLoop({
  required String roomId,
  required int maxRetries,
  required Future<LiveSession?> Function() fresh,
  required Future<SessionExit> Function(LiveSession) run,
  required Future<void> Function(Duration) delay,
  required void Function(TikTokEvent) emit,
  required Completer<void> stop,
}) async {
  final budget = ReconnectBudget(maxRetries);
  LiveSession? held;
  while (!stop.isCompleted) {
    held ??= await fresh();
    final session = held;
    var exit = SessionExit.noTtwid;
    var lived = Duration.zero;
    if (session != null) {
      final started = DateTime.now();
      exit = await run(session);
      lived = DateTime.now().difference(started);
    }
    if (stop.isCompleted) break;

    final judgement = judge(exit, lived);
    if (judgement.rotate) held = null;
    final verdict = budget.record(judgement.end);
    if (verdict.giveUp) break;

    emit(TikTokEvent(
      EventType.reconnecting,
      {
        'attempt': verdict.attempt,
        'max_retries': maxRetries,
        'delay': verdict.delay.inSeconds,
      },
      roomId,
    ));
    await Future.any([delay(verdict.delay), stop.future]);
  }
  emit(TikTokEvent(EventType.disconnected, null, roomId));
}
const deviceBlockedDelay = Duration(seconds: 2);
const maxBackoff = Duration(seconds: 30);

enum SessionExit { closed, deviceBlocked, errored, noTtwid }

enum AttemptEnd { healthy, failed, blocked }

/// How an attempt ended and whether to drop ttwid + UA.
typedef Judgement = ({AttemptEnd end, bool rotate});

/// [giveUp] means stop reconnecting; otherwise wait [delay] before [attempt].
typedef Verdict = ({bool giveUp, int attempt, Duration delay});

Judgement judge(SessionExit exit, Duration lived) {
  final healthy = lived >= healthySession;
  final end = healthy ? AttemptEnd.healthy : AttemptEnd.failed;
  return switch (exit) {
    SessionExit.closed => (end: end, rotate: false),
    SessionExit.deviceBlocked => (end: AttemptEnd.blocked, rotate: true),
    SessionExit.errored => (end: end, rotate: !healthy),
    SessionExit.noTtwid => (end: AttemptEnd.failed, rotate: true),
  };
}

/// Counts consecutive failed attempts. A healthy session resets the count, so
/// long-lived streams don't die after max_retries lifetime blips.
class ReconnectBudget {
  final int maxRetries;
  int _attempt = 0;

  ReconnectBudget(this.maxRetries);

  Verdict record(AttemptEnd end) {
    _attempt = end == AttemptEnd.healthy ? 1 : _attempt + 1;
    if (_attempt > maxRetries) {
      return (giveUp: true, attempt: _attempt, delay: Duration.zero);
    }
    final delay =
        end == AttemptEnd.blocked ? deviceBlockedDelay : backoff(_attempt);
    return (giveUp: false, attempt: _attempt, delay: delay);
  }
}

Duration backoff(int attempt) =>
    attempt >= 5 ? maxBackoff : Duration(seconds: 1 << attempt);
