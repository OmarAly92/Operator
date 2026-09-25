import json
import pathlib

E = "\u001b]777;agent-state;"
BEL = "\u0007"
ST = "\u001b\\"

cases = [
    ("minimal-bel", E + "v=1;state=working" + BEL, [("working", "")]),
    ("st-terminator-with-detail", E + "v=1;state=waiting;detail=Allow%20Bash%3F" + ST, [("waiting", "Allow Bash?")]),
    ("every-state-in-order", E + "v=1;state=working" + BEL + E + "v=1;state=waiting" + BEL + E + "v=1;state=idle" + BEL + E + "v=1;state=done" + BEL, [("working", ""), ("waiting", ""), ("idle", ""), ("done", "")]),
    ("identical-consecutive-events-collapse", E + "v=1;state=working" + BEL + "text" + E + "v=1;state=working" + BEL, [("working", "")]),
    ("same-state-new-detail-is-a-new-event", E + "v=1;state=working;detail=Read" + BEL + E + "v=1;state=working;detail=Edit" + BEL, [("working", "Read"), ("working", "Edit")]),
    ("a-state-returning-after-another-fires-again", E + "v=1;state=working" + BEL + E + "v=1;state=done" + BEL + E + "v=1;state=working" + BEL, [("working", ""), ("done", ""), ("working", "")]),
    ("fields-in-any-order-with-a-space-after-the-separator", E + "state=done; v=1" + BEL, [("done", "")]),
    ("unknown-key-ignored", E + "v=1;state=idle;session=42" + BEL, [("idle", "")]),
    ("empty-trailing-field-ignored", E + "v=1;state=idle;" + BEL, [("idle", "")]),
    ("higher-version-ignored", E + "v=2;state=working" + BEL, []),
    ("missing-version-ignored", E + "state=working" + BEL, []),
    ("missing-state-ignored", E + "v=1;detail=x" + BEL, []),
    ("unknown-state-ignored", E + "v=1;state=paused" + BEL, []),
    ("repeated-key-ignored", E + "v=1;state=working;state=done" + BEL, []),
    ("field-without-equals-ignored", E + "v=1;state=working;oops" + BEL, []),
    ("malformed-percent-escape-ignored", E + "v=1;state=working;detail=100%" + BEL, []),
    ("detail-decodes-utf8-and-drops-control-characters", E + "v=1;state=done;detail=caf%C3%A9%0A%1Bok" + BEL, [("done", "caféok")]),
    ("detail-capped-at-256-bytes", E + "v=1;state=working;detail=" + "a" * 300 + BEL, [("working", "a" * 256)]),
    ("payload-of-1023-bytes-accepted", E + "v=1;state=working;x=" + "c" * 987 + BEL, [("working", "")]),
    ("payload-filling-the-1024-byte-osc-buffer-ignored", E + "v=1;state=working;x=" + "b" * 1100 + BEL, []),
    ("extension-name-is-case-sensitive", "\u001b]777;Agent-State;v=1;state=working" + BEL, []),
    ("notify-is-not-an-agent-event", "\u001b]777;notify;Build;done" + BEL, []),
    ("other-osc-numbers-are-not-agent-events", "\u001b]7000;agent-state;v=1;state=working" + BEL + "\u001b]9;agent-state;v=1;state=working" + BEL, []),
    ("an-ignored-event-does-not-break-the-next-one", E + "v=9;state=working" + BEL + E + "v=1;state=idle" + BEL, [("idle", "")]),
]

doc = {
    "name": "agent-state",
    "description": "OSC 777 ; agent-state ; v=1 ; state=<working|waiting|idle|done> [; detail=<percent-encoded UTF-8>] (BEL | ST). Each case is fed to a fresh core; events lists what take_agent_events returns, in order.",
    "cases": [
        {"name": name, "input": data, "events": [{"state": state, "detail": detail} for state, detail in events]}
        for name, data, events in cases
    ],
}

out = pathlib.Path(__file__).resolve().parent / "agent-state.json"
out.write_text(json.dumps(doc, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
print(out)
