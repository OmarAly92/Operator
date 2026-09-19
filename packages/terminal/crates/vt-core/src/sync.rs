// Port of `vte-0.15.0/src/ansi.rs` (`Processor::advance_sync`,
// `advance_sync_csi`, `stop_sync_internal`).
use memchr::memmem;

pub const SYNC_TIMEOUT_MS: u64 = 150;
pub const SYNC_BUFFER_CAP: usize = 2 * 1024 * 1024;
pub(crate) const BSU: &[u8] = b"\x1b[?2026h";
pub(crate) const ESU: &[u8] = b"\x1b[?2026l";
pub(crate) const BOUNDARY_MARK: &[u8] = b"\x1b]7000;v=1;boundary=";
const ESCAPE_LEN: usize = 8;
const CARRY_LEN: usize = ESCAPE_LEN - 1;

pub(crate) enum TailScan {
    Keep,
    FlushAll,
    FlushBefore(usize),
}

#[derive(Default)]
pub(crate) struct SyncBuffer {
    pub(crate) bytes: Vec<u8>,
    deadline_ms: Option<u64>,
    carry: Vec<u8>,
}

impl SyncBuffer {
    pub(crate) fn is_active(&self) -> bool {
        self.deadline_ms.is_some()
    }

    pub(crate) fn deadline(&self) -> Option<u64> {
        self.deadline_ms
    }

    pub(crate) fn begin(&mut self, now_ms: u64) {
        self.deadline_ms = Some(now_ms + SYNC_TIMEOUT_MS);
    }

    pub(crate) fn end(&mut self) {
        self.deadline_ms = None;
    }

    pub(crate) fn note_parsed(&mut self, bytes: &[u8]) {
        if bytes.len() >= CARRY_LEN {
            self.carry.clear();
            self.carry
                .extend_from_slice(&bytes[bytes.len() - CARRY_LEN..]);
        } else {
            self.carry.extend_from_slice(bytes);
            if self.carry.len() > CARRY_LEN {
                let drop = self.carry.len() - CARRY_LEN;
                self.carry.drain(..drop);
            }
        }
    }

    pub(crate) fn find_bsu(&self, bytes: &[u8]) -> Option<usize> {
        let mut probe = Vec::with_capacity(self.carry.len() + bytes.len().min(ESCAPE_LEN));
        probe.extend_from_slice(&self.carry);
        probe.extend_from_slice(&bytes[..bytes.len().min(ESCAPE_LEN)]);
        if let Some(index) = memmem::find(&probe, BSU) {
            if index < self.carry.len() {
                return Some(0);
            }
        }
        memmem::find(bytes, BSU)
    }

    pub(crate) fn would_overflow(&self, additional: usize) -> bool {
        self.bytes.len() + additional >= SYNC_BUFFER_CAP - 1
    }

    pub(crate) fn append(&mut self, bytes: &[u8], now_ms: u64) -> TailScan {
        self.bytes.extend_from_slice(bytes);
        let len = self.bytes.len();
        let start = (len - bytes.len()).saturating_sub(BOUNDARY_MARK.len() - 1);
        if memmem::find(&self.bytes[start..], BOUNDARY_MARK).is_some() {
            return TailScan::FlushAll;
        }
        let start = (len - bytes.len()).saturating_sub(CARRY_LEN);
        let end = len.saturating_sub(CARRY_LEN);
        let mut bsu_offset = None;
        for index in memchr::memchr_iter(0x1b, &self.bytes[start..end]).rev() {
            let offset = start + index;
            let escape = &self.bytes[offset..offset + ESCAPE_LEN];
            if escape == BSU {
                self.deadline_ms = Some(now_ms + SYNC_TIMEOUT_MS);
                bsu_offset = Some(offset);
            } else if escape == ESU {
                return match bsu_offset {
                    Some(keep_from) => TailScan::FlushBefore(keep_from),
                    None => TailScan::FlushAll,
                };
            }
        }
        TailScan::Keep
    }

    pub(crate) fn take(&mut self) -> Vec<u8> {
        std::mem::take(&mut self.bytes)
    }
}
