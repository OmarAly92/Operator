package screen

import (
	"time"

	"github.com/OmarAly92/operator/backend/internal/domain"
)

type Observation struct {
	Reading  domain.ScreenReading
	Identity string
	Text     string
	Confirm  time.Duration
}

type Decision struct {
	Reading  domain.ScreenReading
	Identity string
	Text     string
}

type Debouncer struct {
	pending   *Observation
	pendingAt time.Time
	applied   *Decision
	sawActive bool
}

func (d *Debouncer) Observe(obs Observation, at time.Time) []Decision {
	if obs.Reading == "" {
		d.pending = nil
		return nil
	}
	if obs.Reading == domain.ScreenWorking {
		d.sawActive = true
	}
	if d.applied != nil && d.applied.Reading == obs.Reading && d.applied.Identity == obs.Identity {
		d.pending = nil
		if obs.Reading != domain.ScreenWorking {
			d.sawActive = false
		}
		return nil
	}
	if d.applied != nil && d.applied.Reading == domain.ScreenQuestion && obs.Reading == domain.ScreenSettled && obs.Confirm > ScreenSettleConfirm {
		obs.Confirm = ScreenSettleConfirm
	}
	if d.pending == nil || d.pending.Reading != obs.Reading || d.pending.Identity != obs.Identity {
		pending := obs
		d.pending = &pending
		d.pendingAt = at
	}
	return d.Due(at)
}

func (d *Debouncer) Due(now time.Time) []Decision {
	if d.pending == nil || now.Sub(d.pendingAt) < d.pending.Confirm {
		return nil
	}
	obs := *d.pending
	d.pending = nil
	var out []Decision
	if obs.Reading == domain.ScreenQuestion && d.applied != nil && d.applied.Reading == domain.ScreenQuestion && d.sawActive {
		out = append(out, Decision{Reading: domain.ScreenWorking})
	}
	decision := Decision{Reading: obs.Reading, Identity: obs.Identity, Text: obs.Text}
	out = append(out, decision)
	d.applied = &decision
	if obs.Reading != domain.ScreenWorking {
		d.sawActive = false
	}
	return out
}
