package controllers

import (
	"context"
	"errors"
	"net/http"

	"github.com/go-chi/chi/v5"

	"github.com/OmarAly92/operator/backend/internal/httpd/apispec"
	"github.com/OmarAly92/operator/backend/internal/httpd/envelope"
	"github.com/OmarAly92/operator/backend/internal/push"
)

type PhoneAlertService interface {
	Status() push.Status
	Claim() (string, string, error)
	Test(ctx context.Context) push.Delivery
}

type PhoneAlertsController struct {
	Svc PhoneAlertService
}

func (c *PhoneAlertsController) Register(r chi.Router) {
	r.Get("/phone-alerts", c.status)
	r.Post("/phone-alerts/subscribe", c.subscribe)
	r.Post("/phone-alerts/test", c.test)
}

func (c *PhoneAlertsController) status(w http.ResponseWriter, r *http.Request) {
	if c.Svc == nil {
		apispec.NotImplemented(w, r, "GET", "/api/v1/phone-alerts")
		return
	}
	st := c.Svc.Status()
	envelope.WriteJSON(w, http.StatusOK, PhoneAlertStatusResponse{Enabled: st.Enabled, Claimed: st.Claimed, LastDelivery: deliveryResponse(st.LastDelivery)})
}

func (c *PhoneAlertsController) subscribe(w http.ResponseWriter, r *http.Request) {
	if c.Svc == nil {
		apispec.NotImplemented(w, r, "POST", "/api/v1/phone-alerts/subscribe")
		return
	}
	topic, server, err := c.Svc.Claim()
	if errors.Is(err, push.ErrAlertsUnavailable) {
		envelope.WriteAPIError(w, r, http.StatusConflict, "conflict", "PHONE_ALERTS_UNAVAILABLE", err.Error(), nil)
		return
	}
	if err != nil {
		envelope.WriteAPIError(w, r, http.StatusInternalServerError, "internal", "PHONE_ALERTS_FAILED", err.Error(), nil)
		return
	}
	envelope.WriteJSON(w, http.StatusOK, PhoneAlertSubscribeResponse{Topic: topic, Server: server})
}

func (c *PhoneAlertsController) test(w http.ResponseWriter, r *http.Request) {
	if c.Svc == nil {
		apispec.NotImplemented(w, r, "POST", "/api/v1/phone-alerts/test")
		return
	}
	d := c.Svc.Test(r.Context())
	envelope.WriteJSON(w, http.StatusOK, *deliveryResponse(&d))
}

func deliveryResponse(d *push.Delivery) *PhoneAlertDeliveryResponse {
	if d == nil {
		return nil
	}
	return &PhoneAlertDeliveryResponse{At: d.At, OK: d.OK, Error: d.Error}
}
