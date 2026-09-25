const CSS_SHAPES: [&str; 34] = [
    "default",
    "context-menu",
    "help",
    "pointer",
    "progress",
    "wait",
    "cell",
    "crosshair",
    "text",
    "vertical-text",
    "alias",
    "copy",
    "move",
    "no-drop",
    "not-allowed",
    "grab",
    "grabbing",
    "all-scroll",
    "col-resize",
    "row-resize",
    "n-resize",
    "e-resize",
    "s-resize",
    "w-resize",
    "ne-resize",
    "nw-resize",
    "se-resize",
    "sw-resize",
    "ew-resize",
    "ns-resize",
    "nesw-resize",
    "nwse-resize",
    "zoom-in",
    "zoom-out",
];

const X11_SHAPES: [(&str, &str); 22] = [
    ("left_ptr", "default"),
    ("question_arrow", "help"),
    ("hand", "pointer"),
    ("left_ptr_watch", "progress"),
    ("watch", "wait"),
    ("cross", "crosshair"),
    ("xterm", "text"),
    ("dnd-link", "alias"),
    ("dnd-copy", "copy"),
    ("dnd-move", "move"),
    ("dnd-no-drop", "no-drop"),
    ("crossed_circle", "not-allowed"),
    ("hand1", "grab"),
    ("right_side", "e-resize"),
    ("top_side", "n-resize"),
    ("top_right_corner", "ne-resize"),
    ("top_left_corner", "nw-resize"),
    ("bottom_side", "s-resize"),
    ("bottom_right_corner", "se-resize"),
    ("bottom_left_corner", "sw-resize"),
    ("left_side", "w-resize"),
    ("fleur", "all-scroll"),
];

pub fn pointer_shape_css(name: &str) -> Option<&'static str> {
    if let Some(css) = CSS_SHAPES.iter().find(|css| **css == name) {
        return Some(css);
    }
    X11_SHAPES
        .iter()
        .find(|(x11, _)| *x11 == name)
        .map(|(_, css)| *css)
}
