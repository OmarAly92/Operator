import 'package:equatable/equatable.dart';

class MatchScore extends Equatable {
  const MatchScore({required this.tier, required this.offset, this.spread});

  final int tier;
  final int offset;
  final int? spread;

  @override
  List<Object?> get props => [tier, offset, spread];
}

class FuzzyPolicy extends Equatable {
  const FuzzyPolicy({required this.maxEdits, required this.transpositionsOnly});

  final int maxEdits;
  final bool transpositionsOnly;

  @override
  List<Object?> get props => [maxEdits, transpositionsOnly];
}

class MatchRange extends Equatable {
  const MatchRange({required this.start, required this.length});

  final int start;
  final int length;

  @override
  List<Object?> get props => [start, length];
}

sealed class TextMatch {
  static const int tierExact = 0;
  static const int tierWholeWord = 1;
  static const int tierPrefix = 2;
  static const int tierWordStart = 3;
  static const int tierSubstring = 4;
  static const int tierSubsequence = 5;
  static const int tierFuzzy = 6;

  static FuzzyPolicy? fuzzyPolicyForToken(String token) {
    if (token.length <= 3) return null;
    if (token.length == 4) return const FuzzyPolicy(maxEdits: 1, transpositionsOnly: true);
    if (token.length <= 7) return const FuzzyPolicy(maxEdits: 1, transpositionsOnly: false);
    return const FuzzyPolicy(maxEdits: 2, transpositionsOnly: false);
  }

  static MatchScore? score(String query, String text, {FuzzyPolicy? fuzzy, bool subsequence = true}) {
    if (query.isEmpty) return const MatchScore(tier: tierExact, offset: 0);
    final q = query.toLowerCase();
    final t = text.toLowerCase();
    if (t == q) return const MatchScore(tier: tierExact, offset: 0);
    final exact = _scoreSubstring(q, t) ?? (subsequence ? _scoreSubsequence(q, t) : null);
    if (exact != null) return exact;
    return fuzzy == null ? null : _scoreFuzzy(q, t, fuzzy);
  }

  static MatchScore? _scoreSubstring(String query, String text) {
    MatchScore? best;
    var pos = 0;
    while (pos <= text.length - query.length) {
      final found = text.indexOf(query, pos);
      if (found == -1) break;
      final startsAtBoundary = found == 0 || _isWordBoundary(text[found - 1]);
      final endsAtBoundary = found + query.length >= text.length || _isWordBoundary(text[found + query.length]);
      final tier = startsAtBoundary && endsAtBoundary
          ? tierWholeWord
          : found == 0
          ? tierPrefix
          : startsAtBoundary
          ? tierWordStart
          : tierSubstring;
      final score = MatchScore(tier: tier, offset: found);
      if (best == null || compare(score, best) < 0) best = score;
      pos = found + 1;
    }
    return best;
  }

  static bool _isWordBoundary(String character) => !RegExp('[a-z0-9]').hasMatch(character);

  static MatchScore? _scoreSubsequence(String query, String text) {
    var queryIndex = 0;
    var firstIndex = -1;
    var lastIndex = -1;
    for (var textIndex = 0; textIndex < text.length && queryIndex < query.length; textIndex += 1) {
      if (text[textIndex] != query[queryIndex]) continue;
      if (firstIndex == -1) firstIndex = textIndex;
      lastIndex = textIndex;
      queryIndex += 1;
    }
    if (queryIndex != query.length || firstIndex == -1) return null;
    return MatchScore(tier: tierSubsequence, offset: firstIndex, spread: lastIndex - firstIndex + 1);
  }

  static int? _boundedEditDistance(String query, String word, int budget) {
    if ((query.length - word.length).abs() > budget) return null;
    var twoRowsBack = <int>[];
    var previousRow = List<int>.generate(word.length + 1, (index) => index);
    for (var queryIndex = 1; queryIndex <= query.length; queryIndex += 1) {
      final currentRow = <int>[queryIndex];
      var rowBest = queryIndex;
      for (var wordIndex = 1; wordIndex <= word.length; wordIndex += 1) {
        final substitutionCost = query[queryIndex - 1] == word[wordIndex - 1] ? 0 : 1;
        var cost = [
          currentRow[wordIndex - 1] + 1,
          previousRow[wordIndex] + 1,
          previousRow[wordIndex - 1] + substitutionCost,
        ].reduce((left, right) => left < right ? left : right);
        final isTransposition = queryIndex > 1 && wordIndex > 1 && query[queryIndex - 1] == word[wordIndex - 2] && query[queryIndex - 2] == word[wordIndex - 1];
        if (isTransposition) {
          final transpositionCost = twoRowsBack[wordIndex - 2] + 1;
          if (transpositionCost < cost) cost = transpositionCost;
        }
        currentRow.add(cost);
        if (cost < rowBest) rowBest = cost;
      }
      if (rowBest > budget) return null;
      twoRowsBack = previousRow;
      previousRow = currentRow;
    }
    final distance = previousRow[word.length];
    return distance <= budget ? distance : null;
  }

  static bool _isAdjacentTransposition(String query, String word) {
    if (query.length != word.length) return false;
    var index = 0;
    while (index < query.length && query[index] == word[index]) {
      index += 1;
    }
    return index < query.length - 1 &&
        query[index] == word[index + 1] &&
        query[index + 1] == word[index] &&
        query.substring(index + 2) == word.substring(index + 2);
  }

  static MatchScore? _scoreFuzzy(String query, String text, FuzzyPolicy policy) {
    if (policy.maxEdits <= 0 || query.length <= policy.maxEdits) return null;
    MatchScore? best;
    final pattern = RegExp('[a-z0-9]+');
    for (final word in pattern.allMatches(text)) {
      final value = word.group(0)!;
      final candidates = <String>{value, value.substring(0, value.length < query.length ? value.length : query.length), value.substring(0, value.length < query.length + policy.maxEdits ? value.length : query.length + policy.maxEdits)};
      for (final candidate in candidates) {
        final distance = policy.transpositionsOnly
            ? (_isAdjacentTransposition(query, candidate) ? 1 : null)
            : _boundedEditDistance(query, candidate, policy.maxEdits);
        if (distance == null) continue;
        final score = MatchScore(tier: tierFuzzy, offset: word.start, spread: distance);
        if (best == null || compare(score, best) < 0) best = score;
      }
    }
    return best;
  }

  static List<MatchRange> ranges(String query, String text, MatchScore score) {
    if (query.isEmpty) return const [];
    final q = query.toLowerCase();
    final t = text.toLowerCase();
    if (score.tier == tierExact) return [MatchRange(start: 0, length: text.length)];
    if (score.tier == tierFuzzy) return [_wordRangeAt(t, score.offset)];
    if (score.tier == tierSubsequence) {
      final indices = <int>[];
      var queryIndex = 0;
      for (var textIndex = 0; textIndex < t.length && queryIndex < q.length; textIndex += 1) {
        if (t[textIndex] != q[queryIndex]) continue;
        indices.add(textIndex);
        queryIndex += 1;
      }
      return _mergeAdjacentRanges(indices);
    }
    return [MatchRange(start: score.offset, length: q.length)];
  }

  static MatchRange _wordRangeAt(String text, int offset) {
    var end = offset;
    while (end < text.length && RegExp('[a-z0-9]').hasMatch(text[end])) {
      end += 1;
    }
    return MatchRange(start: offset, length: (end - offset) < 1 ? 1 : end - offset);
  }

  static List<MatchRange> _mergeAdjacentRanges(List<int> indices) {
    final ranges = <MatchRange>[];
    for (final index in indices) {
      if (ranges.isNotEmpty && ranges.last.start + ranges.last.length == index) {
        final last = ranges.removeLast();
        ranges.add(MatchRange(start: last.start, length: last.length + 1));
      } else {
        ranges.add(MatchRange(start: index, length: 1));
      }
    }
    return ranges;
  }

  static int compare(MatchScore a, MatchScore b) {
    if (a.tier != b.tier) return a.tier - b.tier;
    if (a.offset != b.offset) return a.offset - b.offset;
    return (a.spread ?? 0) - (b.spread ?? 0);
  }

  static List<String> tokenize(String query) => query.trim().toLowerCase().split(RegExp(r'\s+')).where((token) => token.isNotEmpty).toList();

  static MatchScore? scoreTextFields(String query, List<String> fields, {bool typoTolerant = false, bool subsequence = true}) {
    final tokens = tokenize(query);
    if (tokens.isEmpty) return const MatchScore(tier: tierExact, offset: 0, spread: 0);
    var aggregate = const MatchScore(tier: tierExact, offset: 0, spread: 0);
    for (final token in tokens) {
      final fuzzy = typoTolerant ? fuzzyPolicyForToken(token) : null;
      MatchScore? best;
      for (final field in fields) {
        final score = TextMatch.score(token, field, fuzzy: fuzzy, subsequence: subsequence);
        if (score != null && (best == null || compare(score, best) < 0)) best = score;
      }
      if (best == null) return null;
      aggregate = MatchScore(
        tier: aggregate.tier + best.tier,
        offset: aggregate.offset + best.offset,
        spread: (aggregate.spread ?? 0) + (best.spread ?? token.length),
      );
    }
    return aggregate;
  }
}
