package store_test

import (
	"context"
	"sync"
	"testing"
	"time"
)

func TestAppSettingsMigrationSeedsDesktopDefaults(t *testing.T) {
	s := newTestStore(t)
	ctx := context.Background()

	row, err := s.GetAppSettings(ctx)
	if err != nil {
		t.Fatalf("read app settings: %v", err)
	}
	if row.UILocale != "en" {
		t.Errorf("locale = %q, want en", row.UILocale)
	}
	if row.UpdateOptIn {
		t.Errorf("opt-in = %v, want false", row.UpdateOptIn)
	}
	if row.UpdateFeaturePR != nil {
		t.Errorf("feature pr = %v, want nil", row.UpdateFeaturePR)
	}
	if row.KeybindingsJSON != "{}" {
		t.Errorf("keybindings json = %q, want {}", row.KeybindingsJSON)
	}
	if row.UpdatedAt.IsZero() {
		t.Error("updated_at zero after migration seed")
	}
}

func TestAppSettingsFacetWritesPreserveUnrelatedColumns(t *testing.T) {
	s := newTestStore(t)
	ctx := context.Background()
	now := time.Date(2026, 8, 21, 12, 0, 0, 0, time.UTC)

	if err := s.SetAppUILocale(ctx, "ko", now); err != nil {
		t.Fatalf("set ui locale: %v", err)
	}
	featurePR := int64(12)
	if err := s.SetAppUpdateSettings(ctx, true, &featurePR, now); err != nil {
		t.Fatalf("set update settings: %v", err)
	}
	if err := s.SetAppKeybindings(ctx, `{"next-tab":[{"key":"Tab","ctrl":true}]}`, now); err != nil {
		t.Fatalf("set keybindings: %v", err)
	}

	row, err := s.GetAppSettings(ctx)
	if err != nil {
		t.Fatalf("read app settings: %v", err)
	}
	if row.UILocale != "ko" {
		t.Errorf("locale = %q, want ko preserved", row.UILocale)
	}
	if !row.UpdateOptIn {
		t.Errorf("opt-in = %v, want preserved", row.UpdateOptIn)
	}
	if row.UpdateFeaturePR == nil || *row.UpdateFeaturePR != 12 {
		t.Errorf("feature pr = %v, want 12", row.UpdateFeaturePR)
	}
	if row.KeybindingsJSON != `{"next-tab":[{"key":"Tab","ctrl":true}]}` {
		t.Errorf("keybindings = %q, want preserved", row.KeybindingsJSON)
	}
}

func TestAppSettingsLaterFacetWriteKeepsEarlierFacets(t *testing.T) {
	s := newTestStore(t)
	ctx := context.Background()
	now := time.Date(2026, 8, 21, 12, 0, 0, 0, time.UTC)

	if err := s.SetAppUILocale(ctx, "pt-BR", now); err != nil {
		t.Fatalf("set ui locale: %v", err)
	}
	pr := int64(3)
	if err := s.SetAppUpdateSettings(ctx, false, &pr, now); err != nil {
		t.Fatalf("set update settings: %v", err)
	}

	row, err := s.GetAppSettings(ctx)
	if err != nil {
		t.Fatalf("read app settings: %v", err)
	}
	if row.UILocale != "pt-BR" {
		t.Errorf("locale = %q, want pt-BR untouched by update write", row.UILocale)
	}
	if row.UpdateFeaturePR == nil || *row.UpdateFeaturePR != 3 {
		t.Errorf("feature pr = %v, want 3", row.UpdateFeaturePR)
	}
}

func TestAppSettingsConcurrentFacetWritesAllLand(t *testing.T) {
	s := newTestStore(t)
	ctx := context.Background()
	now := time.Date(2026, 8, 21, 12, 0, 0, 0, time.UTC)

	var wg sync.WaitGroup
	wg.Add(3)
	go func() {
		defer wg.Done()
		if err := s.SetAppUILocale(ctx, "es", now); err != nil {
			t.Errorf("set ui locale: %v", err)
		}
	}()
	go func() {
		defer wg.Done()
		if err := s.SetAppUpdateSettings(ctx, true, nil, now); err != nil {
			t.Errorf("set update settings: %v", err)
		}
	}()
	go func() {
		defer wg.Done()
		if err := s.SetAppKeybindings(ctx, `{"focus-terminal":[{"key":"t","ctrl":true,"meta":true,"shift":true,"alt":false}]}`, now); err != nil {
			t.Errorf("set keybindings: %v", err)
		}
	}()
	wg.Wait()

	row, err := s.GetAppSettings(ctx)
	if err != nil {
		t.Fatalf("read app settings: %v", err)
	}
	if row.UILocale != "es" {
		t.Errorf("locale = %q, want es", row.UILocale)
	}
	if !row.UpdateOptIn {
		t.Errorf("opt-in = %v, want true", row.UpdateOptIn)
	}
	if row.KeybindingsJSON == "{}" {
		t.Error("keybindings write lost")
	}
}

func TestAppSettingsMutationsEmitNoChangeLogRows(t *testing.T) {
	s := newTestStore(t)
	ctx := context.Background()
	now := time.Date(2026, 8, 21, 12, 0, 0, 0, time.UTC)
	pr := int64(9)

	mutate := []func() error{
		func() error { return s.SetAppUILocale(ctx, "zh-CN", now) },
		func() error { return s.SetAppUpdateSettings(ctx, true, &pr, now) },
		func() error { return s.SetAppKeybindings(ctx, `{"new-session":[]}`, now) },
	}
	for i, m := range mutate {
		if err := m(); err != nil {
			t.Fatalf("mutation %d: %v", i, err)
		}
		seq, err := s.LatestSeq(ctx)
		if err != nil {
			t.Fatalf("read change log head: %v", err)
		}
		if seq != 0 {
			t.Fatalf("mutation %d produced change_log rows (head = %d)", i, seq)
		}
	}
}

func TestSetAppUpdateSettingsRoundTripsOptInAndFeaturePin(t *testing.T) {
	s := newTestStore(t)
	ctx := context.Background()
	featurePR := int64(42)
	if err := s.SetAppUpdateSettings(ctx, true, &featurePR, time.Now()); err != nil {
		t.Fatal(err)
	}
	got, err := s.GetAppSettings(ctx)
	if err != nil {
		t.Fatal(err)
	}
	if !got.UpdateOptIn || got.UpdateFeaturePR == nil || *got.UpdateFeaturePR != 42 {
		t.Fatalf("got %+v", got)
	}
}
