package push

import (
	"context"
	"fmt"
	"mime"
	"net/http"
	"net/url"
	"strings"
	"time"
)

const (
	DefaultNtfyServer = "https://ntfy.sh"
	ntfyTimeout       = 5 * time.Second
	ntfyRetryDelay    = 2 * time.Second
	PriorityDefault   = "default"
	PriorityHigh      = "high"
)

type Alert struct {
	Click    string
	Title    string
	Message  string
	Priority string
}

type NtfySender struct {
	baseURL    string
	client     *http.Client
	retryDelay time.Duration
}

func NewNtfySender(baseURL string, client *http.Client) *NtfySender {
	if client == nil {
		client = &http.Client{Timeout: ntfyTimeout}
	}
	return &NtfySender{baseURL: strings.TrimRight(baseURL, "/"), client: client, retryDelay: ntfyRetryDelay}
}

func (s *NtfySender) Send(ctx context.Context, topic string, alert Alert) error {
	err := s.post(ctx, topic, alert)
	if err == nil {
		return nil
	}
	select {
	case <-ctx.Done():
		return err
	case <-time.After(s.retryDelay):
	}
	return s.post(ctx, topic, alert)
}

func (s *NtfySender) post(ctx context.Context, topic string, alert Alert) error {
	ctx, cancel := context.WithTimeout(ctx, ntfyTimeout)
	defer cancel()
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, s.baseURL+"/"+url.PathEscape(topic), strings.NewReader(alert.Message))
	if err != nil {
		return err
	}
	priority := alert.Priority
	if priority == "" {
		priority = PriorityDefault
	}
	req.Header.Set("Title", mime.QEncoding.Encode("utf-8", alert.Title))
	req.Header.Set("Tags", "robot")
	req.Header.Set("Priority", priority)
	if alert.Click != "" {
		req.Header.Set("Click", alert.Click)
	}
	res, err := s.client.Do(req)
	if err != nil {
		return err
	}
	defer res.Body.Close()
	if res.StatusCode/100 != 2 {
		return fmt.Errorf("ntfy answered %s", res.Status)
	}
	return nil
}
