// Package specgen builds the code-first OpenAPI document from the Go contract
// types. It lives outside apispec because it imports the controllers (to
// reflect their request/response shapes), and controllers import apispec (for
// the 501 stub) — keeping Build here breaks that cycle. apispec only embeds and
// serves the committed openapi.yaml; specgen produces it.
package specgen

import (
	"fmt"
	"net/http"
	"reflect"
	"strings"

	jsonschema "github.com/swaggest/jsonschema-go"
	openapi "github.com/swaggest/openapi-go"
	"github.com/swaggest/openapi-go/openapi31"

	"github.com/OmarAly92/operator/backend/internal/adapters/projectscan"
	"github.com/OmarAly92/operator/backend/internal/httpd/controllers"
	"github.com/OmarAly92/operator/backend/internal/httpd/envelope"
	projectsvc "github.com/OmarAly92/operator/backend/internal/service/project"
	settingssvc "github.com/OmarAly92/operator/backend/internal/service/settings"
)

// Build reflects the Go contract types and the operation registry below into
// the OpenAPI document. It is the single source of truth for the /api/v1
// contract: `cmd/genspec` writes its output to apispec/openapi.yaml (the
// committed, embedded artifact) and TestBuild_MatchesEmbedded asserts the embed
// equals fresh Build() output so the two can never drift. Schema facets live as
// struct tags on the service.*/controllers.* types; operation metadata (path,
// status codes, summaries) lives here.
//
// Every wire shape is reflected straight from where it is used at runtime — the
// request bodies, path params, and response envelopes from controllers, the
// error envelope from httpd/envelope — so the served responses and the
// generated schema share one definition each.
func Build() ([]byte, error) {
	r := openapi31.NewReflector()
	// Derive `required` from the idiomatic Go convention: a JSON field without
	// `omitempty` is required. swaggest does not infer this on its own, so the
	// structs stay clean (only description/enum tags) and this hook adds the
	// required array. nonNullableSlices drops the spurious "null" type swaggest
	// stamps on every Go slice.
	r.DefaultOptions = append(r.DefaultOptions,
		jsonschema.InterceptProp(requiredFromJSONTag),
		jsonschema.InterceptNullability(nonNullableSlices),
		// Clean component schema names (which become the generated TS type names):
		// swaggest defaults to PackageType, e.g. "ProjectProject", "EnvelopeAPIError".
		jsonschema.InterceptDefName(schemaName),
	)

	r.Spec.SetTitle("Operator HTTP daemon")
	r.Spec.SetVersion("0.1.0-route-shell")
	r.Spec.SetDescription("Loopback-only HTTP surface served by the Go daemon. " +
		"Generated from Go (code-first) — do not edit by hand; run `go generate ./...`.")
	r.Spec.Servers = []openapi31.Server{
		*(&openapi31.Server{URL: "http://127.0.0.1:3001"}).WithDescription("Local daemon (loopback only)"),
	}
	r.Spec.Tags = []openapi31.Tag{
		*(&openapi31.Tag{Name: "agents"}).WithDescription(
			"Supported and locally runnable agent adapters"),
		*(&openapi31.Tag{Name: "projects"}).WithDescription(
			"Project registry, configuration, and lifecycle administration"),
		*(&openapi31.Tag{Name: "sessions"}).WithDescription(
			"Agent session lifecycle and messaging"),
		*(&openapi31.Tag{Name: "prs"}).WithDescription(
			"Pull-request actions (SCM lane)"),
		*(&openapi31.Tag{Name: "reviews"}).WithDescription(
			"Code-review runs and findings"),
		*(&openapi31.Tag{Name: "notifications"}).WithDescription(
			"Durable dashboard notifications"),
		*(&openapi31.Tag{Name: "usage"}).WithDescription(
			"Token usage telemetry for Operator sessions"),
		*(&openapi31.Tag{Name: "push"}).WithDescription(
			"Mobile push-device registration for OS push notifications"),
		*(&openapi31.Tag{Name: "events"}).WithDescription(
			"Server-sent CDC event stream with durable replay"),
		*(&openapi31.Tag{Name: "dev"}).WithDescription(
			"Developer-only maintenance operations"),
		*(&openapi31.Tag{Name: "mobile"}).WithDescription(
			"Connect Mobile LAN bridge control (loopback/desktop only)"),
		*(&openapi31.Tag{Name: "browser"}).WithDescription(
			"Target-isolated desktop browser runtime (loopback only)"),
		*(&openapi31.Tag{Name: "inbox"}).WithDescription(
			"Per-project orchestrator inbox of pending worker/CI/review events"),
		*(&openapi31.Tag{Name: "tickets"}).WithDescription(
			"Planning tickets: spec and plan documents in the repo, assigned to sessions"),
		*(&openapi31.Tag{Name: "claudeAccounts"}).WithDescription(
			"Claude account folders: creation, login, relink, and status"),
		*(&openapi31.Tag{Name: "desktop"}).WithDescription(
			"Desktop machine identification for a paired phone"),
	}

	for _, op := range operations() {
		oc, err := r.NewOperationContext(op.method, op.path)
		if err != nil {
			return nil, fmt.Errorf("new operation %s %s: %w", op.method, op.path, err)
		}
		oc.SetID(op.id)
		oc.SetSummary(op.summary)
		oc.SetTags(op.tag)
		for _, param := range op.pathParams {
			oc.AddReqStructure(param)
		}
		if op.reqBody != nil {
			// AddReqStructure leaves requestBody.required absent, which
			// OpenAPI reads as optional. Most of these bodies are mandatory, so
			// force it — otherwise validators/generators treat the body as
			// skippable. Ops that genuinely accept an empty body opt out.
			if op.optionalReqBody {
				oc.AddReqStructure(op.reqBody)
			} else {
				oc.AddReqStructure(op.reqBody, openapi.WithCustomize(markRequestBodyRequired))
			}
		}
		for _, resp := range op.resps {
			opts := []openapi.ContentOption{openapi.WithHTTPStatus(resp.status)}
			if op.contentTypes != nil && op.contentTypes[resp.status] != "" {
				opts = append(opts, openapi.WithContentType(op.contentTypes[resp.status]))
			}
			oc.AddRespStructure(resp.body, opts...)
		}
		if err := r.AddOperation(oc); err != nil {
			return nil, fmt.Errorf("add operation %s %s: %w", op.method, op.path, err)
		}
	}

	return r.Spec.MarshalYAML()
}

// schemaName maps swaggest's default PackageType component names (e.g.
// "ProjectProject", "EnvelopeAPIError") to the clean, stable schema names that
// become the generated TypeScript type names. Every reflected type is listed
// explicitly: an unrecognised default name is returned verbatim, so a new type
// surfaces as a visibly-wrong "PackageType" name in the diff (and the drift
// test) rather than silently colliding with an existing schema via a
// TrimPrefix catch-all.
func schemaName(_ reflect.Type, defaultName string) string {
	if clean, ok := schemaNames[defaultName]; ok {
		return clean
	}
	return defaultName
}

// schemaNames is the exhaustive default→clean mapping for every type reflected
// by projectOperations(). Add an entry when a new contract type is introduced;
// the drift test fails until the spec is regenerated, which flags the gap.
var schemaNames = map[string]string{
	"ControllersSettingsResponse": "SettingsResponse",
	"ControllersUiSettings":       "UiSettings",
	"SettingsUpdateSettings":      "UpdateSettings",
	"SettingsFeaturePin":          "FeaturePin",
	"SettingsKeybindingOverrides": "KeybindingOverrides",
	"SettingsShortcutBinding":     "ShortcutBinding",
	// httpd/envelope
	"EnvelopeAPIError": "APIError",
	// domain
	"DomainProjectID":                  "ProjectID",
	"DomainSessionID":                  "SessionID",
	"DomainIssueID":                    "IssueID",
	"DomainSession":                    "Session",
	"DomainSessionTicketRef":           "SessionTicketRef",
	"DomainTicketRole":                 "TicketRole",
	"DomainProjectConfig":              "ProjectConfig",
	"DomainTrackerIntakeConfig":        "TrackerIntakeConfig",
	"ControllersTriggerReviewRequest":  "TriggerReviewRequest",
	"DomainContainerReapConfig":        "ContainerReapConfig",
	"DomainAgentConfig":                "AgentConfig",
	"DomainRoleOverride":               "RoleOverride",
	"DomainOrchestratorPolicy":         "OrchestratorPolicy",
	"ControllersTicketView":            "TicketView",
	"ControllersPlanView":              "PlanView",
	"ControllersListTicketsResponse":   "ListTicketsResponse",
	"ControllersTicketResponse":        "TicketResponse",
	"ControllersTicketFileResponse":    "TicketFileResponse",
	"ControllersCreateTicketRequest":   "CreateTicketRequest",
	"ControllersCreateTicketResponse":  "CreateTicketResponse",
	"ControllersSaveTicketFileRequest": "SaveTicketFileRequest",
	"ControllersPlanTicketRequest":     "PlanTicketRequest",
	"ControllersAssignPlanRequest":     "AssignPlanRequest",
	"ControllersAssignPlanResponse":    "AssignPlanResponse",
	"ControllersReviewPlanRequest":     "ReviewPlanRequest",
	"ControllersReviewPlanResponse":    "ReviewPlanResponse",
	"ControllersMergeReadyRequest":     "MergeReadyRequest",
	"DomainTicketStatus":               "TicketStatus",
	"DomainPlanStatus":                 "PlanStatus",
	"DomainTicketDefaults":             "TicketDefaults",
	"DomainTicketRoleDefaults":         "TicketRoleDefaults",
	// httpd/controllers (wire envelopes)
	"ControllersListProjectsResponse":               "ListProjectsResponse",
	"ControllersProjectResponse":                    "ProjectResponse",
	"ControllersAgentIDParam":                       "AgentIDParam",
	"ControllersGetProjectResponse":                 "ProjectGetResponse",
	"ControllersProjectOrDegraded":                  "ProjectOrDegraded",
	"ControllersListSessionsQuery":                  "ListSessionsQuery",
	"ControllersCleanupSessionsQuery":               "CleanupSessionsQuery",
	"ControllersListSessionsResponse":               "ListSessionsResponse",
	"ControllersInboxEntryView":                     "InboxEntryView",
	"ControllersInboxResponse":                      "InboxResponse",
	"ControllersAckInboxEventsRequest":              "AckInboxEventsRequest",
	"ControllersAckInboxEventsResponse":             "AckInboxEventsResponse",
	"ControllersSpawnSessionRequest":                "SpawnSessionRequest",
	"ControllersSpawnSessionResponse":               "SpawnSessionResponse",
	"ControllersSessionResponse":                    "SessionResponse",
	"ControllersSessionPreviewResponse":             "SessionPreviewResponse",
	"ControllersSetSessionPreviewRequest":           "SetSessionPreviewRequest",
	"ControllersStartPreviewServerRequest":          "StartPreviewServerRequest",
	"ControllersPreviewServerStatusResponse":        "PreviewServerStatusResponse",
	"ControllersBrowserStatusQuery":                 "BrowserStatusQuery",
	"ControllersBrowserStatusResponse":              "BrowserStatusResponse",
	"ControllersBrowserCommandRequest":              "BrowserCommandRequest",
	"ControllersBrowserCommandResponse":             "BrowserCommandResponse",
	"ControllersSetSessionMergePolicyRequest":       "SetSessionMergePolicyRequest",
	"ControllersSetSessionMergePolicyResponse":      "SetSessionMergePolicyResponse",
	"ControllersSetSessionAutoInjectReviewRequest":  "SetSessionAutoInjectReviewRequest",
	"ControllersSetSessionAutoInjectReviewResponse": "SetSessionAutoInjectReviewResponse",
	"ControllersRenameSessionRequest":               "RenameSessionRequest",
	"ControllersSetSessionReviewerRequest":          "SetSessionReviewerRequest",
	"ControllersRenameSessionResponse":              "RenameSessionResponse",
	"ControllersRestoreSessionResponse":             "RestoreSessionResponse",
	"ControllersResumeAgentResponse":                "ResumeAgentResponse",
	"ControllersSwitchAgentRequest":                 "SwitchAgentRequest",
	"ControllersAgentSwitchView":                    "AgentSwitch",
	"ControllersAgentSwitchResponse":                "AgentSwitchResponse",
	"ControllersListAgentSwitchesResponse":          "ListAgentSwitchesResponse",
	"ControllersListSessionBlockEventsResponse":     "ListSessionBlockEventsResponse",
	"ControllersBlockEventView":                     "BlockEventView",
	"ControllersBlockRedactedSpanView":              "BlockRedactedSpanView",
	"ControllersSubmitAgentHandoffRequest":          "SubmitAgentHandoffRequest",
	"ControllersCleanupSessionsResponse":            "CleanupSessionsResponse",
	"ControllersCleanupSkippedSession":              "CleanupSkippedSession",
	"ControllersWorkspaceFileQuery":                 "WorkspaceFileQuery",
	"ControllersStageSessionAttachmentsRequest":     "StageSessionAttachmentsRequest",
	"ControllersStageSessionAttachmentsResponse":    "StageSessionAttachmentsResponse",
	"ControllersAttachmentInput":                    "AttachmentInput",
	"ControllersListWorkspaceFilesResponse":         "ListWorkspaceFilesResponse",
	"ControllersWorkspaceFileSummary":               "WorkspaceFileSummary",
	"ControllersWorkspaceFileResponse":              "WorkspaceFileResponse",
	"ControllersKillSessionResponse":                "KillSessionResponse",
	"ControllersRollbackSessionResponse":            "RollbackSessionResponse",
	"ControllersSendSessionMessageRequest":          "SendSessionMessageRequest",
	"ControllersSendSessionMessageResponse":         "SendSessionMessageResponse",
	"ControllersSessionCommandRequest":              "SessionCommandRequest",
	"ControllersSessionCommandResponse":             "SessionCommandResponse",
	"ControllersDelegateTaskRequest":                "DelegateTaskRequest",
	"ControllersDelegateTaskResponse":               "DelegateTaskResponse",
	"ControllersClaimPRResponse":                    "ClaimPRResponse",
	"ControllersClaimPRRequest":                     "ClaimPRRequest",
	"ControllersSessionPRFacts":                     "SessionPRFacts",
	"ControllersSessionPRSummary":                   "SessionPRSummary",
	"ControllersSessionPRCISummary":                 "SessionPRCISummary",
	"ControllersSessionPRFailingCheck":              "SessionPRFailingCheck",
	"ControllersSessionPRReviewSummary":             "SessionPRReviewSummary",
	"ControllersSessionPRReviewEntry":               "SessionPRReviewEntry",
	"ControllersSessionPRUnresolvedReviewer":        "SessionPRUnresolvedReviewer",
	"ControllersSessionPRReviewCommentLink":         "SessionPRReviewCommentLink",
	"ControllersSessionPRMergeabilitySummary":       "SessionPRMergeabilitySummary",
	"ControllersSessionPRConflictFile":              "SessionPRConflictFile",
	"ControllersListSessionPRsResponse":             "ListSessionPRsResponse",
	"ControllersSetActivityRequest":                 "SetActivityRequest",
	"ControllersSetActivityResponse":                "SetActivityResponse",
	"ControllersSetReviewActivityRequest":           "SetReviewActivityRequest",
	"ControllersSetReviewActivityResponse":          "SetReviewActivityResponse",
	"ControllersSpawnOrchestratorRequest":           "SpawnOrchestratorRequest",
	"ControllersSpawnOrchestratorResponse":          "SpawnOrchestratorResponse",
	"ControllersOrchestratorResponse":               "OrchestratorResponse",
	"AgentInventory":                                "ListAgentsResponse",
	"AgentInfo":                                     "AgentInfo",
	"AgentProbeResult":                              "ProbeAgentResponse",
	"PortsAgentModelCatalog":                        "AgentModelsResponse",
	"PortsAgentModelInfo":                           "AgentModelInfo",
	"ControllersListNotificationsQuery":             "ListNotificationsQuery",
	"ControllersNotificationStreamQuery":            "NotificationStreamQuery",
	"ControllersNotificationIDParam":                "NotificationIDParam",
	"ControllersNotificationTarget":                 "NotificationTarget",
	"ControllersNotificationResponse":               "NotificationResponse",
	"ControllersListNotificationsResponse":          "ListNotificationsResponse",
	"ControllersMarkNotificationReadRequest":        "MarkNotificationReadRequest",
	"ControllersNotificationEnvelope":               "NotificationEnvelope",
	"ControllersMarkAllNotificationsReadRequest":    "MarkAllNotificationsReadRequest",
	"ControllersMarkAllNotificationsReadResponse":   "MarkAllNotificationsReadResponse",
	"ControllersUsageHookMetadata":                  "UsageHookMetadata",
	"ControllersListUsageSessionsQuery":             "ListUsageSessionsQuery",
	"ControllersUsageRollupQuery":                   "UsageRollupQuery",
	"ControllersCompactSessionUsageResponse":        "CompactSessionUsageResponse",
	"ControllersListCompactSessionUsageResponse":    "ListCompactSessionUsageResponse",
	"ControllersUsageTotalsResponse":                "UsageTotalsResponse",
	"ControllersUsageModelResponse":                 "UsageModelResponse",
	"ControllersUsageHarnessResponse":               "UsageHarnessResponse",
	"ControllersSessionContextResponse":             "SessionContextResponse",
	"ControllersUsageRollupBucketResponse":          "UsageRollupBucketResponse",
	"ControllersUsageRollupResponse":                "UsageRollupResponse",
	"ControllersSessionUsageResponse":               "SessionUsageResponse",
	"ControllersUsageQuotaWindowResponse":           "UsageQuotaWindowResponse",
	"ControllersUsageQuotaResponse":                 "UsageQuotaResponse",
	"ControllersUsageQuotaEnvelope":                 "UsageQuotaEnvelope",
	// httpd/controllers — standalone shell terminal wire envelopes
	"ControllersShellTerminalHandleIDParam": "ShellTerminalHandleIDParam",
	"ControllersOpenShellTerminalRequest":   "OpenShellTerminalRequest",
	"ControllersUpdateShellTerminalRequest": "UpdateShellTerminalRequest",
	"ControllersShellTerminalResponse":      "ShellTerminalResponse",
	"ControllersListShellTerminalsResponse": "ListShellTerminalsResponse",
	"ControllersShellTerminalEnvelope":      "ShellTerminalEnvelope",
	"ControllersTerminalBlockView":          "TerminalBlockView",
	"ControllersClaudeAccountView":          "ClaudeAccountView",
	"ControllersClaudeAccountStatus":        "ClaudeAccountStatus",
	"ControllersListClaudeAccountsResponse": "ListClaudeAccountsResponse",
	"ControllersClaudeAccountEnvelope":      "ClaudeAccountEnvelope",
	"ControllersCreateClaudeAccountRequest": "CreateClaudeAccountRequest",
	"ControllersRenameClaudeAccountRequest": "RenameClaudeAccountRequest",
	"ControllersClaudeAccountLoginRequest":  "ClaudeAccountLoginRequest",
	// httpd/controllers — PR wire envelopes
	"ControllersMergePRRequest":          "MergePRRequest",
	"ControllersMergePRResponse":         "MergePRResponse",
	"ControllersResolveCommentsRequest":  "ResolveCommentsRequest",
	"ControllersResolveCommentsResponse": "ResolveCommentsResponse",
	// httpd/controllers — review wire envelopes
	"ControllersListReviewsResponse":   "ListReviewsResponse",
	"ControllersReviewRunResponse":     "ReviewRunResponse",
	"ControllersTriggerReviewResponse": "TriggerReviewResponse",
	"ControllersCancelReviewResponse":  "CancelReviewResponse",
	"ControllersKillReviewResponse":    "KillReviewResponse",
	"ControllersRestoreReviewResponse": "RestoreReviewResponse",
	"ControllersSubmitReviewItem":      "SubmitReviewItem",
	"ControllersSubmitReviewInput":     "SubmitReviewInput",
	// domain review entities
	"DomainReviewRun":     "ReviewRun",
	"ReviewPRReviewState": "PRReviewState",
	// httpd/controllers: dev wire envelopes
	"ControllersDevImportProjectsRequest":      "DevImportProjectsRequest",
	"ControllersDevImportProjectsResponse":     "DevImportProjectsResponse",
	"ControllersDevImportScanRequest":          "DevImportScanRequest",
	"ControllersDevAncestorRepositoryRequest":  "DevAncestorRepositoryRequest",
	"ControllersDevAncestorRepositoryResponse": "DevAncestorRepositoryResponse",
	"ControllersDevBlockReplayRequest":         "DevBlockReplayRequest",
	"ControllersDevBlockReplayResponse":        "DevBlockReplayResponse",
	// projectscan folder-scan shapes
	"ProjectscanRepo":   "ImportFolderScanRepo",
	"ProjectscanResult": "ImportFolderScanResult",
	// httpd/controllers: mobile wire envelopes
	"ControllersMobileStatusResponse":         "MobileStatusResponse",
	"ControllersMobileTunnelStatus":           "MobileTunnelStatus",
	"ControllersMobileAuthtokenRequest":       "MobileAuthtokenRequest",
	"ControllersMobileNgrokStatus":            "MobileNgrokStatus",
	"ControllersMobileNgrokCredential":        "MobileNgrokCredential",
	"ControllersMobileNgrokAgent":             "MobileNgrokAgent",
	"ControllersMobileNgrokSession":           "MobileNgrokSession",
	"ControllersMobileNgrokLogLine":           "MobileNgrokLogLine",
	"ControllersMobileNgrokAPIKey":            "MobileNgrokAPIKey",
	"ControllersMobileNgrokAPIKeyRequest":     "MobileNgrokAPIKeyRequest",
	"ControllersMobileNgrokAccount":           "MobileNgrokAccount",
	"ControllersMobileNgrokAccountCredential": "MobileNgrokAccountCredential",
	"ControllersMobileNgrokAccountSession":    "MobileNgrokAccountSession",
	"ControllersMobileNgrokAccountEndpoint":   "MobileNgrokAccountEndpoint",
	"ControllersMobileNgrokReservedDomain":    "MobileNgrokReservedDomain",
	"ControllersMobileNgrokDomainRequest":     "MobileNgrokDomainRequest",
	"ControllersMobileNgrokCredentialIDParam": "MobileNgrokCredentialIDParam",
	"ControllersMobileNgrokCheck":             "MobileNgrokCheck",
	"ControllersMobileNgrokDiagnosis":         "MobileNgrokDiagnosis",
	// httpd/controllers: desktop wire envelope
	"ControllersDesktopResponse": "DesktopResponse",
	// devimport report
	"DevimportReport":   "DevImportProjectsReport",
	"DevimportConflict": "DevImportProjectsConflict",
	// httpd/controllers: push-device wire envelopes
	"ControllersRegisterPushDeviceRequest":    "RegisterPushDeviceRequest",
	"ControllersPushDeviceEnvelope":           "PushDeviceEnvelope",
	"ControllersPushDeviceResponse":           "PushDeviceResponse",
	"ControllersUnregisterPushDeviceResponse": "UnregisterPushDeviceResponse",
	// service/project entities + DTOs
	"ProjectProject":                    "Project",
	"ProjectSummary":                    "ProjectSummary",
	"ProjectDegraded":                   "DegradedProject",
	"ProjectAddInput":                   "AddProjectInput",
	"ProjectInitializeRepositoryInput":  "InitializeRepositoryInput",
	"ProjectInitializeRepositoryResult": "InitializeRepositoryResult",
	"ProjectRemoveResult":               "RemoveProjectResult",
	"ProjectSetConfigInput":             "SetProjectConfigInput",
	"ProjectUpdateSettingsInput":        "UpdateProjectSettingsInput",
	"ProjectWorkspaceRepo":              "WorkspaceRepo",
	"SessionWorkspaceFileStatus":        "WorkspaceFileStatus",
}

// markRequestBodyRequired sets requestBody.required: true on the operation's
// JSON body. swaggest leaves it absent (== optional) for AddReqStructure bodies.
func markRequestBodyRequired(cor openapi.ContentOrReference) {
	if rb, ok := cor.(*openapi31.RequestBodyOrReference); ok && rb.RequestBody != nil {
		rb.RequestBody.WithRequired(true)
	}
}

// nonNullableSlices drops the "null" that swaggest unions into every Go slice
// type (a nil slice marshals as JSON null). A required array field should be
// `T[]`, not `T[] | null`; the handlers normalise nil to an empty slice, so
// null never reaches the wire. Byte slices (base64 strings) are left alone.
func nonNullableSlices(p jsonschema.InterceptNullabilityParams) {
	if !p.NullAdded || p.Type == nil || p.Type.Kind() != reflect.Slice {
		return
	}
	if p.Type.Elem().Kind() == reflect.Uint8 {
		return
	}
	p.Schema.TypeEns().WithSimpleTypes(jsonschema.Array)
	p.Schema.Type.SliceOfSimpleTypeValues = nil
}

// requiredFromJSONTag marks a property required when its json tag lacks
// `omitempty` (the Go convention for "always present"). Runs after default
// processing so ParentSchema exists; skips fields without a json tag (e.g. path
// params, which swaggest marks required on their own).
func requiredFromJSONTag(p jsonschema.InterceptPropParams) error {
	if !p.Processed || p.ParentSchema == nil {
		return nil
	}
	jsonTag := p.Field.Tag.Get("json")
	if jsonTag == "" || jsonTag == "-" {
		return nil
	}
	parts := strings.Split(jsonTag, ",")
	name := parts[0]
	if name == "" {
		name = p.Name
	}
	for _, opt := range parts[1:] {
		if opt == "omitempty" {
			return nil
		}
	}
	for _, existing := range p.ParentSchema.Required {
		if existing == name {
			return nil
		}
	}
	p.ParentSchema.Required = append(p.ParentSchema.Required, name)
	return nil
}

// --- operation registry -----------------------------------------------------

type respUnit struct {
	status int
	body   any
}

type operation struct {
	method, path, id, summary string
	tag                       string
	pathParams                []any // path/query param containers (e.g. ProjectIDParam)
	reqBody                   any   // JSON request body struct, nil when the op takes none
	// optionalReqBody declares the body without marking it required, for the
	// handlers that accept an empty body as a meaningful default.
	optionalReqBody bool
	resps           []respUnit
	contentTypes    map[int]string // optional non-JSON response content types by status
}

func operations() []operation {
	ops := append([]operation{}, eventOperations()...)
	ops = append(ops, agentOperations()...)
	ops = append(ops, projectOperations()...)
	ops = append(ops, sessionOperations()...)
	ops = append(ops, prOperations()...)
	ops = append(ops, reviewOperations()...)
	ops = append(ops, notificationOperations()...)
	ops = append(ops, usageOperations()...)
	ops = append(ops, pushOperations()...)
	ops = append(ops, devOperations()...)
	ops = append(ops, mobileOperations()...)
	ops = append(ops, desktopOperations()...)
	ops = append(ops, browserOperations()...)
	ops = append(ops, shellTerminalOperations()...)
	ops = append(ops, inboxOperations()...)
	ops = append(ops, ticketOperations()...)
	return ops
}

// ticketOperations declares the canonical /projects/{id}/tickets operations. The
// set must stay 1:1 with the routes TicketsController.Register mounts —
// TestRouteSpecParity fails the build otherwise.
func ticketOperations() []operation {
	apiErr := func(codes ...int) []respUnit {
		out := make([]respUnit, 0, len(codes)+1)
		for _, c := range codes {
			out = append(out, respUnit{c, envelope.APIError{}})
		}
		return append(out, respUnit{http.StatusNotImplemented, envelope.APIError{}})
	}
	ticketOK := func(status int, body any, codes ...int) []respUnit {
		return append([]respUnit{{status, body}}, apiErr(codes...)...)
	}
	return []operation{
		{
			method: http.MethodGet, path: "/api/v1/projects/{id}/tickets", id: "listTickets", tag: "tickets",
			summary:    "List a project's planning tickets with derived statuses",
			pathParams: []any{controllers.ProjectIDParam{}},
			resps:      ticketOK(http.StatusOK, controllers.ListTicketsResponse{}, http.StatusBadRequest, http.StatusNotFound, http.StatusInternalServerError),
		},
		{
			method: http.MethodPost, path: "/api/v1/projects/{id}/tickets", id: "createTicket", tag: "tickets",
			summary:    "Create a ticket folder with ticket.md and spec.md and commit it",
			pathParams: []any{controllers.ProjectIDParam{}},
			reqBody:    controllers.CreateTicketRequest{},
			resps:      ticketOK(http.StatusCreated, controllers.CreateTicketResponse{}, http.StatusBadRequest, http.StatusNotFound, http.StatusInternalServerError),
		},
		{
			method: http.MethodGet, path: "/api/v1/projects/{id}/tickets/events", id: "streamTicketChanges", tag: "tickets",
			summary:    "Server-sent events: tickets_changed whenever the tickets folder changes",
			pathParams: []any{controllers.ProjectIDParam{}},
			resps: []respUnit{
				{http.StatusOK, ""},
				{http.StatusBadRequest, envelope.APIError{}},
				{http.StatusNotFound, envelope.APIError{}},
				{http.StatusInternalServerError, envelope.APIError{}},
				{http.StatusNotImplemented, envelope.APIError{}},
			},
			contentTypes: map[int]string{http.StatusOK: "text/event-stream"},
		},
		{
			method: http.MethodGet, path: "/api/v1/projects/{id}/tickets/{slug}", id: "getTicket", tag: "tickets",
			summary:    "Fetch one ticket with its plans and linked sessions",
			pathParams: []any{controllers.ProjectIDParam{}, controllers.TicketSlugParam{}},
			resps:      ticketOK(http.StatusOK, controllers.TicketResponse{}, http.StatusBadRequest, http.StatusNotFound, http.StatusInternalServerError),
		},
		{
			method: http.MethodGet, path: "/api/v1/projects/{id}/tickets/{slug}/file", id: "getTicketFile", tag: "tickets",
			summary:    "Read one markdown file inside the ticket folder",
			pathParams: []any{controllers.ProjectIDParam{}, controllers.TicketSlugParam{}, controllers.TicketFileQuery{}},
			resps:      ticketOK(http.StatusOK, controllers.TicketFileResponse{}, http.StatusBadRequest, http.StatusNotFound, http.StatusInternalServerError),
		},
		{
			method: http.MethodPut, path: "/api/v1/projects/{id}/tickets/{slug}/file", id: "saveTicketFile", tag: "tickets",
			summary:    "Write one markdown file inside the ticket folder, optionally guarded by ifUnmodifiedSince",
			pathParams: []any{controllers.ProjectIDParam{}, controllers.TicketSlugParam{}, controllers.TicketFileQuery{}},
			reqBody:    controllers.SaveTicketFileRequest{},
			resps:      ticketOK(http.StatusOK, controllers.TicketFileResponse{}, http.StatusBadRequest, http.StatusNotFound, http.StatusConflict, http.StatusInternalServerError),
		},
		{
			method: http.MethodPost, path: "/api/v1/projects/{id}/tickets/{slug}/plan", id: "planTicket", tag: "tickets",
			summary:         "Spawn the ticket's planning session in place at the project root",
			pathParams:      []any{controllers.ProjectIDParam{}, controllers.TicketSlugParam{}},
			reqBody:         controllers.PlanTicketRequest{},
			optionalReqBody: true,
			resps:           ticketOK(http.StatusCreated, controllers.SessionView{}, http.StatusBadRequest, http.StatusNotFound, http.StatusConflict, http.StatusInternalServerError),
		},
		{
			method: http.MethodPost, path: "/api/v1/projects/{id}/tickets/{slug}/archive", id: "archiveTicket", tag: "tickets",
			summary:    "Hide a ticket in the archive",
			pathParams: []any{controllers.ProjectIDParam{}, controllers.TicketSlugParam{}},
			resps:      ticketOK(http.StatusOK, controllers.TicketResponse{}, http.StatusBadRequest, http.StatusNotFound, http.StatusInternalServerError),
		},
		{
			method: http.MethodPost, path: "/api/v1/projects/{id}/tickets/{slug}/unarchive", id: "unarchiveTicket", tag: "tickets",
			summary:    "Bring an archived ticket back",
			pathParams: []any{controllers.ProjectIDParam{}, controllers.TicketSlugParam{}},
			resps:      ticketOK(http.StatusOK, controllers.TicketResponse{}, http.StatusBadRequest, http.StatusNotFound, http.StatusInternalServerError),
		},
		{
			method: http.MethodPost, path: "/api/v1/projects/{id}/tickets/{slug}/plans/{plan}/assign", id: "assignPlan", tag: "tickets",
			summary:         "Spawn an implementing session for one plan in a worktree; dryRun=1 only computes warnings",
			pathParams:      []any{controllers.ProjectIDParam{}, controllers.TicketSlugParam{}, controllers.TicketPlanParam{}, controllers.AssignPlanQuery{}},
			reqBody:         controllers.AssignPlanRequest{},
			optionalReqBody: true,
			resps:           append([]respUnit{{http.StatusOK, controllers.AssignPlanResponse{}}}, ticketOK(http.StatusCreated, controllers.AssignPlanResponse{}, http.StatusBadRequest, http.StatusNotFound, http.StatusConflict, http.StatusInternalServerError)...),
		},
		{
			method: http.MethodPost, path: "/api/v1/projects/{id}/tickets/{slug}/plans/{plan}/done", id: "markPlanDone", tag: "tickets",
			summary:    "Record a plan as done by hand",
			pathParams: []any{controllers.ProjectIDParam{}, controllers.TicketSlugParam{}, controllers.TicketPlanParam{}},
			resps:      ticketOK(http.StatusOK, controllers.TicketResponse{}, http.StatusBadRequest, http.StatusNotFound, http.StatusInternalServerError),
		},
		{
			method: http.MethodPost, path: "/api/v1/projects/{id}/tickets/{slug}/plans/{plan}/review", id: "reviewPlan", tag: "tickets",
			summary:         "Ask the planner session, or a fresh session, to review the plan's implementation",
			pathParams:      []any{controllers.ProjectIDParam{}, controllers.TicketSlugParam{}, controllers.TicketPlanParam{}},
			reqBody:         controllers.ReviewPlanRequest{},
			optionalReqBody: true,
			resps:           ticketOK(http.StatusOK, controllers.ReviewPlanResponse{}, http.StatusBadRequest, http.StatusNotFound, http.StatusConflict, http.StatusInternalServerError),
		},
		{
			method: http.MethodPost, path: "/api/v1/projects/{id}/tickets/{slug}/plans/{plan}/merge-ready", id: "reportPlanMergeReady", tag: "tickets",
			summary:         "Called by the reviewer: the branch is ready and waits for the user's merge confirmation",
			pathParams:      []any{controllers.ProjectIDParam{}, controllers.TicketSlugParam{}, controllers.TicketPlanParam{}},
			reqBody:         controllers.MergeReadyRequest{},
			optionalReqBody: true,
			resps:           ticketOK(http.StatusOK, controllers.TicketResponse{}, http.StatusBadRequest, http.StatusNotFound, http.StatusConflict, http.StatusInternalServerError),
		},
		{
			method: http.MethodPost, path: "/api/v1/projects/{id}/tickets/{slug}/plans/{plan}/merge", id: "approvePlanMerge", tag: "tickets",
			summary:    "User confirmation: tell the reviewer to merge the branch now",
			pathParams: []any{controllers.ProjectIDParam{}, controllers.TicketSlugParam{}, controllers.TicketPlanParam{}},
			resps:      ticketOK(http.StatusOK, controllers.TicketResponse{}, http.StatusBadRequest, http.StatusNotFound, http.StatusConflict, http.StatusInternalServerError),
		},
	}
}

// inboxOperations declares the canonical /projects/{id}/inbox operations. The
// set must stay 1:1 with the routes InboxController.Register mounts —
// TestRouteSpecParity fails the build otherwise.
func inboxOperations() []operation {
	return []operation{
		{
			method: http.MethodGet, path: "/api/v1/projects/{id}/inbox", id: "listInboxEvents", tag: "inbox",
			summary:    "List a project's pending orchestrator inbox events",
			pathParams: []any{controllers.ProjectIDParam{}},
			resps: []respUnit{
				{http.StatusOK, controllers.InboxResponse{}},
				{http.StatusInternalServerError, envelope.APIError{}},
				{http.StatusNotImplemented, envelope.APIError{}},
			},
		},
		{
			method: http.MethodPost, path: "/api/v1/projects/{id}/inbox/ack", id: "ackInboxEvents", tag: "inbox",
			summary:    "Acknowledge pending orchestrator inbox events by id",
			pathParams: []any{controllers.ProjectIDParam{}},
			reqBody:    controllers.AckInboxEventsRequest{},
			resps: []respUnit{
				{http.StatusOK, controllers.AckInboxEventsResponse{}},
				{http.StatusBadRequest, envelope.APIError{}},
				{http.StatusInternalServerError, envelope.APIError{}},
				{http.StatusNotImplemented, envelope.APIError{}},
			},
		},
	}
}

func browserOperations() []operation {
	return []operation{
		{
			method: http.MethodGet, path: "/api/v1/browser/status", id: "getBrowserStatus", tag: "browser",
			summary:    "Check whether the desktop browser runtime is connected for a session",
			pathParams: []any{controllers.BrowserStatusQuery{}, controllers.BrowserCapabilityHeader{}},
			resps: []respUnit{
				{http.StatusOK, controllers.BrowserStatusResponse{}},
				{http.StatusBadRequest, envelope.APIError{}},
				{http.StatusForbidden, envelope.APIError{}},
				{http.StatusNotFound, envelope.APIError{}},
				{http.StatusConflict, envelope.APIError{}},
				{http.StatusNotImplemented, envelope.APIError{}},
			},
		},
		{
			method: http.MethodPost, path: "/api/v1/browser/commands", id: "executeBrowserCommand", tag: "browser",
			summary:    "Execute a target-scoped command in a session's desktop browser",
			pathParams: []any{controllers.BrowserCapabilityHeader{}},
			reqBody:    controllers.BrowserCommandRequest{},
			resps: []respUnit{
				{http.StatusOK, controllers.BrowserCommandResponse{}},
				{http.StatusBadRequest, envelope.APIError{}},
				{http.StatusForbidden, envelope.APIError{}},
				{http.StatusNotFound, envelope.APIError{}},
				{http.StatusConflict, envelope.APIError{}},
				{http.StatusUnprocessableEntity, envelope.APIError{}},
				{http.StatusServiceUnavailable, envelope.APIError{}},
				{http.StatusNotImplemented, envelope.APIError{}},
			},
		},
	}
}

type shellTerminalBlocksQuery struct {
	Limit *int64 `query:"limit,omitempty" minimum:"1" maximum:"500" description:"Maximum blocks to return, oldest first. Defaults to 100."`
}

type claudeAccountsListQuery struct {
	Refresh *int64 `query:"refresh,omitempty" minimum:"1" maximum:"1" description:"Set to 1 to bypass the 30-second login status cache."`
}

type sessionBlocksQuery struct {
	AgentID   *string `query:"agentId,omitempty" description:"Return only this subagent's events; empty means the main conversation."`
	AfterSeq  *int64  `query:"afterSeq,omitempty" minimum:"0" description:"Return events with seq greater than this cursor. Omit to read from the start of the retained log."`
	BeforeSeq *int64  `query:"beforeSeq,omitempty" minimum:"1" description:"Return the events immediately older than this sequence, ascending. Mutually exclusive with afterSeq."`
	Limit     *int64  `query:"limit,omitempty" minimum:"1" maximum:"500" description:"Maximum events to return. Defaults to the daemon's per-session retention."`
}

func usageOperations() []operation {
	return []operation{
		{
			method: http.MethodGet, path: "/api/v1/usage/sessions", id: "listCompactSessionUsage", tag: "usage",
			summary:    "List compact token usage for session cards",
			pathParams: []any{controllers.ListUsageSessionsQuery{}},
			resps: []respUnit{
				{http.StatusOK, controllers.ListCompactSessionUsageResponse{}},
				{http.StatusInternalServerError, envelope.APIError{}},
				{http.StatusNotImplemented, envelope.APIError{}},
			},
		},
		{
			method: http.MethodGet, path: "/api/v1/usage/sessions/{sessionId}", id: "getSessionUsage", tag: "usage",
			summary:    "Get detailed token usage for one session",
			pathParams: []any{controllers.SessionIDParam{}},
			resps: []respUnit{
				{http.StatusOK, controllers.SessionUsageResponse{}},
				{http.StatusNotFound, envelope.APIError{}},
				{http.StatusInternalServerError, envelope.APIError{}},
				{http.StatusNotImplemented, envelope.APIError{}},
			},
		},
		{
			method: http.MethodGet, path: "/api/v1/usage/rollup", id: "getUsageRollup", tag: "usage",
			summary:    "Get day or week token usage rollups",
			pathParams: []any{controllers.UsageRollupQuery{}},
			resps: []respUnit{
				{http.StatusOK, controllers.UsageRollupResponse{}},
				{http.StatusBadRequest, envelope.APIError{}},
				{http.StatusInternalServerError, envelope.APIError{}},
				{http.StatusNotImplemented, envelope.APIError{}},
			},
		},
		{
			method: http.MethodGet, path: "/api/v1/usage/quota", id: "getUsageQuota", tag: "usage",
			summary: "Get the account's latest Codex quota position",
			resps: []respUnit{
				{http.StatusOK, controllers.UsageQuotaEnvelope{}},
				{http.StatusInternalServerError, envelope.APIError{}},
				{http.StatusNotImplemented, envelope.APIError{}},
			},
		},
	}
}

// shellTerminalOperations describes the standalone shell terminal surface:
// shells the user opens by hand, with no agent session behind them.
func shellTerminalOperations() []operation {
	return []operation{
		{
			method: http.MethodGet, path: "/api/v1/settings", id: "getSettings", tag: "settings",
			summary: "Read the daemon-owned user preferences",
			resps: []respUnit{
				{http.StatusOK, controllers.SettingsResponse{}},
				{http.StatusInternalServerError, envelope.APIError{}},
				{http.StatusNotImplemented, envelope.APIError{}},
			},
		},
		{
			method: http.MethodPatch, path: "/api/v1/settings/ui", id: "updateUiSettings", tag: "settings",
			summary: "Set the desktop presentation locale",
			reqBody: controllers.UiSettings{},
			resps: []respUnit{
				{http.StatusOK, controllers.SettingsResponse{}},
				{http.StatusBadRequest, envelope.APIError{}},
				{http.StatusInternalServerError, envelope.APIError{}},
				{http.StatusNotImplemented, envelope.APIError{}},
			},
		},
		{
			method: http.MethodPatch, path: "/api/v1/settings/updates", id: "setUpdateSettings", tag: "settings",
			summary: "Set the desktop auto-update opt-in state",
			reqBody: settingssvc.UpdateSettings{},
			resps: []respUnit{
				{http.StatusOK, controllers.SettingsResponse{}},
				{http.StatusBadRequest, envelope.APIError{}},
				{http.StatusInternalServerError, envelope.APIError{}},
				{http.StatusNotImplemented, envelope.APIError{}},
			},
		},
		{
			method: http.MethodPatch, path: "/api/v1/settings/keybindings", id: "setKeybindingOverrides", tag: "settings",
			summary: "Set the persisted desktop shortcut overrides",
			reqBody: settingssvc.KeybindingOverrides{},
			resps: []respUnit{
				{http.StatusOK, controllers.SettingsResponse{}},
				{http.StatusBadRequest, envelope.APIError{}},
				{http.StatusInternalServerError, envelope.APIError{}},
				{http.StatusNotImplemented, envelope.APIError{}},
			},
		},
		{
			method: http.MethodGet, path: "/api/v1/shell-terminals", id: "listShellTerminals", tag: "shellTerminals",
			summary: "List the standalone shell terminals owned by the current app run",
			resps: []respUnit{
				{http.StatusOK, controllers.ListShellTerminalsResponse{}},
				{http.StatusInternalServerError, envelope.APIError{}},
				{http.StatusNotImplemented, envelope.APIError{}},
			},
		},
		{
			method: http.MethodPost, path: "/api/v1/shell-terminals", id: "openShellTerminal", tag: "shellTerminals",
			summary: "Open a standalone shell terminal",
			reqBody: controllers.OpenShellTerminalRequest{},
			resps: []respUnit{
				{http.StatusCreated, controllers.ShellTerminalEnvelope{}},
				{http.StatusBadRequest, envelope.APIError{}},
				{http.StatusNotFound, envelope.APIError{}},
				{http.StatusInternalServerError, envelope.APIError{}},
				{http.StatusNotImplemented, envelope.APIError{}},
			},
		},
		{
			method: http.MethodPatch, path: "/api/v1/shell-terminals/{handleId}", id: "renameShellTerminal", tag: "shellTerminals",
			summary:    "Rename a standalone shell terminal tab",
			pathParams: []any{controllers.ShellTerminalHandleIDParam{}},
			reqBody:    controllers.UpdateShellTerminalRequest{},
			resps: []respUnit{
				{http.StatusOK, controllers.ShellTerminalEnvelope{}},
				{http.StatusBadRequest, envelope.APIError{}},
				{http.StatusNotFound, envelope.APIError{}},
				{http.StatusInternalServerError, envelope.APIError{}},
				{http.StatusNotImplemented, envelope.APIError{}},
			},
		},
		{
			method: http.MethodDelete, path: "/api/v1/shell-terminals/{handleId}", id: "closeShellTerminal", tag: "shellTerminals",
			summary:    "Close a standalone shell terminal and destroy its PTY",
			pathParams: []any{controllers.ShellTerminalHandleIDParam{}},
			resps: []respUnit{
				{http.StatusNoContent, nil},
				{http.StatusBadRequest, envelope.APIError{}},
				{http.StatusNotFound, envelope.APIError{}},
				{http.StatusInternalServerError, envelope.APIError{}},
				{http.StatusNotImplemented, envelope.APIError{}},
			},
		},
		{
			method: http.MethodGet, path: "/api/v1/shell-terminals/{handleId}/blocks", id: "listShellTerminalBlocks", tag: "shellTerminals",
			summary:    "Read a shell terminal's retained raw block history, oldest first",
			pathParams: []any{controllers.ShellTerminalHandleIDParam{}, shellTerminalBlocksQuery{}},
			resps: []respUnit{
				{http.StatusOK, []controllers.TerminalBlockView{}},
				{http.StatusBadRequest, envelope.APIError{}},
				{http.StatusNotFound, envelope.APIError{}},
				{http.StatusInternalServerError, envelope.APIError{}},
				{http.StatusNotImplemented, envelope.APIError{}},
			},
		},
		{
			method: http.MethodGet, path: "/api/v1/claude-accounts", id: "listClaudeAccounts", tag: "claudeAccounts",
			summary:    "List Claude accounts, default first, with login status and shared setup state",
			pathParams: []any{claudeAccountsListQuery{}},
			resps: []respUnit{
				{http.StatusOK, controllers.ListClaudeAccountsResponse{}},
				{http.StatusInternalServerError, envelope.APIError{}},
				{http.StatusNotImplemented, envelope.APIError{}},
			},
		},
		{
			method: http.MethodPost, path: "/api/v1/claude-accounts", id: "createClaudeAccount", tag: "claudeAccounts",
			summary: "Add a Claude account folder at ~/.claude-<name> and link the shared setup",
			reqBody: controllers.CreateClaudeAccountRequest{},
			resps: []respUnit{
				{http.StatusCreated, controllers.ClaudeAccountEnvelope{}},
				{http.StatusBadRequest, envelope.APIError{}},
				{http.StatusConflict, envelope.APIError{}},
				{http.StatusNotImplemented, envelope.APIError{}},
			},
		},
		{
			method: http.MethodPatch, path: "/api/v1/claude-accounts/{accountId}", id: "renameClaudeAccount", tag: "claudeAccounts",
			summary:    "Rename a Claude account label; the folder never changes",
			pathParams: []any{controllers.ClaudeAccountIDParam{}},
			reqBody:    controllers.RenameClaudeAccountRequest{},
			resps: []respUnit{
				{http.StatusOK, controllers.ClaudeAccountEnvelope{}},
				{http.StatusBadRequest, envelope.APIError{}},
				{http.StatusNotFound, envelope.APIError{}},
				{http.StatusConflict, envelope.APIError{}},
				{http.StatusNotImplemented, envelope.APIError{}},
			},
		},
		{
			method: http.MethodDelete, path: "/api/v1/claude-accounts/{accountId}", id: "deleteClaudeAccount", tag: "claudeAccounts",
			summary:    "Unregister a Claude account; its folder stays on disk",
			pathParams: []any{controllers.ClaudeAccountIDParam{}},
			resps: []respUnit{
				{http.StatusNoContent, nil},
				{http.StatusNotFound, envelope.APIError{}},
				{http.StatusConflict, envelope.APIError{}},
				{http.StatusNotImplemented, envelope.APIError{}},
			},
		},
		{
			method: http.MethodPost, path: "/api/v1/claude-accounts/{accountId}/login", id: "loginClaudeAccount", tag: "claudeAccounts",
			summary:    "Open a terminal running Claude against the account folder for /login",
			pathParams: []any{controllers.ClaudeAccountIDParam{}},
			reqBody:    controllers.ClaudeAccountLoginRequest{},
			resps: []respUnit{
				{http.StatusCreated, controllers.ShellTerminalEnvelope{}},
				{http.StatusNotFound, envelope.APIError{}},
				{http.StatusConflict, envelope.APIError{}},
				{http.StatusNotImplemented, envelope.APIError{}},
			},
		},
		{
			method: http.MethodPost, path: "/api/v1/claude-accounts/{accountId}/prefer", id: "preferClaudeAccount", tag: "claudeAccounts",
			summary:    "Make this the account new Claude Code sessions use unless one is chosen",
			pathParams: []any{controllers.ClaudeAccountIDParam{}},
			resps: []respUnit{
				{http.StatusOK, controllers.ClaudeAccountEnvelope{}},
				{http.StatusNotFound, envelope.APIError{}},
				{http.StatusNotImplemented, envelope.APIError{}},
			},
		},
		{
			method: http.MethodPost, path: "/api/v1/claude-accounts/{accountId}/relink", id: "relinkClaudeAccount", tag: "claudeAccounts",
			summary:    "Back up files that replaced shared setup links, then re-link them",
			pathParams: []any{controllers.ClaudeAccountIDParam{}},
			resps: []respUnit{
				{http.StatusNoContent, nil},
				{http.StatusNotFound, envelope.APIError{}},
				{http.StatusConflict, envelope.APIError{}},
				{http.StatusNotImplemented, envelope.APIError{}},
			},
		},
	}
}

func agentOperations() []operation {
	return []operation{
		{
			method: http.MethodGet, path: "/api/v1/agents", id: "listAgents", tag: "agents",
			summary: "Return cached supported and locally installed agent adapters",
			resps: []respUnit{
				{http.StatusOK, controllers.ListAgentsResponse{}},
				{http.StatusInternalServerError, envelope.APIError{}},
				{http.StatusNotImplemented, envelope.APIError{}},
			},
		},
		{
			method: http.MethodPost, path: "/api/v1/agents/refresh", id: "refreshAgents", tag: "agents",
			summary: "Refresh the cached local agent adapter catalog",
			resps: []respUnit{
				{http.StatusOK, controllers.RefreshAgentsResponse{}},
				{http.StatusInternalServerError, envelope.APIError{}},
				{http.StatusNotImplemented, envelope.APIError{}},
			},
		},
		{
			method: http.MethodPost, path: "/api/v1/agents/{agent}/probe", id: "probeAgent", tag: "agents",
			summary:    "Run a fresh local readiness probe for one agent adapter",
			pathParams: []any{controllers.AgentIDParam{}},
			resps: []respUnit{
				{http.StatusOK, controllers.ProbeAgentResponse{}},
				{http.StatusBadRequest, envelope.APIError{}},
				{http.StatusInternalServerError, envelope.APIError{}},
				{http.StatusNotImplemented, envelope.APIError{}},
			},
		},
		{
			method: http.MethodGet, path: "/api/v1/agents/{agent}/models", id: "getAgentModels", tag: "agents",
			summary:    "Return the cached model picker for one agent, discovering it on first use",
			pathParams: []any{controllers.AgentIDParam{}, controllers.AgentModelsQuery{}},
			resps: []respUnit{
				{http.StatusOK, controllers.AgentModelsResponse{}},
				{http.StatusBadRequest, envelope.APIError{}},
				{http.StatusNotFound, envelope.APIError{}},
				{http.StatusInternalServerError, envelope.APIError{}},
				{http.StatusNotImplemented, envelope.APIError{}},
			},
		},
		{
			method: http.MethodPost, path: "/api/v1/agents/{agent}/models/refresh", id: "refreshAgentModels", tag: "agents",
			summary:    "Refresh and cache the model picker for one agent",
			pathParams: []any{controllers.AgentIDParam{}, controllers.AgentModelsRefreshQuery{}},
			resps: []respUnit{
				{http.StatusOK, controllers.AgentModelsResponse{}},
				{http.StatusBadRequest, envelope.APIError{}},
				{http.StatusNotFound, envelope.APIError{}},
				{http.StatusInternalServerError, envelope.APIError{}},
				{http.StatusNotImplemented, envelope.APIError{}},
			},
		},
	}
}

// mobileOperations declares the 4 /mobile control operations. These are
// mounted on the loopback router (mountMobile in router.go), not the REST
// /api/v1 group — only the desktop/CLI may enable, disable, or regenerate the
// phone's LAN access; the phone never toggles its own connection. Must stay
// 1:1 with the routes mountMobile registers (enforced by the parity test).
func mobileOperations() []operation {
	return []operation{
		{
			method: http.MethodGet, path: "/api/v1/mobile/status", id: "getMobileStatus", tag: "mobile",
			summary: "Check whether Connect Mobile's LAN bridge is enabled",
			resps: []respUnit{
				{http.StatusOK, controllers.MobileStatusResponse{}},
				{http.StatusForbidden, envelope.APIError{}},
			},
		},
		{
			method: http.MethodPost, path: "/api/v1/mobile/enable", id: "enableMobile", tag: "mobile",
			summary: "Enable the Connect Mobile LAN bridge and issue a fresh password",
			resps: []respUnit{
				{http.StatusOK, controllers.MobileStatusResponse{}},
				{http.StatusForbidden, envelope.APIError{}},
				{http.StatusInternalServerError, envelope.APIError{}},
			},
		},
		{
			method: http.MethodPost, path: "/api/v1/mobile/disable", id: "disableMobile", tag: "mobile",
			summary: "Disable the Connect Mobile LAN bridge",
			resps: []respUnit{
				{http.StatusOK, controllers.MobileStatusResponse{}},
				{http.StatusForbidden, envelope.APIError{}},
				{http.StatusInternalServerError, envelope.APIError{}},
			},
		},
		{
			method: http.MethodPost, path: "/api/v1/mobile/regenerate", id: "regenerateMobile", tag: "mobile",
			summary: "Rotate the Connect Mobile password, dropping any connected phone",
			resps: []respUnit{
				{http.StatusOK, controllers.MobileStatusResponse{}},
				{http.StatusForbidden, envelope.APIError{}},
				{http.StatusInternalServerError, envelope.APIError{}},
			},
		},
		{
			method: http.MethodPost, path: "/api/v1/mobile/tunnel/enable", id: "enableMobileTunnel", tag: "mobile",
			summary: "Make the Connect Mobile bridge reachable from the internet",
			resps: []respUnit{
				{http.StatusOK, controllers.MobileStatusResponse{}},
				{http.StatusForbidden, envelope.APIError{}},
				{http.StatusInternalServerError, envelope.APIError{}},
			},
		},
		{
			method: http.MethodPost, path: "/api/v1/mobile/tunnel/disable", id: "disableMobileTunnel", tag: "mobile",
			summary: "Stop the public tunnel, leaving the LAN bridge running",
			resps: []respUnit{
				{http.StatusOK, controllers.MobileStatusResponse{}},
				{http.StatusForbidden, envelope.APIError{}},
				{http.StatusInternalServerError, envelope.APIError{}},
			},
		},
		{
			method: http.MethodPost, path: "/api/v1/mobile/tunnel/authtoken", id: "setMobileTunnelAuthtoken", tag: "mobile",
			summary: "Store an ngrok authtoken for a stable tunnel address",
			reqBody: controllers.MobileAuthtokenRequest{},
			resps: []respUnit{
				{http.StatusOK, controllers.MobileStatusResponse{}},
				{http.StatusBadRequest, envelope.APIError{}},
				{http.StatusForbidden, envelope.APIError{}},
			},
		},
		{
			method: http.MethodDelete, path: "/api/v1/mobile/tunnel/authtoken", id: "removeMobileTunnelAuthtoken", tag: "mobile",
			summary: "Remove the stored ngrok authtoken",
			resps: []respUnit{
				{http.StatusOK, controllers.MobileStatusResponse{}},
				{http.StatusForbidden, envelope.APIError{}},
				{http.StatusInternalServerError, envelope.APIError{}},
			},
		},
		{
			method: http.MethodGet, path: "/api/v1/mobile/tunnel/ngrok", id: "getMobileNgrok", tag: "mobile",
			summary: "Get the current ngrok tunnel status",
			resps: []respUnit{
				{http.StatusOK, controllers.MobileNgrokStatus{}},
				{http.StatusForbidden, envelope.APIError{}},
			},
		},
		{
			method: http.MethodPut, path: "/api/v1/mobile/tunnel/ngrok/api-key", id: "setMobileNgrokAPIKey", tag: "mobile",
			summary: "Store an ngrok API key",
			reqBody: controllers.MobileNgrokAPIKeyRequest{},
			resps: []respUnit{
				{http.StatusOK, controllers.MobileNgrokAccount{}},
				{http.StatusBadRequest, envelope.APIError{}},
				{http.StatusUnauthorized, envelope.APIError{}},
				{http.StatusBadGateway, envelope.APIError{}},
				{http.StatusForbidden, envelope.APIError{}},
			},
		},
		{
			method: http.MethodDelete, path: "/api/v1/mobile/tunnel/ngrok/api-key", id: "removeMobileNgrokAPIKey", tag: "mobile",
			summary: "Remove the stored ngrok API key",
			resps: []respUnit{
				{http.StatusOK, controllers.MobileNgrokStatus{}},
				{http.StatusForbidden, envelope.APIError{}},
				{http.StatusInternalServerError, envelope.APIError{}},
			},
		},
		{
			method: http.MethodGet, path: "/api/v1/mobile/tunnel/ngrok/account", id: "getMobileNgrokAccount", tag: "mobile",
			summary: "Get the ngrok account's credentials, sessions, endpoints and reserved domains",
			resps: []respUnit{
				{http.StatusOK, controllers.MobileNgrokAccount{}},
				{http.StatusForbidden, envelope.APIError{}},
			},
		},
		{
			method: http.MethodPost, path: "/api/v1/mobile/tunnel/ngrok/account/credential", id: "mintMobileNgrokCredential", tag: "mobile",
			summary: "Mint a fresh operator-owned ngrok API credential",
			resps: []respUnit{
				{http.StatusOK, controllers.MobileNgrokStatus{}},
				{http.StatusUnauthorized, envelope.APIError{}},
				{http.StatusBadGateway, envelope.APIError{}},
				{http.StatusForbidden, envelope.APIError{}},
			},
		},
		{
			method: http.MethodDelete, path: "/api/v1/mobile/tunnel/ngrok/account/credential/{id}", id: "revokeMobileNgrokCredential", tag: "mobile",
			summary:    "Revoke an ngrok API credential",
			pathParams: []any{controllers.MobileNgrokCredentialIDParam{}},
			resps: []respUnit{
				{http.StatusOK, controllers.MobileNgrokAccount{}},
				{http.StatusUnauthorized, envelope.APIError{}},
				{http.StatusBadGateway, envelope.APIError{}},
				{http.StatusForbidden, envelope.APIError{}},
			},
		},
		{
			method: http.MethodPut, path: "/api/v1/mobile/tunnel/ngrok/domain", id: "setMobileNgrokDomain", tag: "mobile",
			summary: "Set the reserved ngrok domain the tunnel uses",
			reqBody: controllers.MobileNgrokDomainRequest{},
			resps: []respUnit{
				{http.StatusOK, controllers.MobileNgrokStatus{}},
				{http.StatusBadRequest, envelope.APIError{}},
				{http.StatusForbidden, envelope.APIError{}},
			},
		},
		{
			method: http.MethodPost, path: "/api/v1/mobile/tunnel/ngrok/diagnose", id: "diagnoseMobileNgrok", tag: "mobile",
			summary: "Run ngrok tunnel diagnostics",
			resps: []respUnit{
				{http.StatusOK, controllers.MobileNgrokDiagnosis{}},
				{http.StatusForbidden, envelope.APIError{}},
			},
		},
	}
}

// desktopOperations declares the single /desktop operation. Must stay 1:1
// with the route DesktopController.Register mounts (enforced by the parity
// test).
func desktopOperations() []operation {
	return []operation{
		{
			method: http.MethodGet, path: "/api/v1/desktop", id: "getDesktop", tag: "desktop",
			summary: "Identify this desktop to an authenticated phone",
			resps: []respUnit{
				{http.StatusOK, controllers.DesktopResponse{}},
			},
		},
	}
}

// devOperations declares developer-only API operations. Must stay 1:1 with
// the routes DevController.Register mounts (enforced by the parity test).
func devOperations() []operation {
	return []operation{
		{
			method: http.MethodPost, path: "/api/v1/dev/import-projects", id: "runDevImportProjects", tag: "dev",
			summary: "Run the developer project-registry import through the daemon store",
			reqBody: controllers.DevImportProjectsRequest{},
			resps: []respUnit{
				{http.StatusOK, controllers.DevImportProjectsResponse{}},
				{http.StatusBadRequest, envelope.APIError{}},
				{http.StatusInternalServerError, envelope.APIError{}},
				{http.StatusNotImplemented, envelope.APIError{}},
			},
		},
		{
			method: http.MethodPost, path: "/api/v1/dev/import-scan", id: "runDevImportScan", tag: "dev",
			summary: "Scan a local folder for importable Git repositories",
			reqBody: controllers.DevImportScanRequest{},
			resps: []respUnit{
				{http.StatusOK, projectscan.Result{}},
				{http.StatusBadRequest, envelope.APIError{}},
				{http.StatusInternalServerError, envelope.APIError{}},
				{http.StatusNotImplemented, envelope.APIError{}},
			},
		},
		{
			method: http.MethodPost, path: "/api/v1/dev/ancestor-repository", id: "findDevAncestorRepository", tag: "dev",
			summary: "Report whether a folder sits inside an existing Git repository",
			reqBody: controllers.DevAncestorRepositoryRequest{},
			resps: []respUnit{
				{http.StatusOK, controllers.DevAncestorRepositoryResponse{}},
				{http.StatusBadRequest, envelope.APIError{}},
				{http.StatusInternalServerError, envelope.APIError{}},
				{http.StatusNotImplemented, envelope.APIError{}},
			},
		},
		{
			method: http.MethodPost, path: "/api/v1/dev/block-replay", id: "runDevBlockReplay", tag: "dev",
			summary: "Drive a synthetic block-event stream through the real Record path (dev-only, gated by OPERATOR_DEV_BLOCK_REPLAY=1)",
			reqBody: controllers.DevBlockReplayRequest{},
			resps: []respUnit{
				{http.StatusAccepted, controllers.DevBlockReplayResponse{}},
				{http.StatusBadRequest, envelope.APIError{}},
				{http.StatusNotImplemented, envelope.APIError{}},
			},
		},
	}
}

func notificationOperations() []operation {
	return []operation{
		{
			method: http.MethodGet, path: "/api/v1/notifications", id: "listNotifications", tag: "notifications",
			summary:    "List notification history",
			pathParams: []any{controllers.ListNotificationsQuery{}},
			resps: []respUnit{
				{http.StatusOK, controllers.ListNotificationsResponse{}},
				{http.StatusBadRequest, envelope.APIError{}},
				{http.StatusInternalServerError, envelope.APIError{}},
				{http.StatusNotImplemented, envelope.APIError{}},
			},
		},
		{
			method: http.MethodPatch, path: "/api/v1/notifications/{id}", id: "markNotificationRead", tag: "notifications",
			summary:    "Mark a notification read",
			pathParams: []any{controllers.NotificationIDParam{}},
			reqBody:    controllers.MarkNotificationReadRequest{},
			resps: []respUnit{
				{http.StatusOK, controllers.NotificationEnvelope{}},
				{http.StatusBadRequest, envelope.APIError{}},
				{http.StatusNotFound, envelope.APIError{}},
				{http.StatusInternalServerError, envelope.APIError{}},
				{http.StatusNotImplemented, envelope.APIError{}},
			},
		},
		{
			method: http.MethodPost, path: "/api/v1/notifications/read-all", id: "markAllNotificationsRead", tag: "notifications",
			summary: "Mark notifications read",
			reqBody: controllers.MarkAllNotificationsReadRequest{},
			resps: []respUnit{
				{http.StatusOK, controllers.MarkAllNotificationsReadResponse{}},
				{http.StatusBadRequest, envelope.APIError{}},
				{http.StatusInternalServerError, envelope.APIError{}},
				{http.StatusNotImplemented, envelope.APIError{}},
			},
		},
		{
			method: http.MethodGet, path: "/api/v1/notifications/stream", id: "streamNotifications", tag: "notifications",
			summary:    "Stream created notifications",
			pathParams: []any{controllers.NotificationStreamQuery{}},
			resps: []respUnit{
				{http.StatusOK, ""},
				{http.StatusInternalServerError, envelope.APIError{}},
				{http.StatusNotImplemented, envelope.APIError{}},
			},
			contentTypes: map[int]string{http.StatusOK: "text/event-stream"},
		},
	}
}

// reviewOperations declares the session-scoped /reviews operations. Must stay
// 1:1 with the routes ReviewsController.Register mounts (enforced by the parity
// test).
// pushOperations declares the /push/devices operations. Must stay 1:1 with the
// routes PushController.Register mounts (enforced by the parity test).
func pushOperations() []operation {
	return []operation{
		{
			method: http.MethodPost, path: "/api/v1/push/devices", id: "registerPushDevice", tag: "push",
			summary: "Register (upsert) a phone's Expo push token",
			reqBody: controllers.RegisterPushDeviceRequest{},
			resps: []respUnit{
				{http.StatusOK, controllers.PushDeviceEnvelope{}},
				{http.StatusBadRequest, envelope.APIError{}},
				{http.StatusInternalServerError, envelope.APIError{}},
				{http.StatusNotImplemented, envelope.APIError{}},
			},
		},
		{
			method: http.MethodDelete, path: "/api/v1/push/devices/{token}", id: "unregisterPushDevice", tag: "push",
			summary:    "Unregister a phone's Expo push token",
			pathParams: []any{controllers.PushDeviceTokenParam{}},
			resps: []respUnit{
				{http.StatusOK, controllers.UnregisterPushDeviceResponse{}},
				{http.StatusInternalServerError, envelope.APIError{}},
				{http.StatusNotImplemented, envelope.APIError{}},
			},
		},
	}
}

func reviewOperations() []operation {
	return []operation{
		{
			method: http.MethodGet, path: "/api/v1/sessions/{sessionId}/reviews", id: "listReviews", tag: "reviews",
			summary:    "List a worker's code-review runs",
			pathParams: []any{controllers.SessionIDParam{}},
			resps: []respUnit{
				{http.StatusOK, controllers.ListReviewsResponse{}},
				{http.StatusUnprocessableEntity, envelope.APIError{}},
				{http.StatusNotImplemented, envelope.APIError{}},
			},
		},
		{
			method: http.MethodPost, path: "/api/v1/sessions/{sessionId}/reviews/trigger", id: "triggerReview", tag: "reviews",
			summary:    "Trigger a code review of a worker's PR",
			pathParams: []any{controllers.SessionIDParam{}},
			// Optional: an empty body runs under the project's configured reviewer.
			reqBody:         controllers.TriggerReviewRequest{},
			optionalReqBody: true,
			resps: []respUnit{
				{http.StatusOK, controllers.TriggerReviewResponse{}},
				{http.StatusCreated, controllers.TriggerReviewResponse{}},
				{http.StatusUnprocessableEntity, envelope.APIError{}},
				{http.StatusNotFound, envelope.APIError{}},
				{http.StatusNotImplemented, envelope.APIError{}},
			},
		},
		{
			method: http.MethodPost, path: "/api/v1/sessions/{sessionId}/reviews/cancel", id: "cancelReview", tag: "reviews",
			summary:    "Cancel a running code review",
			pathParams: []any{controllers.SessionIDParam{}},
			resps: []respUnit{
				{http.StatusOK, controllers.CancelReviewResponse{}},
				{http.StatusUnprocessableEntity, envelope.APIError{}},
				{http.StatusNotFound, envelope.APIError{}},
				{http.StatusNotImplemented, envelope.APIError{}},
			},
		},
		{
			method: http.MethodPost, path: "/api/v1/sessions/{sessionId}/reviews/kill", id: "killReviewSession", tag: "reviews",
			summary:    "Kill a worker's reviewer terminal session",
			pathParams: []any{controllers.SessionIDParam{}},
			resps: []respUnit{
				{http.StatusOK, controllers.KillReviewResponse{}},
				{http.StatusUnprocessableEntity, envelope.APIError{}},
				{http.StatusNotFound, envelope.APIError{}},
				{http.StatusNotImplemented, envelope.APIError{}},
			},
		},
		{
			method: http.MethodPost, path: "/api/v1/sessions/{sessionId}/reviews/restore", id: "restoreReviewSession", tag: "reviews",
			summary:    "Restore a worker's reviewer terminal session",
			pathParams: []any{controllers.SessionIDParam{}},
			resps: []respUnit{
				{http.StatusOK, controllers.RestoreReviewResponse{}},
				{http.StatusUnprocessableEntity, envelope.APIError{}},
				{http.StatusNotFound, envelope.APIError{}},
				{http.StatusNotImplemented, envelope.APIError{}},
			},
		},
		{
			method: http.MethodPost, path: "/api/v1/sessions/{sessionId}/reviews/switch", id: "switchReviewSession", tag: "reviews",
			summary:    "Switch a worker's reviewer harness",
			pathParams: []any{controllers.SessionIDParam{}},
			reqBody:    controllers.SetSessionReviewerRequest{},
			resps: []respUnit{
				{http.StatusOK, controllers.ListReviewsResponse{}},
				{http.StatusBadRequest, envelope.APIError{}},
				{http.StatusUnprocessableEntity, envelope.APIError{}},
				{http.StatusNotFound, envelope.APIError{}},
				{http.StatusNotImplemented, envelope.APIError{}},
			},
		},
		{
			method: http.MethodPost, path: "/api/v1/sessions/{sessionId}/reviews/submit", id: "submitReview", tag: "reviews",
			summary:    "Record a reviewer's result for a worker's PR",
			pathParams: []any{controllers.SessionIDParam{}},
			reqBody:    controllers.SubmitReviewInput{},
			resps: []respUnit{
				{http.StatusOK, controllers.ReviewRunResponse{}},
				{http.StatusBadRequest, envelope.APIError{}},
				{http.StatusUnprocessableEntity, envelope.APIError{}},
				{http.StatusNotFound, envelope.APIError{}},
				{http.StatusNotImplemented, envelope.APIError{}},
			},
		},
	}
}

type eventsQuery struct {
	After      *int64 `query:"after,omitempty" minimum:"0" description:"Replay events with seq greater than this cursor. When omitted, clients may send Last-Event-ID instead."`
	FromLatest *bool  `query:"fromLatest,omitempty" description:"Start at the current log head and replay nothing. Ignored when after is present."`
}

func eventOperations() []operation {
	return []operation{
		{
			method: http.MethodGet, path: "/api/v1/events", id: "streamEvents", tag: "events",
			summary:    "Stream CDC events with durable replay",
			pathParams: []any{eventsQuery{}},
			resps: []respUnit{
				{http.StatusOK, ""},
				{status: http.StatusBadRequest, body: envelope.APIError{}},
				{status: http.StatusInternalServerError, body: envelope.APIError{}},
				{status: http.StatusNotImplemented, body: envelope.APIError{}},
			},
			contentTypes: map[int]string{http.StatusOK: "text/event-stream"},
		},
	}
}

// projectOperations declares the canonical /projects operations. The set must
// stay 1:1 with the routes ProjectsController.Register mounts —
// TestRouteSpecParity fails the build otherwise.
func projectOperations() []operation {
	return []operation{
		{
			method: http.MethodGet, path: "/api/v1/projects", id: "listProjects", tag: "projects",
			summary: "List all registered projects (active + degraded)",
			resps: []respUnit{
				{http.StatusOK, controllers.ListProjectsResponse{}},
				{http.StatusInternalServerError, envelope.APIError{}},
			},
		},
		{
			method: http.MethodPost, path: "/api/v1/projects", id: "addProject", tag: "projects",
			summary: "Register a new project from a git repository path",
			reqBody: projectsvc.AddInput{},
			resps: []respUnit{
				{http.StatusCreated, controllers.ProjectResponse{}},
				{http.StatusBadRequest, envelope.APIError{}},
				{http.StatusConflict, envelope.APIError{}},
				{http.StatusInternalServerError, envelope.APIError{}},
			},
		},
		{
			method: http.MethodPost, path: "/api/v1/projects/initialize", id: "initializeProjectRepository", tag: "projects",
			summary: "Initialize a selected folder as a Git repository with an initial commit",
			reqBody: projectsvc.InitializeRepositoryInput{},
			resps: []respUnit{
				{http.StatusOK, projectsvc.InitializeRepositoryResult{}},
				{http.StatusBadRequest, envelope.APIError{}},
				{http.StatusConflict, envelope.APIError{}},
				{http.StatusInternalServerError, envelope.APIError{}},
			},
		}, {
			method: http.MethodGet, path: "/api/v1/projects/{id}", id: "getProject", tag: "projects",
			summary:    "Fetch one project; discriminates ok vs degraded",
			pathParams: []any{controllers.ProjectIDParam{}},
			resps: []respUnit{
				{http.StatusOK, controllers.GetProjectResponse{}},
				{http.StatusNotFound, envelope.APIError{}},
				{http.StatusInternalServerError, envelope.APIError{}},
			},
		},
		{
			method: http.MethodPut, path: "/api/v1/projects/{id}", id: "updateProjectSettings", tag: "projects",
			summary:    "Atomically replace a project's display name and config",
			pathParams: []any{controllers.ProjectIDParam{}},
			reqBody:    projectsvc.UpdateSettingsInput{},
			resps: []respUnit{
				{http.StatusOK, controllers.ProjectResponse{}},
				{http.StatusBadRequest, envelope.APIError{}},
				{http.StatusNotFound, envelope.APIError{}},
				{http.StatusInternalServerError, envelope.APIError{}},
			},
		},
		{
			method: http.MethodPut, path: "/api/v1/projects/{id}/config", id: "setProjectConfig", tag: "projects",
			summary:    "Replace a project's per-project config",
			pathParams: []any{controllers.ProjectIDParam{}},
			reqBody:    projectsvc.SetConfigInput{},
			resps: []respUnit{
				{http.StatusOK, controllers.ProjectResponse{}},
				{http.StatusBadRequest, envelope.APIError{}},
				{http.StatusNotFound, envelope.APIError{}},
				{http.StatusInternalServerError, envelope.APIError{}},
			},
		},
		{
			method: http.MethodDelete, path: "/api/v1/projects/{id}", id: "removeProject", tag: "projects",
			summary:    "Remove a project; stops sessions, cleans workspaces, unregisters",
			pathParams: []any{controllers.ProjectIDParam{}},
			resps: []respUnit{
				{http.StatusOK, projectsvc.RemoveResult{}},
				{http.StatusBadRequest, envelope.APIError{}},
				{http.StatusNotFound, envelope.APIError{}},
				{http.StatusInternalServerError, envelope.APIError{}},
			},
		},
	}
}

func sessionOperations() []operation {
	return []operation{
		{
			method: http.MethodGet, path: "/api/v1/sessions", id: "listSessions", tag: "sessions",
			summary:    "List sessions",
			pathParams: []any{controllers.ListSessionsQuery{}},
			resps: []respUnit{
				{http.StatusOK, controllers.ListSessionsResponse{}},
				{http.StatusBadRequest, envelope.APIError{}},
				{http.StatusInternalServerError, envelope.APIError{}},
			},
		},
		{
			method: http.MethodPost, path: "/api/v1/sessions", id: "spawnSession", tag: "sessions",
			summary: "Spawn a new agent session",
			reqBody: controllers.SpawnSessionRequest{},
			resps: []respUnit{
				{http.StatusCreated, controllers.SpawnSessionResponse{}},
				{http.StatusBadRequest, envelope.APIError{}},
				{http.StatusNotFound, envelope.APIError{}},
				{http.StatusInternalServerError, envelope.APIError{}},
			},
		},
		{
			method: http.MethodGet, path: "/api/v1/sessions/{sessionId}", id: "getSession", tag: "sessions",
			summary:    "Fetch one session",
			pathParams: []any{controllers.SessionIDParam{}},
			resps: []respUnit{
				{http.StatusOK, controllers.SessionResponse{}},
				{http.StatusNotFound, envelope.APIError{}},
				{http.StatusInternalServerError, envelope.APIError{}},
			},
		},
		{
			method: http.MethodPost, path: "/api/v1/sessions/{sessionId}/pin", id: "pinSession", tag: "sessions",
			summary:    "Pin a session",
			pathParams: []any{controllers.SessionIDParam{}},
			resps: []respUnit{
				{http.StatusOK, controllers.SessionResponse{}},
				{http.StatusNotFound, envelope.APIError{}},
				{http.StatusInternalServerError, envelope.APIError{}},
				{http.StatusNotImplemented, envelope.APIError{}},
			},
		},
		{
			method: http.MethodDelete, path: "/api/v1/sessions/{sessionId}/pin", id: "unpinSession", tag: "sessions",
			summary:    "Unpin a session",
			pathParams: []any{controllers.SessionIDParam{}},
			resps: []respUnit{
				{http.StatusOK, controllers.SessionResponse{}},
				{http.StatusNotFound, envelope.APIError{}},
				{http.StatusInternalServerError, envelope.APIError{}},
				{http.StatusNotImplemented, envelope.APIError{}},
			},
		},
		{
			method: http.MethodGet, path: "/api/v1/sessions/{sessionId}/preview", id: "getSessionPreview", tag: "sessions",
			summary:    "Discover a browser preview URL for a session workspace",
			pathParams: []any{controllers.SessionIDParam{}},
			resps: []respUnit{
				{http.StatusOK, controllers.SessionPreviewResponse{}},
				{http.StatusNotFound, envelope.APIError{}},
				{http.StatusInternalServerError, envelope.APIError{}},
				{http.StatusNotImplemented, envelope.APIError{}},
			},
		},
		{
			method: http.MethodPost, path: "/api/v1/sessions/{sessionId}/preview", id: "setSessionPreview", tag: "sessions",
			summary:    "Set (or autodetect) the browser preview URL for a session",
			pathParams: []any{controllers.SessionIDParam{}},
			reqBody:    controllers.SetSessionPreviewRequest{},
			resps: []respUnit{
				{http.StatusOK, controllers.SessionResponse{}},
				{http.StatusBadRequest, envelope.APIError{}},
				{http.StatusNotFound, envelope.APIError{}},
				{http.StatusInternalServerError, envelope.APIError{}},
				{http.StatusNotImplemented, envelope.APIError{}},
			},
		},
		{
			method: http.MethodDelete, path: "/api/v1/sessions/{sessionId}/preview", id: "clearSessionPreview", tag: "sessions",
			summary:    "Clear the browser preview URL for a session",
			pathParams: []any{controllers.SessionIDParam{}},
			resps: []respUnit{
				{http.StatusOK, controllers.SessionResponse{}},
				{http.StatusNotFound, envelope.APIError{}},
				{http.StatusInternalServerError, envelope.APIError{}},
				{http.StatusNotImplemented, envelope.APIError{}},
			},
		},
		{
			method: http.MethodGet, path: "/api/v1/sessions/{sessionId}/preview/server", id: "getSessionPreviewServer", tag: "sessions",
			summary:    "Get the managed preview server status for a session",
			pathParams: []any{controllers.SessionIDParam{}, controllers.BrowserCapabilityHeader{}},
			resps: []respUnit{
				{http.StatusOK, controllers.PreviewServerStatusResponse{}},
				{http.StatusForbidden, envelope.APIError{}},
				{http.StatusNotFound, envelope.APIError{}},
				{http.StatusConflict, envelope.APIError{}},
				{http.StatusInternalServerError, envelope.APIError{}},
				{http.StatusNotImplemented, envelope.APIError{}},
			},
		},
		{
			method: http.MethodPost, path: "/api/v1/sessions/{sessionId}/preview/server", id: "startSessionPreviewServer", tag: "sessions",
			summary:    "Start a session-owned server from .operator/launch.json and open its application preview",
			pathParams: []any{controllers.SessionIDParam{}, controllers.BrowserCapabilityHeader{}},
			reqBody:    controllers.StartPreviewServerRequest{},
			resps: []respUnit{
				{http.StatusOK, controllers.PreviewServerStatusResponse{}},
				{http.StatusBadRequest, envelope.APIError{}},
				{http.StatusForbidden, envelope.APIError{}},
				{http.StatusNotFound, envelope.APIError{}},
				{http.StatusConflict, envelope.APIError{}},
				{http.StatusRequestTimeout, envelope.APIError{}},
				{http.StatusUnprocessableEntity, envelope.APIError{}},
				{http.StatusGatewayTimeout, envelope.APIError{}},
				{http.StatusInternalServerError, envelope.APIError{}},
				{http.StatusNotImplemented, envelope.APIError{}},
			},
		},
		{
			method: http.MethodDelete, path: "/api/v1/sessions/{sessionId}/preview/server", id: "stopSessionPreviewServer", tag: "sessions",
			summary:    "Stop the managed preview server for a session",
			pathParams: []any{controllers.SessionIDParam{}, controllers.BrowserCapabilityHeader{}},
			resps: []respUnit{
				{http.StatusOK, controllers.PreviewServerStatusResponse{}},
				{http.StatusForbidden, envelope.APIError{}},
				{http.StatusNotFound, envelope.APIError{}},
				{http.StatusConflict, envelope.APIError{}},
				{http.StatusInternalServerError, envelope.APIError{}},
				{http.StatusNotImplemented, envelope.APIError{}},
			},
		},
		{
			method: http.MethodGet, path: "/api/v1/sessions/{sessionId}/preview/files/*", id: "getSessionPreviewFile", tag: "sessions",
			summary:    "Serve a static browser preview file from a session workspace",
			pathParams: []any{controllers.SessionIDParam{}},
			resps: []respUnit{
				{http.StatusOK, ""},
				{http.StatusNotFound, envelope.APIError{}},
				{http.StatusInternalServerError, envelope.APIError{}},
				{http.StatusNotImplemented, envelope.APIError{}},
			},
			contentTypes: map[int]string{http.StatusOK: "text/html"},
		},
		{
			method: http.MethodPost, path: "/api/v1/sessions/{sessionId}/attachments", id: "stageSessionAttachments", tag: "sessions",
			summary:    "Write images into a running session's worktree and return their paths",
			pathParams: []any{controllers.SessionIDParam{}},
			reqBody:    controllers.StageSessionAttachmentsRequest{},
			resps: []respUnit{
				{http.StatusCreated, controllers.StageSessionAttachmentsResponse{}},
				{http.StatusBadRequest, envelope.APIError{}},
				{http.StatusNotFound, envelope.APIError{}},
				{http.StatusInternalServerError, envelope.APIError{}},
				{http.StatusNotImplemented, envelope.APIError{}},
			},
		},
		{
			method: http.MethodGet, path: "/api/v1/sessions/{sessionId}/workspace/files", id: "listSessionWorkspaceFiles", tag: "sessions",
			summary:    "List files in a session workspace with git change status",
			pathParams: []any{controllers.SessionIDParam{}},
			resps: []respUnit{
				{http.StatusOK, controllers.ListWorkspaceFilesResponse{}},
				{http.StatusNotFound, envelope.APIError{}},
				{http.StatusInternalServerError, envelope.APIError{}},
				{http.StatusNotImplemented, envelope.APIError{}},
			},
		},
		{
			method: http.MethodGet, path: "/api/v1/sessions/{sessionId}/workspace/events", id: "streamSessionWorkspaceChanges", tag: "sessions",
			summary:    "Stream session workspace file changes",
			pathParams: []any{controllers.SessionIDParam{}},
			resps: []respUnit{
				{http.StatusOK, ""},
				{http.StatusNotFound, envelope.APIError{}},
				{http.StatusInternalServerError, envelope.APIError{}},
				{http.StatusNotImplemented, envelope.APIError{}},
			},
			contentTypes: map[int]string{http.StatusOK: "text/event-stream"},
		},
		{
			method: http.MethodGet, path: "/api/v1/sessions/{sessionId}/workspace/file", id: "getSessionWorkspaceFile", tag: "sessions",
			summary:    "Read one session workspace file and its git diff",
			pathParams: []any{controllers.SessionIDParam{}, controllers.WorkspaceFileQuery{}},
			resps: []respUnit{
				{http.StatusOK, controllers.WorkspaceFileResponse{}},
				{http.StatusBadRequest, envelope.APIError{}},
				{http.StatusNotFound, envelope.APIError{}},
				{http.StatusInternalServerError, envelope.APIError{}},
				{http.StatusNotImplemented, envelope.APIError{}},
			},
		},
		{
			method: http.MethodGet, path: "/api/v1/sessions/{sessionId}/pr", id: "listSessionPRs", tag: "sessions",
			summary:    "List pull requests owned by a session",
			pathParams: []any{controllers.SessionIDParam{}},
			resps: []respUnit{
				{http.StatusOK, controllers.ListSessionPRsResponse{}},
				{http.StatusNotFound, envelope.APIError{}},
				{http.StatusInternalServerError, envelope.APIError{}},
				{http.StatusNotImplemented, envelope.APIError{}},
			},
		},
		{
			method: http.MethodPost, path: "/api/v1/sessions/{sessionId}/pr/claim", id: "claimSessionPR", tag: "sessions",
			summary:    "Claim an existing pull request for a session",
			pathParams: []any{controllers.SessionIDParam{}},
			reqBody:    controllers.ClaimPRRequest{},
			resps: []respUnit{
				{http.StatusOK, controllers.ClaimPRResponse{}},
				{http.StatusBadRequest, envelope.APIError{}},
				{http.StatusNotFound, envelope.APIError{}},
				{http.StatusConflict, envelope.APIError{}},
				{http.StatusUnprocessableEntity, envelope.APIError{}},
				{http.StatusServiceUnavailable, envelope.APIError{}},
				{http.StatusNotImplemented, envelope.APIError{}},
			},
		},
		{
			method: http.MethodPatch, path: "/api/v1/sessions/{sessionId}", id: "renameSession", tag: "sessions",
			summary:    "Rename a session display name",
			pathParams: []any{controllers.SessionIDParam{}},
			reqBody:    controllers.RenameSessionRequest{},
			resps: []respUnit{
				{http.StatusOK, controllers.RenameSessionResponse{}},
				{http.StatusBadRequest, envelope.APIError{}},
				{http.StatusNotFound, envelope.APIError{}},
				{http.StatusInternalServerError, envelope.APIError{}},
				{http.StatusNotImplemented, envelope.APIError{}},
			},
		},
		{
			method: http.MethodPatch, path: "/api/v1/sessions/{sessionId}/merge-policy", id: "setSessionMergePolicy", tag: "sessions",
			summary:    "Configure whether PR completion terminates the session",
			pathParams: []any{controllers.SessionIDParam{}},
			reqBody:    controllers.SetSessionMergePolicyRequest{},
			resps: []respUnit{
				{http.StatusOK, controllers.SetSessionMergePolicyResponse{}},
				{http.StatusBadRequest, envelope.APIError{}},
				{http.StatusNotFound, envelope.APIError{}},
				{http.StatusInternalServerError, envelope.APIError{}},
				{http.StatusNotImplemented, envelope.APIError{}},
			},
		},
		{
			method: http.MethodPatch, path: "/api/v1/sessions/{sessionId}/auto-inject-review", id: "setSessionAutoInjectReview", tag: "sessions",
			summary:    "Set the auto-inject review setting for a session",
			pathParams: []any{controllers.SessionIDParam{}},
			reqBody:    controllers.SetSessionAutoInjectReviewRequest{},
			resps: []respUnit{
				{http.StatusOK, controllers.SetSessionAutoInjectReviewResponse{}},
				{http.StatusNotFound, envelope.APIError{}},
				{http.StatusInternalServerError, envelope.APIError{}},
				{http.StatusNotImplemented, envelope.APIError{}},
			},
		},
		{
			method: http.MethodPut, path: "/api/v1/sessions/{sessionId}/reviewer", id: "setSessionReviewer", tag: "sessions",
			summary:    "Set the reviewer harness for a session",
			pathParams: []any{controllers.SessionIDParam{}},
			reqBody:    controllers.SetSessionReviewerRequest{},
			resps: []respUnit{
				{http.StatusOK, controllers.SessionResponse{}},
				{http.StatusBadRequest, envelope.APIError{}},
				{http.StatusNotFound, envelope.APIError{}},
				{http.StatusUnprocessableEntity, envelope.APIError{}},
				{http.StatusInternalServerError, envelope.APIError{}},
				{http.StatusNotImplemented, envelope.APIError{}},
			},
		},
		{
			method: http.MethodPost, path: "/api/v1/sessions/cleanup", id: "cleanupSessions", tag: "sessions",
			summary:    "Clean up terminated session workspaces",
			pathParams: []any{controllers.CleanupSessionsQuery{}},
			resps: []respUnit{
				{http.StatusOK, controllers.CleanupSessionsResponse{}},
				{http.StatusInternalServerError, envelope.APIError{}},
				{http.StatusNotImplemented, envelope.APIError{}},
			},
		},
		{
			method: http.MethodPost, path: "/api/v1/sessions/{sessionId}/restore", id: "restoreSession", tag: "sessions",
			summary:         "Restore a terminated session",
			pathParams:      []any{controllers.SessionIDParam{}},
			reqBody:         controllers.RestoreSessionRequest{},
			optionalReqBody: true,
			resps: []respUnit{
				{http.StatusOK, controllers.RestoreSessionResponse{}},
				{http.StatusNotFound, envelope.APIError{}},
				{http.StatusConflict, envelope.APIError{}},
				{http.StatusInternalServerError, envelope.APIError{}},
			},
		},
		{
			method: http.MethodPost, path: "/api/v1/sessions/{sessionId}/resume-agent", id: "resumeAgent", tag: "sessions",
			summary:    "Resume an exited agent in its existing session",
			pathParams: []any{controllers.SessionIDParam{}},
			resps: []respUnit{
				{http.StatusOK, controllers.ResumeAgentResponse{}},
				{http.StatusNotFound, envelope.APIError{}},
				{http.StatusConflict, envelope.APIError{}},
				{http.StatusInternalServerError, envelope.APIError{}},
				{http.StatusNotImplemented, envelope.APIError{}},
			},
		},
		{
			method: http.MethodPost, path: "/api/v1/sessions/{sessionId}/relaunch-agent", id: "relaunchSessionAgent", tag: "sessions",
			summary:    "Kill the running agent and relaunch it on a new conversation",
			pathParams: []any{controllers.SessionIDParam{}},
			reqBody:    controllers.RelaunchAgentRequest{},
			resps: []respUnit{
				{http.StatusOK, controllers.RelaunchAgentResponse{}},
				{http.StatusBadRequest, envelope.APIError{}},
				{http.StatusNotFound, envelope.APIError{}},
				{http.StatusConflict, envelope.APIError{}},
				{http.StatusInternalServerError, envelope.APIError{}},
				{http.StatusNotImplemented, envelope.APIError{}},
			},
		},
		{
			method: http.MethodPost, path: "/api/v1/sessions/{sessionId}/switch-agent", id: "switchSessionAgent", tag: "sessions",
			summary:    "Switch a logical Operator session to another agent harness",
			pathParams: []any{controllers.SessionIDParam{}},
			reqBody:    controllers.SwitchAgentRequest{},
			resps: []respUnit{
				{http.StatusOK, controllers.AgentSwitchResponse{}},
				{http.StatusBadRequest, envelope.APIError{}},
				{http.StatusNotFound, envelope.APIError{}},
				{http.StatusConflict, envelope.APIError{}},
				{http.StatusInternalServerError, envelope.APIError{}},
				{http.StatusNotImplemented, envelope.APIError{}},
			},
		},
		{
			method: http.MethodGet, path: "/api/v1/sessions/{sessionId}/agent-switches", id: "listSessionAgentSwitches", tag: "sessions",
			summary:    "List a session's durable agent-switch history",
			pathParams: []any{controllers.SessionIDParam{}},
			resps: []respUnit{
				{http.StatusOK, controllers.ListAgentSwitchesResponse{}},
				{http.StatusNotFound, envelope.APIError{}},
				{http.StatusInternalServerError, envelope.APIError{}},
				{http.StatusNotImplemented, envelope.APIError{}},
			},
		},
		{
			method: http.MethodPost, path: "/api/v1/sessions/{sessionId}/agent-switches/{switchId}/handoff", id: "submitSessionAgentHandoff", tag: "sessions",
			summary:    "Submit a generation-fenced source-agent handoff",
			pathParams: []any{controllers.SessionIDParam{}, controllers.AgentSwitchIDParam{}},
			reqBody:    controllers.SubmitAgentHandoffRequest{},
			resps: []respUnit{
				{http.StatusOK, controllers.AgentSwitchResponse{}},
				{http.StatusBadRequest, envelope.APIError{}},
				{http.StatusNotFound, envelope.APIError{}},
				{http.StatusConflict, envelope.APIError{}},
				{http.StatusInternalServerError, envelope.APIError{}},
				{http.StatusNotImplemented, envelope.APIError{}},
			},
		},
		{
			method: http.MethodGet, path: "/api/v1/sessions/{sessionId}/blocks", id: "listSessionBlockEvents", tag: "sessions",
			summary:    "Read a session's retained, redacted block-event log",
			pathParams: []any{controllers.SessionIDParam{}, sessionBlocksQuery{}},
			resps: []respUnit{
				{http.StatusOK, controllers.ListSessionBlockEventsResponse{}},
				{http.StatusBadRequest, envelope.APIError{}},
				{http.StatusInternalServerError, envelope.APIError{}},
				{http.StatusNotImplemented, envelope.APIError{}},
			},
		},
		{
			method: http.MethodPost, path: "/api/v1/sessions/{sessionId}/kill", id: "killSession", tag: "sessions",
			summary:    "Mark a session terminated and tear down runtime/workspace resources",
			pathParams: []any{controllers.SessionIDParam{}},
			resps: []respUnit{
				{http.StatusOK, controllers.KillSessionResponse{}},
				{http.StatusNotFound, envelope.APIError{}},
				{http.StatusConflict, envelope.APIError{}},
				{http.StatusInternalServerError, envelope.APIError{}},
			},
		},
		{
			method: http.MethodPost, path: "/api/v1/sessions/{sessionId}/rollback", id: "rollbackSession", tag: "sessions",
			summary:    "Undo a partially-completed spawn (delete seed row, or kill if spawn output exists)",
			pathParams: []any{controllers.SessionIDParam{}},
			resps: []respUnit{
				{http.StatusOK, controllers.RollbackSessionResponse{}},
				{http.StatusNotFound, envelope.APIError{}},
				{http.StatusConflict, envelope.APIError{}},
				{http.StatusInternalServerError, envelope.APIError{}},
			},
		},
		{
			method: http.MethodPost, path: "/api/v1/sessions/{sessionId}/send", id: "sendSessionMessage", tag: "sessions",
			summary:    "Send a message to a running session's agent",
			pathParams: []any{controllers.SessionIDParam{}},
			reqBody:    controllers.SendSessionMessageRequest{},
			resps: []respUnit{
				{http.StatusOK, controllers.SendSessionMessageResponse{}},
				{http.StatusBadRequest, envelope.APIError{}},
				{http.StatusNotFound, envelope.APIError{}},
				// Conflict: the session is terminated, or paused on a permission
				// decision (SESSION_AWAITING_DECISION) — the guarded send refuses
				// to paste into a pending dialog.
				{http.StatusConflict, envelope.APIError{}},
				{http.StatusInternalServerError, envelope.APIError{}},
			},
		},
		{
			method: http.MethodPost, path: "/api/v1/sessions/{sessionId}/command", id: "sendSessionCommand", tag: "sessions",
			summary:    "Drive a control command into a session's terminal",
			pathParams: []any{controllers.SessionIDParam{}},
			reqBody:    controllers.SessionCommandRequest{},
			resps: []respUnit{
				{http.StatusOK, controllers.SessionCommandResponse{}},
				{http.StatusBadRequest, envelope.APIError{}},
				{http.StatusNotFound, envelope.APIError{}},
				{http.StatusConflict, envelope.APIError{}},
				{http.StatusInternalServerError, envelope.APIError{}},
			},
		},
		{
			method: http.MethodPost, path: "/api/v1/sessions/{sessionId}/decision", id: "decideSessionDialog", tag: "sessions",
			summary:    "Answer a session's pending permission dialog",
			pathParams: []any{controllers.SessionIDParam{}},
			reqBody:    controllers.SessionDecisionRequest{},
			resps: []respUnit{
				{http.StatusOK, controllers.SessionDecisionResponse{}},
				{http.StatusBadRequest, envelope.APIError{}},
				{http.StatusNotFound, envelope.APIError{}},
				{http.StatusConflict, envelope.APIError{}},
				{http.StatusInternalServerError, envelope.APIError{}},
			},
		},
		{
			method: http.MethodPost, path: "/api/v1/sessions/{sessionId}/answer", id: "answerSessionQuestion", tag: "sessions",
			summary:    "Answer a session's pending question menu",
			pathParams: []any{controllers.SessionIDParam{}},
			reqBody:    controllers.SessionAnswerRequest{},
			resps: []respUnit{
				{http.StatusOK, controllers.SessionAnswerResponse{}},
				{http.StatusBadRequest, envelope.APIError{}},
				{http.StatusNotFound, envelope.APIError{}},
				{http.StatusConflict, envelope.APIError{}},
				{http.StatusInternalServerError, envelope.APIError{}},
			},
		},
		{
			method: http.MethodGet, path: "/api/v1/sessions/{sessionId}/interactions", id: "listSessionInteractions", tag: "sessions",
			summary:    "List a session's currently pending dialogs",
			pathParams: []any{controllers.SessionIDParam{}},
			resps: []respUnit{
				{http.StatusOK, controllers.SessionInteractionsResponse{}},
				{http.StatusInternalServerError, envelope.APIError{}},
				{http.StatusNotImplemented, envelope.APIError{}},
			},
		},
		{
			method: http.MethodGet, path: "/api/v1/sessions/{sessionId}/slash-commands", id: "listSessionSlashCommands", tag: "sessions",
			summary:    "List the slash commands, skills and plugin skills available to a session",
			pathParams: []any{controllers.SessionIDParam{}},
			resps: []respUnit{
				{http.StatusOK, controllers.SessionSlashCommandsResponse{}},
				{http.StatusNotFound, envelope.APIError{}},
				{http.StatusInternalServerError, envelope.APIError{}},
				{http.StatusNotImplemented, envelope.APIError{}},
			},
		},
		{
			method: http.MethodGet, path: "/api/v1/sessions/{sessionId}/models", id: "listSessionModels", tag: "sessions",
			summary:    "Read the models a session's harness offers and which one is current",
			pathParams: []any{controllers.SessionIDParam{}},
			resps: []respUnit{
				{http.StatusOK, controllers.SessionModelsResponse{}},
				{http.StatusNotFound, envelope.APIError{}},
				{http.StatusConflict, envelope.APIError{}},
				{http.StatusInternalServerError, envelope.APIError{}},
				{http.StatusNotImplemented, envelope.APIError{}},
			},
		},
		{
			method: http.MethodGet, path: "/api/v1/sessions/{sessionId}/draft", id: "getSessionDraft", tag: "sessions",
			summary:    "Read a session's unsent composer draft",
			pathParams: []any{controllers.SessionIDParam{}},
			resps: []respUnit{
				{http.StatusOK, controllers.SessionDraftResponse{}},
				{http.StatusInternalServerError, envelope.APIError{}},
				{http.StatusNotImplemented, envelope.APIError{}},
			},
		},
		{
			method: http.MethodGet, path: "/api/v1/sessions/{sessionId}/suggestion", id: "getSessionSuggestion", tag: "sessions",
			summary:    "Read the prompt a session's harness suggests in its empty composer",
			pathParams: []any{controllers.SessionIDParam{}},
			resps: []respUnit{
				{http.StatusOK, controllers.SessionSuggestionResponse{}},
				{http.StatusInternalServerError, envelope.APIError{}},
				{http.StatusNotImplemented, envelope.APIError{}},
			},
		},
		{
			method: http.MethodPost, path: "/api/v1/sessions/{sessionId}/activity", id: "setSessionActivity", tag: "sessions",
			summary:    "Report an agent activity-state signal for a session",
			pathParams: []any{controllers.SessionIDParam{}},
			reqBody:    controllers.SetActivityRequest{},
			resps: []respUnit{
				{http.StatusOK, controllers.SetActivityResponse{}},
				{http.StatusBadRequest, envelope.APIError{}},
				{http.StatusNotFound, envelope.APIError{}},
				{http.StatusInternalServerError, envelope.APIError{}},
				{http.StatusNotImplemented, envelope.APIError{}},
			},
		},
		{
			method: http.MethodPost, path: "/api/v1/reviews/{reviewSessionID}/activity", id: "setReviewActivity", tag: "reviews",
			summary:    "Report a reviewer-owned hook signal",
			pathParams: []any{controllers.ReviewSessionIDParam{}},
			reqBody:    controllers.SetReviewActivityRequest{},
			resps: []respUnit{
				{http.StatusOK, controllers.SetReviewActivityResponse{}},
				{http.StatusBadRequest, envelope.APIError{}},
				{http.StatusNotFound, envelope.APIError{}},
				{http.StatusInternalServerError, envelope.APIError{}},
				{http.StatusNotImplemented, envelope.APIError{}},
			},
		},
		{
			method: http.MethodGet, path: "/api/v1/orchestrators", id: "listOrchestrators", tag: "sessions",
			summary: "List orchestrator sessions across projects",
			resps: []respUnit{
				{http.StatusOK, controllers.ListSessionsResponse{}},
				{http.StatusInternalServerError, envelope.APIError{}},
				{http.StatusNotImplemented, envelope.APIError{}},
			},
		},
		{
			method: http.MethodPost, path: "/api/v1/orchestrators", id: "spawnOrchestrator", tag: "sessions",
			summary: "Spawn an orchestrator session",
			reqBody: controllers.SpawnOrchestratorRequest{},
			resps: []respUnit{
				{http.StatusCreated, controllers.SpawnOrchestratorResponse{}},
				{http.StatusBadRequest, envelope.APIError{}},
				{http.StatusNotFound, envelope.APIError{}},
				{http.StatusInternalServerError, envelope.APIError{}},
				{http.StatusNotImplemented, envelope.APIError{}},
			},
		},
		{
			method: http.MethodPost, path: "/api/v1/orchestrators/delegate", id: "delegateTask", tag: "sessions",
			summary: "Start a worker task and ask the orchestrator to title it",
			reqBody: controllers.DelegateTaskRequest{},
			resps: []respUnit{
				{http.StatusAccepted, controllers.DelegateTaskResponse{}},
				{http.StatusBadRequest, envelope.APIError{}},
				{http.StatusNotFound, envelope.APIError{}},
				{http.StatusConflict, envelope.APIError{}},
				{http.StatusInternalServerError, envelope.APIError{}},
				{http.StatusNotImplemented, envelope.APIError{}},
			},
		},
		{
			method: http.MethodGet, path: "/api/v1/orchestrators/{id}", id: "getOrchestrator", tag: "sessions",
			summary:    "Fetch one orchestrator session",
			pathParams: []any{controllers.OrchestratorIDParam{}},
			resps: []respUnit{
				{http.StatusOK, controllers.SessionResponse{}},
				{http.StatusNotFound, envelope.APIError{}},
				{http.StatusInternalServerError, envelope.APIError{}},
				{http.StatusNotImplemented, envelope.APIError{}},
			},
		},
	}
}

// prOperations declares the PR action operations. These live in the SCM lane:
// the handler delegates to a PRService backed by the SCM provider. A nil
// PRService (SCM not configured) returns 501 for both routes.
func prOperations() []operation {
	return []operation{
		{
			method: http.MethodPost, path: "/api/v1/prs/{id}/merge", id: "mergePR", tag: "prs",
			summary:    "Squash-merge a pull request",
			pathParams: []any{controllers.PRIDParam{}},
			reqBody:    controllers.MergePRRequest{},
			resps: []respUnit{
				{http.StatusBadRequest, envelope.APIError{}},
				{http.StatusOK, controllers.MergePRResponse{}},
				{http.StatusNotFound, envelope.APIError{}},
				{http.StatusConflict, envelope.APIError{}},
				{http.StatusUnprocessableEntity, envelope.APIError{}},
				{http.StatusNotImplemented, envelope.APIError{}},
			},
		},
		{
			method: http.MethodPost, path: "/api/v1/prs/{id}/resolve-comments", id: "resolveComments", tag: "prs",
			summary:    "Resolve review threads on a pull request",
			pathParams: []any{controllers.PRIDParam{}},
			reqBody:    nil, // body is optional: omitting it resolves all unresolved threads
			resps: []respUnit{
				{http.StatusOK, controllers.ResolveCommentsResponse{}},
				{http.StatusNotFound, envelope.APIError{}},
				{http.StatusUnprocessableEntity, envelope.APIError{}},
				{http.StatusNotImplemented, envelope.APIError{}},
			},
		},
	}
}
