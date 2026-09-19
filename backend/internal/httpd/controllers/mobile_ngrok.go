package controllers

import (
	"encoding/json"
	"errors"
	"net/http"
	"strings"

	"github.com/go-chi/chi/v5"

	"github.com/OmarAly92/operator/backend/internal/httpd/envelope"
	"github.com/OmarAly92/operator/backend/internal/tunnel"
)

func writeNgrokError(w http.ResponseWriter, r *http.Request, err error) {
	if errors.Is(err, tunnel.ErrNgrokAPIUnauthorized) {
		envelope.WriteAPIError(w, r, http.StatusUnauthorized, "unauthorized", "NGROK_API_UNAUTHORIZED", err.Error(), nil)
		return
	}
	envelope.WriteAPIError(w, r, http.StatusBadGateway, "upstream", "NGROK_API_ERROR", err.Error(), nil)
}

func (c *MobileController) NgrokStatus(w http.ResponseWriter, r *http.Request) {
	envelope.WriteJSON(w, http.StatusOK, c.Bridge.NgrokStatus(r.Context()))
}

func (c *MobileController) RemoveAuthtoken(w http.ResponseWriter, r *http.Request) {
	res, err := c.Bridge.RemoveAuthtoken()
	if err != nil {
		envelope.WriteAPIError(w, r, http.StatusInternalServerError, "internal", "MOBILE_AUTHTOKEN_REMOVE", err.Error(), nil)
		return
	}
	envelope.WriteJSON(w, http.StatusOK, withWarning(res))
}

func (c *MobileController) SetNgrokAPIKey(w http.ResponseWriter, r *http.Request) {
	var body MobileNgrokAPIKeyRequest
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil || strings.TrimSpace(body.Key) == "" {
		envelope.WriteAPIError(w, r, http.StatusBadRequest, "invalid_request", "MOBILE_NGROK_APIKEY_BODY", "an ngrok API key is required", nil)
		return
	}
	res, err := c.Bridge.SetAPIKey(r.Context(), body.Key)
	if err != nil {
		writeNgrokError(w, r, err)
		return
	}
	envelope.WriteJSON(w, http.StatusOK, res)
}

func (c *MobileController) RemoveNgrokAPIKey(w http.ResponseWriter, r *http.Request) {
	res, err := c.Bridge.RemoveAPIKey()
	if err != nil {
		envelope.WriteAPIError(w, r, http.StatusInternalServerError, "internal", "MOBILE_NGROK_APIKEY_REMOVE", err.Error(), nil)
		return
	}
	envelope.WriteJSON(w, http.StatusOK, res)
}

func (c *MobileController) NgrokAccount(w http.ResponseWriter, r *http.Request) {
	envelope.WriteJSON(w, http.StatusOK, c.Bridge.NgrokAccount(r.Context()))
}

func (c *MobileController) MintNgrokCredential(w http.ResponseWriter, r *http.Request) {
	res, err := c.Bridge.MintCredential(r.Context())
	if err != nil {
		writeNgrokError(w, r, err)
		return
	}
	envelope.WriteJSON(w, http.StatusOK, res)
}

func (c *MobileController) RevokeNgrokCredential(w http.ResponseWriter, r *http.Request) {
	res, err := c.Bridge.RevokeCredential(r.Context(), chi.URLParam(r, "id"))
	if err != nil {
		writeNgrokError(w, r, err)
		return
	}
	envelope.WriteJSON(w, http.StatusOK, res)
}

func (c *MobileController) SetNgrokDomain(w http.ResponseWriter, r *http.Request) {
	var body MobileNgrokDomainRequest
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		envelope.WriteAPIError(w, r, http.StatusBadRequest, "invalid_request", "MOBILE_NGROK_DOMAIN_BODY", "malformed request body", nil)
		return
	}
	res, err := c.Bridge.SetDomain(r.Context(), body.Domain)
	if err != nil {
		envelope.WriteAPIError(w, r, http.StatusBadRequest, "invalid_request", "MOBILE_NGROK_DOMAIN", err.Error(), nil)
		return
	}
	envelope.WriteJSON(w, http.StatusOK, res)
}

func (c *MobileController) DiagnoseNgrok(w http.ResponseWriter, r *http.Request) {
	envelope.WriteJSON(w, http.StatusOK, c.Bridge.Diagnose(r.Context()))
}
