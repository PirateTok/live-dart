import 'package:piratetok_live/piratetok_live.dart';
import 'package:test/test.dart';

void main() {
  test('combo, streak and diamond helpers', () {
    final combo = <String, dynamic>{
      'gift': {'type': 1, 'diamondCount': 5},
      'repeatCount': 7,
      'repeatEnd': 0,
    };
    expect(isComboGift(combo), isTrue);
    expect(isStreakOver(combo), isFalse);
    expect(diamondTotal(combo), 35);
    combo['repeatEnd'] = 1;
    expect(isStreakOver(combo), isTrue);

    final single = <String, dynamic>{
      'gift': {'type': 2, 'diamondCount': 100},
    };
    expect(isComboGift(single), isFalse);
    expect(isStreakOver(single), isTrue);
    expect(diamondTotal(single), 100);
    expect(diamondTotal({}), 0);
  });
}
