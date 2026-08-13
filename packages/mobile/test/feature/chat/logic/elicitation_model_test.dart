import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/feature/chat/logic/elicitation_model.dart';

class _Property implements ElicitationProperty {
  const _Property({
    this.type,
    this.title,
    this.description,
    this.defaultValue,
    this.enumValues,
    this.oneOf,
    this.itemsAnyOf,
    this.minimum,
    this.maximum,
    this.minLength,
    this.maxLength,
  });

  @override
  final String? type;
  @override
  final String? title;
  @override
  final String? description;
  @override
  final dynamic defaultValue;
  @override
  final List<dynamic>? enumValues;
  @override
  final List<InputChoice>? oneOf;
  @override
  final List<InputChoice>? itemsAnyOf;
  @override
  final num? minimum;
  @override
  final num? maximum;
  @override
  final int? minLength;
  @override
  final int? maxLength;
}

void main() {
  group('mobile Chat elicitation model', () {
    test('opens only explicit web URLs', () {
      expect(safeHttpUrl('https://example.com/login')?.host, 'example.com');
      expect(safeHttpUrl('http://example.com'), isNotNull);
      expect(safeHttpUrl('javascript:alert(1)'), isNull);
      expect(safeHttpUrl('file:///etc/passwd'), isNull);
      expect(safeHttpUrl('not a URL'), isNull);
      expect(safeHttpUrl(7), isNull);
    });

    test('validates required, string, number and integer constraints', () {
      expect(
        missingRequiredInputs(
          ['name', 'scopes'],
          {'name': '', 'scopes': <dynamic>[]},
        ),
        ['name', 'scopes'],
      );
      expect(missingRequiredInputs(['name'], {'name': 'ok'}), isEmpty);
      expect(
        validateInput(const _Property(type: 'string', minLength: 3), 'ab'),
        contains('at least 3'),
      );
      expect(
        validateInput(const _Property(type: 'string', maxLength: 2), 'abc'),
        contains('at most 2'),
      );
      expect(
        validateInput(const _Property(type: 'integer'), 1.5),
        contains('whole number'),
      );
      expect(
        validateInput(
          const _Property(type: 'number', minimum: 2, maximum: 4),
          1,
        ),
        contains('at least 2'),
      );
      expect(
        validateInput(
          const _Property(type: 'number', minimum: 2, maximum: 4),
          5,
        ),
        contains('at most 4'),
      );
      expect(
        validateInput(
          const _Property(type: 'number', minimum: 2, maximum: 4),
          3,
        ),
        isNull,
      );
    });

    test('normalizes provider choices and multi-select toggles', () {
      expect(
        inputOptions(
          const _Property(
            type: 'string',
            oneOf: [
              InputChoice(
                value: 'fast',
                label: 'Fast',
                description: 'Less context',
              ),
            ],
          ),
        ),
        [
          const InputChoice(
            value: 'fast',
            label: 'Fast',
            description: 'Less context',
          ),
        ],
      );
      expect(
        inputOptions(
          const _Property(
            type: 'array',
            title: 'Scopes',
            description: 'Select access scopes',
            itemsAnyOf: [InputChoice(value: 'read', label: 'Read')],
          ),
        ),
        [const InputChoice(value: 'read', label: 'Read')],
      );
      expect(
        inputOptions(
          const _Property(type: 'string', enumValues: ['read', 7, 'write']),
        ),
        [
          const InputChoice(value: 'read', label: 'read'),
          const InputChoice(value: 'write', label: 'write'),
        ],
      );
      expect(toggleInputValue(['read'], 'write'), ['read', 'write']);
      expect(toggleInputValue(['read', 'write'], 'read'), ['write']);
    });

    test('seeds each field with a value its control can render', () {
      expect(initialInputValue(const _Property(type: 'array')), <dynamic>[]);
      expect(initialInputValue(const _Property(type: 'boolean')), false);
      expect(initialInputValue(const _Property(type: 'string')), '');
      expect(
        initialInputValue(const _Property(type: 'boolean', defaultValue: true)),
        true,
      );
    });

    test('humanizes a schema key for a label', () {
      expect(humanizeInputName('api_token'), 'Api token');
    });
  });
}
