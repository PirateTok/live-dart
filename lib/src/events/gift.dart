// Helpers over a decoded `gift` event's data.

Map<String, dynamic> _details(Map<String, dynamic> data) {
  final g = data['gift'];
  return g is Map<String, dynamic> ? g : const {};
}

int _int(Object? v) => v is int ? v : 0;

/// Combo gifts (gift type 1) send several events with a running repeatCount until repeatEnd.
bool isComboGift(Map<String, dynamic> data) => _int(_details(data)['type']) == 1;

/// Always true for non-combo gifts; true on repeatEnd == 1 for combos.
bool isStreakOver(Map<String, dynamic> data) =>
    !isComboGift(data) || _int(data['repeatEnd']) == 1;

/// Diamonds per gift × repeatCount (at least 1).
int diamondTotal(Map<String, dynamic> data) {
  final count = _int(data['repeatCount']);
  return _int(_details(data)['diamondCount']) * (count < 1 ? 1 : count);
}
