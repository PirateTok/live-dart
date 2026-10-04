import 'package:piratetok_live/src/reconnect.dart';
import 'package:test/test.dart';

const _short = Duration(seconds: 3);
const _long = Duration(seconds: 45);

void main() {
  test('consecutive failures accumulate until give up', () {
    final b = ReconnectBudget(3);
    expect(b.record(AttemptEnd.failed), (giveUp: false, attempt: 1, delay: const Duration(seconds: 2)));
    expect(b.record(AttemptEnd.failed), (giveUp: false, attempt: 2, delay: const Duration(seconds: 4)));
    expect(b.record(AttemptEnd.failed), (giveUp: false, attempt: 3, delay: const Duration(seconds: 8)));
    final last = b.record(AttemptEnd.failed);
    expect(last.giveUp, isTrue);
    expect(last.attempt, 4);
  });

  test('healthy session resets the count', () {
    final b = ReconnectBudget(3);
    b.record(AttemptEnd.failed);
    b.record(AttemptEnd.failed);
    b.record(AttemptEnd.failed);
    final healthy = b.record(AttemptEnd.healthy);
    expect(healthy.giveUp, isFalse);
    expect(healthy.attempt, 1);
    for (var i = 0; i < 20; i++) {
      expect(b.record(AttemptEnd.failed).giveUp, isFalse);
      expect(b.record(AttemptEnd.healthy).giveUp, isFalse);
    }
  });

  test('blocked uses short delay and still counts', () {
    final b = ReconnectBudget(2);
    expect(b.record(AttemptEnd.blocked).delay, deviceBlockedDelay);
    b.record(AttemptEnd.blocked);
    expect(b.record(AttemptEnd.blocked).giveUp, isTrue);
  });

  test('backoff caps at 30s', () {
    expect(backoff(4), const Duration(seconds: 16));
    expect(backoff(5), maxBackoff);
    expect(backoff(1 << 30), maxBackoff);
  });

  test('rotation rules', () {
    expect(judge(SessionExit.deviceBlocked, _long), (end: AttemptEnd.blocked, rotate: true));
    expect(judge(SessionExit.noTtwid, Duration.zero), (end: AttemptEnd.failed, rotate: true));
    expect(judge(SessionExit.errored, _short), (end: AttemptEnd.failed, rotate: true));
    expect(judge(SessionExit.errored, _long), (end: AttemptEnd.healthy, rotate: false));
    expect(judge(SessionExit.closed, _short), (end: AttemptEnd.failed, rotate: false));
    expect(judge(SessionExit.closed, _long), (end: AttemptEnd.healthy, rotate: false));
  });
}
