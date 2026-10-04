/// The top-viewers box next to the viewer counter (usually the top 3 ranked by
/// contribution score), from a `roomUserSeq` event's data. Entries without a
/// decoded user are skipped; the rest come back sorted by rank. No cookies needed.
///
/// Each entry is a contributor map: `score`, `user`, `rank`, `delta`.
List<Map<String, dynamic>> topViewers(Map<String, dynamic> data) {
  final ranks = data['ranksList'];
  final top = <Map<String, dynamic>>[
    if (ranks is List)
      for (final c in ranks)
        if (c is Map<String, dynamic> && c['user'] != null) c,
  ];
  top.sort((a, b) => (a['rank'] as int).compareTo(b['rank'] as int));
  return top;
}
