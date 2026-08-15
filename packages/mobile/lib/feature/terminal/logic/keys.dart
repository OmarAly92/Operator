import 'package:equatable/equatable.dart';

/// The daemon runs SanitizeControlChars on `POST /sessions/{id}/send`, which
/// strips every one of these — the mux is the only path for control bytes.
class ControlKey extends Equatable {
  const ControlKey({required this.label, required this.sequence, required this.hint});

  final String label;
  final String sequence;
  final String hint;

  @override
  List<Object?> get props => [label, sequence, hint];
}

const List<ControlKey> kControlKeys = [
  ControlKey(label: 'esc', sequence: '\x1b', hint: 'Escape'),
  ControlKey(label: 'tab', sequence: '\t', hint: 'Tab'),
  ControlKey(label: '^C', sequence: '\x03', hint: 'Interrupt'),
  ControlKey(label: '←', sequence: '\x1b[D', hint: 'Left'),
  ControlKey(label: '↑', sequence: '\x1b[A', hint: 'Up'),
  ControlKey(label: '↓', sequence: '\x1b[B', hint: 'Down'),
  ControlKey(label: '→', sequence: '\x1b[C', hint: 'Right'),
  ControlKey(label: '↵', sequence: '\r', hint: 'Enter'),
];
