package terminal

import (
	"context"

	"github.com/OmarAly92/operator/backend/internal/domain"
)

type NotificationFeed interface {
	Subscribe(projectID domain.ProjectID) (<-chan domain.NotificationEvent, func())
}

func WithNotificationFeed(feed NotificationFeed) Option {
	return func(m *Manager) { m.notificationFeed = feed }
}

type remoteOriginKey struct{}

func WithRemoteOrigin(ctx context.Context) context.Context {
	return context.WithValue(ctx, remoteOriginKey{}, true)
}

func IsRemoteOrigin(ctx context.Context) bool {
	remote, _ := ctx.Value(remoteOriginKey{}).(bool)
	return remote
}

func (m *Manager) startNotificationFeed() {
	if m.notificationFeed == nil {
		return
	}
	events, cancel := m.notificationFeed.Subscribe("")
	m.stopNotificationFeed = cancel
	go func() {
		for ev := range events {
			if ev.Kind != domain.NotificationCreated {
				continue
			}
			m.broadcastNotification(frameFor(ev.Record))
		}
	}()
}

func frameFor(rec domain.NotificationRecord) *notificationFrame {
	return &notificationFrame{
		ID:        rec.ID,
		SessionID: string(rec.SessionID),
		ProjectID: string(rec.ProjectID),
		Type:      string(rec.Type),
		Title:     rec.Title,
		Body:      rec.Body,
		Quiet:     rec.Quiet,
		CreatedAt: rec.CreatedAt,
	}
}

func (m *Manager) broadcastNotification(frame *notificationFrame) {
	m.mu.Lock()
	defer m.mu.Unlock()
	for c := range m.conns {
		c.mu.Lock()
		subscribed := c.notificationsSubscribed && !c.closed
		c.mu.Unlock()
		if subscribed {
			c.enqueue(serverMsg{Ch: chNotifications, Type: msgNotification, Notification: frame})
		}
	}
}

func (m *Manager) PhoneForeground() bool {
	m.mu.Lock()
	defer m.mu.Unlock()
	for c := range m.conns {
		c.mu.Lock()
		foreground := c.remote && c.notificationsSubscribed && !c.closed
		c.mu.Unlock()
		if foreground {
			return true
		}
	}
	return false
}

func (c *connState) handleNotifications(msg clientMsg) {
	c.mu.Lock()
	defer c.mu.Unlock()
	switch msg.Type {
	case msgSubscribe:
		c.notificationsSubscribed = true
	case msgUnsubscribe:
		c.notificationsSubscribed = false
	}
}
