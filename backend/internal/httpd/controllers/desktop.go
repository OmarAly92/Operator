package controllers

import (
	"net/http"
	"os"
	"strings"

	"github.com/go-chi/chi/v5"

	"github.com/OmarAly92/operator/backend/internal/httpd/envelope"
)

type DesktopController struct {
	Hostname func() (string, error)
}

func (c *DesktopController) Register(r chi.Router) {
	r.Get("/desktop", c.Get)
}

func (c *DesktopController) Get(w http.ResponseWriter, _ *http.Request) {
	hostname := c.Hostname
	if hostname == nil {
		hostname = os.Hostname
	}
	host, err := hostname()
	if err != nil {
		host = ""
	}
	envelope.WriteJSON(w, http.StatusOK, DesktopResponse{Name: DesktopName(host), Hostname: host})
}

func DesktopName(hostname string) string {
	name := strings.TrimSuffix(strings.TrimSpace(hostname), ".local")
	name = strings.TrimSpace(strings.ReplaceAll(name, "-", " "))
	if name == "" {
		return "Desktop"
	}
	return name
}
