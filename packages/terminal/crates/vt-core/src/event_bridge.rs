use crate::alt_screen::AltScreen;
use crate::block::BlockSource;
use crate::parser::Parser;
use terminal_marks::MarkEvent;

/// Apply a `MarkEvent` to the block grid and the alt-screen state. The
/// alt-screen drop rule is the caller's responsibility — this function
/// applies every event it is handed without filtering.
///
/// The mapping table is the plan's spec; the alt-screen `Enter`/`Leave`
/// events are the only ones that touch the `AltScreen` flag. Every other
/// event mutates the grid.
pub(crate) fn apply_event(parser: &mut Parser, alt: &mut AltScreen, event: MarkEvent) {
    match event {
        MarkEvent::PromptStart { tier } => {
            parser.open_block(source_for_tier(tier));
        }
        MarkEvent::CommandStart { .. } | MarkEvent::OutputStart { .. } => {
            // The plan's "Step 3" table marks these as "no block change"
            // for Phase 1a. The block is already open from `PromptStart`,
            // and the grid does not yet track per-block command text.
        }
        MarkEvent::CommandEnd { exit_code, .. } => {
            parser.close_block(exit_code);
        }
        MarkEvent::CwdChanged { path } => {
            parser.grid_mut().set_meta_field("cwd", &path);
        }
        MarkEvent::Extension(fields) => {
            let grid = parser.grid_mut();
            for (key, value) in fields.pairs {
                // The `v` key is the version sentinel from the extension
                // decoder; it is not a block-level field. Drop it on the
                // floor here so the grid's "unknown keys are ignored" rule
                // never even sees it.
                if key == "v" {
                    continue;
                }
                grid.set_meta_field(&key, &value);
            }
        }
        MarkEvent::InputReady | MarkEvent::InputReleased => {}
        MarkEvent::AltScreenEnter => {
            alt.set(true);
        }
        MarkEvent::AltScreenLeave => {
            alt.set(false);
        }
    }
}

/// Map a mark tier to the block source the grid tags a new block with. A
/// Tier-1 OSC 133 prompt is just `Osc133` until an extension field lands;
/// the `Extension` upgrade happens in `BlockGrid::set_meta_field`.
fn source_for_tier(tier: terminal_marks::MarkTier) -> BlockSource {
    match tier {
        terminal_marks::MarkTier::Osc133 => BlockSource::Osc133,
        terminal_marks::MarkTier::Extension => BlockSource::Extension,
    }
}
