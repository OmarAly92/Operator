import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/feature/chat/logic/composer_suggestions.dart';

class _Skill implements SuggestibleSkill {
  const _Skill({
    required this.name,
    required this.displayName,
    this.description,
    this.inputHint,
    this.source,
  });

  @override
  final String name;
  @override
  final String displayName;
  @override
  final String? description;
  @override
  final String? inputHint;
  @override
  final String? source;
}

void main() {
  group('mobile Chat composer suggestions', () {
    test('finds slash skills and @ files at token boundaries', () {
      final skill = findComposerSuggestion('/rev')!;
      expect(skill.kind, SuggestionKind.skills);
      expect(skill.query, 'rev');
      expect(skill.start, 0);

      final file = findComposerSuggestion('inspect @src/app')!;
      expect(file.kind, SuggestionKind.files);
      expect(file.query, 'src/app');

      expect(findComposerSuggestion('https://opr.dev'), isNull);
      expect(findComposerSuggestion('please /review'), isNull);
      expect(findComposerSuggestion('email@example.com'), isNull);
      expect(findComposerSuggestion('done '), isNull);
    });

    test('replaces only the active token', () {
      const text = 'please inspect @src/ap now';
      final trigger = findComposerSuggestion(text, 'please inspect @src/ap'.length)!;
      expect(
        replaceComposerSuggestion(text, trigger, 'src/app.ts'),
        'please inspect src/app.ts now',
      );
    });

    test('quotes paths with spaces and keeps the slash for provider skills', () {
      expect(
        replaceComposerSuggestion(
          'open @my',
          findComposerSuggestion('open @my')!,
          'my notes/todo.md',
        ),
        'open "my notes/todo.md" ',
      );
      expect(
        replaceComposerSuggestion('/rev', findComposerSuggestion('/rev')!, 'review'),
        '/review ',
      );
    });

    test('ranks names and basenames ahead of descriptions and deep paths', () {
      const skills = [
        _Skill(name: 'code-review', displayName: 'Code review', description: 'Review a change'),
        _Skill(name: 'review', displayName: 'Review', description: 'Inspect code'),
      ];
      expect(
        rankComposerSkills(skills, 'rev').map((item) => item.value).toList(),
        ['review', 'code-review'],
      );
      expect(
        rankComposerFiles(['deep/src/app.ts', 'app.ts', 'docs/application.md'], 'app')
            .map((item) => item.value)
            .toList(),
        ['app.ts', 'deep/src/app.ts', 'docs/application.md'],
      );
    });

    test('carries the detail and badge the picker renders', () {
      const skills = [
        _Skill(
          name: 'review',
          displayName: 'Review',
          description: 'Inspect code\nsecond line',
          inputHint: 'a path',
          source: 'plugin',
        ),
      ];
      final ranked = rankComposerSkills(skills, '').single;
      expect(ranked.label, 'Review');
      expect(ranked.detail, 'Inspect code · a path');
      expect(ranked.badge, 'plugin');
      expect(rankComposerFiles(['src/app.ts'], '').single.detail, 'src');
    });
  });
}
