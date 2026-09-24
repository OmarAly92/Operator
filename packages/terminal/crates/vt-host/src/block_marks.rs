pub(crate) fn write_block_open(text: &mut String, snapshot: &vt_core::GridSnapshot, row: usize) {
    for (index, block) in snapshot.blocks.iter().enumerate() {
        if block.source == vt_core::BlockSource::Synthetic {
            continue;
        }
        if block.first_row as usize == row {
            text.push_str("\x1b]7000;v=1;id=");
            text.push_str(&index.to_string());
            text.push_str(";cmd=");
            percent_encode_into(text, snapshot.block_command(index));
            text.push_str("\x1b\\");
            return;
        }
    }
}

pub(crate) fn write_block_close(text: &mut String, snapshot: &vt_core::GridSnapshot, row: usize) {
    for block in snapshot.blocks.iter() {
        if block.source == vt_core::BlockSource::Synthetic {
            continue;
        }
        let last_row = block.first_row as usize + block.row_count as usize - 1;
        if last_row == row {
            if let Some(exit_code) = block.exit_code {
                text.push_str("\x1b]7000;v=1;exit=");
                text.push_str(&exit_code.to_string());
                text.push_str("\x1b\\");
            }
            return;
        }
    }
}

fn percent_encode_into(text: &mut String, value: &str) {
    for ch in value.chars() {
        if ch.is_ascii() && matches!(ch as u8, b';' | b'=' | b'%' | 0x00..=0x1f) {
            text.push_str(&format!("%{:02X}", ch as u8));
        } else {
            text.push(ch);
        }
    }
}
