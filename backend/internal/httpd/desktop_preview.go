package httpd

import (
	"context"
	"encoding/json"
	"net/http"

	"github.com/go-chi/chi/v5"

	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/httpd/envelope"
)

// DesktopPreviewService records the durable preview-open acknowledgements the
// desktop shell sends after opening a preview target externally.
type DesktopPreviewService interface {
	AckPreviewOpened(ctx context.Context, id domain.SessionID, revision int64) error
}

type desktopPreviewOpenedRequest struct {
	Revision int64 `json:"revision"`
}

func mountDesktopPreview(r chi.Router, svc DesktopPreviewService) {
	if svc == nil {
		return
	}
	r.Post("/internal/desktop/sessions/{sessionId}/preview-opened", func(w http.ResponseWriter, req *http.Request) {
		var body desktopPreviewOpenedRequest
		dec := json.NewDecoder(req.Body)
		dec.DisallowUnknownFields()
		if err := dec.Decode(&body); err != nil {
			envelope.WriteAPIError(w, req, http.StatusBadRequest, "bad_request", "INVALID_JSON",
				"request body must be valid JSON with a numeric revision", nil)
			return
		}
		if body.Revision <= 0 {
			envelope.WriteAPIError(w, req, http.StatusBadRequest, "bad_request", "REVISION_REQUIRED",
				"revision must be a positive preview revision", nil)
			return
		}
		if err := svc.AckPreviewOpened(req.Context(), domain.SessionID(chi.URLParam(req, "sessionId")), body.Revision); err != nil {
			envelope.WriteError(w, req, err)
			return
		}
		envelope.WriteJSON(w, http.StatusOK, map[string]any{
			"sessionId": chi.URLParam(req, "sessionId"),
			"revision":  body.Revision,
		})
	})
}
