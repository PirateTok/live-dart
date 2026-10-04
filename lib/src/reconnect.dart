const healthySession = Duration(seconds: 30);
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
