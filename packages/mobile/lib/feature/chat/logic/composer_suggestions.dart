import 'dart:math';

import 'package:equatable/equatable.dart';

const int _maxSuggestions = 80;

final RegExp _whitespace = RegExp(r'\s');

enum SuggestionKind { skills, files }

class ComposerSuggestion extends Equatable {
  const ComposerSuggestion({
    required this.kind,
    required this.query,
    required this.start,
    required this.end,
  });

  final SuggestionKind kind;
  final String query;
  final int start;
  final int end;

  @override
  List<Object?> get props => [kind, query, start, end];
}

class RankedSuggestion extends Equatable {
  const RankedSuggestion({
    required this.value,
    required this.label,
    this.detail,
    this.badge,
  });

  final String value;
  final String label;
  final String? detail;
  final String? badge;

  @override
  List<Object?> get props => [value, label, detail, badge];
}

abstract class SuggestibleSkill {
  String get name;
  String get displayName;
  String? get description;
  String? get inputHint;
  String? get source;
}

ComposerSuggestion? findComposerSuggestion(String text, [int? cursor]) {
  final caret = max(0, min(cursor ?? text.length, text.length));
  for (var index = caret - 1; index >= 0; index -= 1) {
    final char = text[index];
    if (_whitespace.hasMatch(char)) return null;
    if (char != '/' && char != '@') continue;

    final preceding = index > 0 ? text[index - 1] : null;
    if (preceding != null && !_whitespace.hasMatch(preceding)) continue;
    if (char == '/' && text.substring(0, index).trim().isNotEmpty) return null;

    return ComposerSuggestion(
      kind: char == '/' ? SuggestionKind.skills : SuggestionKind.files,
      query: text.substring(index + 1, caret),
      start: index,
      end: caret,
    );
  }
  return null;
}

String replaceComposerSuggestion(String text, ComposerSuggestion trigger, String value) {
  final inserted = trigger.kind == SuggestionKind.skills ? '/$value' : _quotePath(value);
  final suffix = text.substring(trigger.end);
  final separator = suffix.isNotEmpty && _whitespace.hasMatch(suffix[0]) ? '' : ' ';
  return '${text.substring(0, trigger.start)}$inserted$separator$suffix';
}

List<RankedSuggestion> rankComposerSkills(List<SuggestibleSkill> skills, String query) {
  final needle = query.trim().toLowerCase();
  final scored = <({double score, String name, RankedSuggestion suggestion})>[];

  for (final skill in skills) {
    if (skill.name.isEmpty) continue;
    final scores = <double>[
      ?_score(skill.name, needle, 0),
      ?_score(skill.displayName.isEmpty ? skill.name : skill.displayName, needle, 10),
      if (needle.isNotEmpty) ?_score(skill.description ?? '', needle, 40),
      if (needle.isNotEmpty) ?_score(skill.inputHint ?? '', needle, 50),
    ];
    if (scores.isEmpty) continue;

    final description = _firstLine(skill.description);
    final hint = _firstLine(skill.inputHint);
    scored.add((
      score: scores.reduce(min),
      name: skill.name,
      suggestion: RankedSuggestion(
        value: skill.name,
        label: skill.displayName.isEmpty ? skill.name : skill.displayName,
        detail: description != null && hint != null ? '$description · $hint' : description ?? hint,
        badge: skill.source,
      ),
    ));
  }

  scored.sort((left, right) {
    final byScore = left.score.compareTo(right.score);
    return byScore != 0 ? byScore : left.name.compareTo(right.name);
  });
  return scored.take(_maxSuggestions).map((entry) => entry.suggestion).toList();
}

List<RankedSuggestion> rankComposerFiles(List<String> paths, String query) {
  final needle = query.trim().toLowerCase();
  final scored = <({double score, String path, RankedSuggestion suggestion})>[];

  for (final path in paths) {
    if (path.isEmpty) continue;
    final slash = path.lastIndexOf('/');
    final basename = slash < 0 ? path : path.substring(slash + 1);
    final parent = slash < 0 ? null : path.substring(0, slash);
    final scores = <double>[?_score(basename, needle, 0), ?_score(path, needle, 10)];
    if (scores.isEmpty) continue;

    scored.add((
      score: scores.reduce(min),
      path: path,
      suggestion: RankedSuggestion(value: path, label: basename, detail: parent),
    ));
  }

  scored.sort((left, right) {
    final byScore = left.score.compareTo(right.score);
    if (byScore != 0) return byScore;
    final byLength = left.path.length.compareTo(right.path.length);
    return byLength != 0 ? byLength : left.path.compareTo(right.path);
  });
  return scored.take(_maxSuggestions).map((entry) => entry.suggestion).toList();
}

double? _score(String value, String query, int base) {
  final haystack = value.toLowerCase();
  if (query.isEmpty || haystack == query) return base.toDouble();
  if (haystack.startsWith(query)) return base + 1;
  if (['-', '_', '/', ':', '.'].any((marker) => haystack.contains('$marker$query'))) return base + 2;
  final index = haystack.indexOf(query);
  return index < 0 ? null : base + 3 + min(index, 20) / 100;
}

String _quotePath(String path) => _whitespace.hasMatch(path) ? '"$path"' : path;

String? _firstLine(String? value) {
  final line = value?.split('\n').first.trim();
  return line == null || line.isEmpty ? null : line;
}
