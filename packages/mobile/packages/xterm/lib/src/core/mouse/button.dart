enum TerminalMouseButton {
  left(id: 0),

  middle(id: 1),

  right(id: 2),

  wheelUp(id: 64 + 0, isWheel: true),

  wheelDown(id: 64 + 1, isWheel: true),

  wheelLeft(id: 64 + 2, isWheel: true),

  wheelRight(id: 64 + 3, isWheel: true),
  ;

  /// The id that is used to report a button press or release to the terminal.
  ///
  /// Mouse wheel up / down use button IDs 4 = 0100 (binary) and 5 = 0101 (binary).
  /// The bits three and four of the button are transposed by 64 and 128
  /// respectively, when reporting the id of the button and have have to be
  /// adjusted correspondingly.
  ///
  /// OPERATOR FORK FIX: the transposition REPLACES bit three, it does not add to
  /// it, so the wheel buttons are 64..67 and not 64+4..64+7. Adding both counted
  /// bit three twice and overflowed into the modifier bits, reporting every
  /// wheel event as Shift+wheel. tmux leaves S-WheelUpPane unbound, so it
  /// accepted the report and silently did nothing, which read as dead scrolling
  /// on the mobile client.
  final int id;

  /// Whether this button is a mouse wheel button.
  final bool isWheel;

  const TerminalMouseButton({required this.id, this.isWheel = false});
}
