import 'dart:math' as math;

typedef _Value = List<double>;

class GlslFunction {
  GlslFunction._(this.name, this.parameters, this.statements);

  factory GlslFunction.parse(String source, String name) {
    final code = source.split('\n').map((line) => line.replaceFirst(RegExp(r'//.*'), '')).join('\n');
    final header = RegExp('\\b\\w+\\s+$name\\s*\\(([^)]*)\\)\\s*\\{').firstMatch(code);
    if (header == null) throw StateError('function $name not found');
    final parameters = [
      for (final parameter in header.group(1)!.split(',')) parameter.trim().split(RegExp(r'\s+')).last,
    ];
    var depth = 1, end = header.end;
    while (depth > 0) {
      if (end >= code.length) throw StateError('function $name is not closed');
      final char = code[end++];
      if (char == '{') depth++;
      if (char == '}') depth--;
    }
    final body = code.substring(header.end, end - 1);
    final statements = [
      for (final raw in body.split(';'))
        if (raw.trim().isNotEmpty) raw.trim(),
    ];
    return GlslFunction._(name, parameters, statements);
  }

  final String name;
  final List<String> parameters;
  final List<String> statements;

  List<String> get normalized => [for (final statement in statements) statement.replaceAll(RegExp(r'\s+'), ' ')];

  List<double> call(List<List<double>> arguments) {
    if (arguments.length != parameters.length) throw StateError('$name takes ${parameters.length} arguments');
    final scope = <String, _Value>{for (var i = 0; i < parameters.length; i++) parameters[i]: arguments[i]};
    for (final statement in statements) {
      if (statement.startsWith('return ')) {
        return _Parser(statement.substring(7), scope).expression();
      }
      final declaration = RegExp(r'^(float|vec2|vec3)\s+(\w+)\s*=\s*(.*)$', dotAll: true).firstMatch(statement);
      if (declaration == null) throw StateError('unsupported statement: $statement');
      scope[declaration.group(2)!] = _Parser(declaration.group(3)!, scope).expression();
    }
    throw StateError('$name returned nothing');
  }
}

class _Parser {
  _Parser(String source, this.scope) : tokens = _tokenize(source);

  static final RegExp _token = RegExp(r'\s*(\d+\.?\d*(?:[eE][+-]?\d+)?|\.\d+|\w+|<=|>=|==|!=|[-+*/(),.?:<>])');

  static List<String> _tokenize(String source) {
    final tokens = <String>[];
    var position = 0;
    while (position < source.length) {
      if (source.substring(position).trim().isEmpty) break;
      final match = _token.matchAsPrefix(source, position);
      if (match == null) throw StateError('cannot read: ${source.substring(position)}');
      tokens.add(match.group(1)!);
      position = match.end;
    }
    return tokens;
  }

  final Map<String, _Value> scope;
  final List<String> tokens;
  int position = 0;

  String? get _peek => position < tokens.length ? tokens[position] : null;

  String _next() => tokens[position++];

  void _expect(String token) {
    if (_next() != token) throw StateError('expected $token in ${tokens.join(' ')}');
  }

  _Value expression() {
    final value = _ternary();
    if (position != tokens.length) throw StateError('unread tokens in ${tokens.join(' ')}');
    return value;
  }

  _Value _ternary() {
    final condition = _comparison();
    if (_peek != '?') return condition;
    _next();
    final whenTrue = _ternary();
    _expect(':');
    final whenFalse = _ternary();
    return condition.first != 0 ? whenTrue : whenFalse;
  }

  _Value _comparison() {
    var left = _additive();
    while (const ['<', '>', '<=', '>=', '==', '!='].contains(_peek)) {
      final operator = _next();
      final right = _additive();
      final a = left.first, b = right.first;
      final result = switch (operator) {
        '<' => a < b,
        '>' => a > b,
        '<=' => a <= b,
        '>=' => a >= b,
        '==' => a == b,
        _ => a != b,
      };
      left = [result ? 1.0 : 0.0];
    }
    return left;
  }

  _Value _additive() {
    var left = _multiplicative();
    while (_peek == '+' || _peek == '-') {
      final operator = _next();
      final right = _multiplicative();
      left = _combine(left, right, operator == '+' ? (a, b) => a + b : (a, b) => a - b);
    }
    return left;
  }

  _Value _multiplicative() {
    var left = _unary();
    while (_peek == '*' || _peek == '/') {
      final operator = _next();
      final right = _unary();
      left = _combine(left, right, operator == '*' ? (a, b) => a * b : (a, b) => a / b);
    }
    return left;
  }

  _Value _unary() {
    if (_peek == '-') {
      _next();
      return [for (final component in _unary()) -component];
    }
    return _postfix();
  }

  _Value _postfix() {
    var value = _primary();
    while (_peek == '.') {
      _next();
      final swizzle = _next();
      value = [
        for (final letter in swizzle.split(''))
          value[const {'x': 0, 'y': 1, 'z': 2, 'w': 3, 'r': 0, 'g': 1, 'b': 2, 'a': 3}[letter]!],
      ];
    }
    return value;
  }

  _Value _primary() {
    final token = _next();
    if (token == '(') {
      final value = _ternary();
      _expect(')');
      return value;
    }
    final number = double.tryParse(token);
    if (number != null) return [number];
    if (_peek == '(') {
      _next();
      final arguments = <_Value>[];
      if (_peek != ')') {
        arguments.add(_ternary());
        while (_peek == ',') {
          _next();
          arguments.add(_ternary());
        }
      }
      _expect(')');
      return _call(token, arguments);
    }
    final value = scope[token];
    if (value == null) throw StateError('unknown name $token');
    return value;
  }

  static _Value _combine(_Value a, _Value b, double Function(double, double) f) {
    final length = a.length > b.length ? a.length : b.length;
    if ((a.length != 1 && a.length != length) || (b.length != 1 && b.length != length)) throw StateError('mismatched operands');
    return [for (var i = 0; i < length; i++) f(a[a.length == 1 ? 0 : i], b[b.length == 1 ? 0 : i])];
  }

  static _Value _call(String name, List<_Value> a) {
    switch (name) {
      case 'max':
        return _combine(a[0], a[1], (x, y) => x > y ? x : y);
      case 'min':
        return _combine(a[0], a[1], (x, y) => x < y ? x : y);
      case 'abs':
        return [for (final x in a[0]) x.abs()];
      case 'dot':
        return [_sum(_combine(a[0], a[1], (x, y) => x * y))];
      case 'length':
        return [math.sqrt(_sum([for (final x in a[0]) x * x]))];
      case 'mix':
        final t = a[2];
        return [for (var i = 0; i < a[0].length; i++) a[0][i] + (a[1][i] - a[0][i]) * t[t.length == 1 ? 0 : i]];
      case 'vec2':
      case 'vec3':
        final size = name == 'vec2' ? 2 : 3;
        final flat = [for (final part in a) ...part];
        return flat.length == 1 ? List.filled(size, flat.first) : flat;
    }
    throw StateError('unsupported GLSL function $name');
  }

  static double _sum(List<double> values) => values.fold(0.0, (total, value) => total + value);
}
