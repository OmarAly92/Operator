package domain

import "testing"

func TestPermissionModeObservationRoundTrips(t *testing.T) {
	in := PermissionModeObservation{Mode: PermissionModePlan, Version: "2.1.280"}
	out, ok := ParsePermissionModeObservation(in.Detail())
	if !ok || out != in {
		t.Fatalf("round trip = %+v, %v; want %+v", out, ok, in)
	}
}

func TestPermissionModeObservationRefusesJunk(t *testing.T) {
	for _, detail := range []string{"", "not json", `{"mode":"yolo"}`} {
		if _, ok := ParsePermissionModeObservation(detail); ok {
			t.Fatalf("detail %q parsed as an observation", detail)
		}
	}
}

func TestPermissionModeObservationCarriesAnUnknownMode(t *testing.T) {
	in := PermissionModeObservation{Version: "2.1.280"}
	out, ok := ParsePermissionModeObservation(in.Detail())
	if !ok || out != in {
		t.Fatalf("unknown mode = %+v, %v; want %+v", out, ok, in)
	}
}

func TestParseBlockEventKindKnowsPermissionMode(t *testing.T) {
	if kind, ok := ParseBlockEventKind("permission_mode"); !ok || kind != BlockEventPermissionMode {
		t.Fatalf("ParseBlockEventKind(permission_mode) = %q, %v", kind, ok)
	}
}
