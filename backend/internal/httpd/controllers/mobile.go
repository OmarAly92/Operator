package controllers

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"strings"
	"time"

	"github.com/OmarAly92/operator/backend/internal/httpd/envelope"
	"github.com/OmarAly92/operator/backend/internal/mobilebridge"
	"github.com/OmarAly92/operator/backend/internal/tunnel"
)

const mobileUnencryptedWarning = "Traffic on this connection is not encrypted. Only use it on a network you trust."
const mobileTunnelWarning = "This desktop is reachable from the internet. Anyone with the address and password can start agents and run terminal commands here."

type mobileBridge interface {
	Status() MobileStatusResponse
	Enable() (MobileStatusResponse, error)
	Disable() error
	Regenerate() (MobileStatusResponse, error)
	TunnelEnable() (MobileStatusResponse, error)
	TunnelDisable() (MobileStatusResponse, error)
	SetAuthtoken(token string) (MobileStatusResponse, error)
	RemoveAuthtoken() (MobileStatusResponse, error)
	NgrokStatus(ctx context.Context) MobileNgrokStatus
	SetAPIKey(ctx context.Context, key string) (MobileNgrokAccount, error)
	RemoveAPIKey() (MobileNgrokStatus, error)
	NgrokAccount(ctx context.Context) MobileNgrokAccount
	MintCredential(ctx context.Context) (MobileNgrokStatus, error)
	RevokeCredential(ctx context.Context, id string) (MobileNgrokAccount, error)
	SetDomain(ctx context.Context, domain string) (MobileNgrokStatus, error)
	Diagnose(ctx context.Context) MobileNgrokDiagnosis
}

type TunnelController interface {
	Enable(ctx context.Context) error
	Disable(ctx context.Context) error
	Status() tunnel.Status
	SetAuthtoken(ctx context.Context, token string) error
	HasAuthtoken() bool
	SetLocalPort(port int)
	RemoveAuthtoken() error
	NgrokInfo(ctx context.Context) tunnel.NgrokInfo
	SetAPIKey(ctx context.Context, key string) error
	RemoveAPIKey() error
	NgrokAccount(ctx context.Context) tunnel.NgrokAccount
	MintOperatorCredential(ctx context.Context) error
	RevokeCredential(ctx context.Context, id string) error
	SetStableDomain(ctx context.Context, domain string) error
	NgrokDiagnose(ctx context.Context) tunnel.NgrokDiagnosis
}

var _ TunnelController = (*tunnel.Manager)(nil)

// MobileController exposes the Connect Mobile bridge control endpoints
// (status/enable/disable/regenerate) over the loopback API, delegating to a
// mobileBridge and stamping the unencrypted-LAN warning onto every response.
type MobileController struct{ Bridge mobileBridge }

// withWarning stamps the constant unencrypted-LAN warning onto any bridge
// response. The warning is not bridge-specific state — it's always present —
// so the controller guarantees it here rather than trusting every mobileBridge
// implementation (including test fakes) to set it.
func withWarning(res MobileStatusResponse) MobileStatusResponse {
	if res.Tunnel != nil && res.Tunnel.State == string(tunnel.StateLive) {
		res.Warning = mobileTunnelWarning
		return res
	}
	res.Warning = mobileUnencryptedWarning
	return res
}

// Status returns the current bridge status.
func (c *MobileController) Status(w http.ResponseWriter, r *http.Request) {
	envelope.WriteJSON(w, http.StatusOK, withWarning(c.Bridge.Status()))
}

// Enable turns the bridge on and returns the resulting status (with password).
func (c *MobileController) Enable(w http.ResponseWriter, r *http.Request) {
	res, err := c.Bridge.Enable()
	if err != nil {
		envelope.WriteAPIError(w, r, http.StatusInternalServerError, "internal", "MOBILE_ENABLE", err.Error(), nil)
		return
	}
	envelope.WriteJSON(w, http.StatusOK, withWarning(res))
}

// Disable turns the bridge off and returns the resulting status.
func (c *MobileController) Disable(w http.ResponseWriter, r *http.Request) {
	if err := c.Bridge.Disable(); err != nil {
		envelope.WriteAPIError(w, r, http.StatusInternalServerError, "internal", "MOBILE_DISABLE", err.Error(), nil)
		return
	}
	envelope.WriteJSON(w, http.StatusOK, withWarning(c.Bridge.Status()))
}

// Regenerate rotates the connection password and returns the resulting status.
func (c *MobileController) Regenerate(w http.ResponseWriter, r *http.Request) {
	res, err := c.Bridge.Regenerate()
	if err != nil {
		envelope.WriteAPIError(w, r, http.StatusInternalServerError, "internal", "MOBILE_REGEN", err.Error(), nil)
		return
	}
	envelope.WriteJSON(w, http.StatusOK, withWarning(res))
}

func (c *MobileController) TunnelEnable(w http.ResponseWriter, r *http.Request) {
	res, err := c.Bridge.TunnelEnable()
	if err != nil {
		envelope.WriteAPIError(w, r, http.StatusInternalServerError, "internal", "MOBILE_TUNNEL_ENABLE", err.Error(), nil)
		return
	}
	envelope.WriteJSON(w, http.StatusOK, withWarning(res))
}

func (c *MobileController) TunnelDisable(w http.ResponseWriter, r *http.Request) {
	res, err := c.Bridge.TunnelDisable()
	if err != nil {
		envelope.WriteAPIError(w, r, http.StatusInternalServerError, "internal", "MOBILE_TUNNEL_DISABLE", err.Error(), nil)
		return
	}
	envelope.WriteJSON(w, http.StatusOK, withWarning(res))
}

func (c *MobileController) SetAuthtoken(w http.ResponseWriter, r *http.Request) {
	var body MobileAuthtokenRequest
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		envelope.WriteAPIError(w, r, http.StatusBadRequest, "invalid_request", "MOBILE_AUTHTOKEN_BODY", "malformed request body", nil)
		return
	}
	res, err := c.Bridge.SetAuthtoken(body.Token)
	if err != nil {
		envelope.WriteAPIError(w, r, http.StatusBadRequest, "invalid_request", "MOBILE_AUTHTOKEN", err.Error(), nil)
		return
	}
	envelope.WriteJSON(w, http.StatusOK, withWarning(res))
}

// LANController is the runtime hook set the concrete bridge needs. httpd's
// LANManager + authState satisfy it (adapter wired in daemon.go).
type LANController interface {
	Start(port int) (int, error)
	Stop(ctx context.Context) error
	Running() bool
	BoundPort() int
	SetPasswordHash(hash string)
	PasswordHash() string
	SetPasswordStrong(strong bool)
	PasswordStrong() bool
	SetTrustedForwardHeader(name string)
}

// BridgeService is the production mobileBridge. It persists state and drives
// the LAN listener. Password plaintext exists only transiently in the response.
type BridgeService struct {
	LAN         LANController
	ConfigPath  string
	DefaultPort int
	Tunnel      TunnelController
}

func (b *BridgeService) currentHost() string { return mobilebridge.AutopickLANIP() }

// Status reports the current bridge state, host, and port. The plaintext
// password is included only while the bridge is enabled (loopback route only).
func (b *BridgeService) Status() MobileStatusResponse {
	st, _ := mobilebridge.Load(b.ConfigPath)
	enabled := st.Enabled && b.LAN.Running()
	res := MobileStatusResponse{
		Enabled: enabled,
		Host:    b.currentHost(),
		Port:    b.LAN.BoundPort(),
	}
	// Only surface the password while the bridge is actually enabled. This route
	// is reachable only on the loopback listener (the LAN listener 404s
	// /api/v1/mobile via lanControlBlock), so the plaintext never reaches a phone.
	if enabled {
		res.Password = st.Password
	}
	res.Tunnel = b.tunnelStatus()
	return withWarning(res)
}

func (b *BridgeService) tunnelStatus() *MobileTunnelStatus {
	if b.Tunnel == nil {
		return nil
	}
	st := b.Tunnel.Status()
	out := &MobileTunnelStatus{
		State:          string(st.State),
		Provider:       st.Provider,
		URL:            st.URL,
		Error:          st.Error,
		Restarts:       st.Restarts,
		NeedsAuthtoken: st.NeedsAuthtoken,
		HasAuthtoken:   b.Tunnel.HasAuthtoken(),
		LastProvider:   st.LastProvider,
		FallbackReason: st.FallbackReason,
	}
	if !st.Since.IsZero() {
		out.Since = st.Since.UTC().Format(time.RFC3339)
	}
	return out
}

func (b *BridgeService) enableWithPassword(pw string) (MobileStatusResponse, error) {
	// Snapshot state so we can roll back the in-memory side effects (armed hash,
	// running listener) if we fail before durable state is written. Otherwise a
	// failed enable would leave a LAN listener open on 0.0.0.0 with the new
	// password while persisted state/UI still say the bridge is off.
	prevHash := b.LAN.PasswordHash()
	prevStrong := b.LAN.PasswordStrong()
	wasRunning := b.LAN.Running()
	prevState, _ := mobilebridge.Load(b.ConfigPath)

	// The persisted password is plaintext; the auth hash is derived in memory.
	b.LAN.SetPasswordHash(mobilebridge.HashPassword(pw))
	b.LAN.SetPasswordStrong(len(pw) >= mobilebridge.TunnelPasswordLength)
	port, err := b.LAN.Start(b.DefaultPort)
	if err != nil {
		b.LAN.SetPasswordHash(prevHash) // Start failed: undo the hash swap.
		b.LAN.SetPasswordStrong(prevStrong)
		return MobileStatusResponse{}, err
	}
	if err := mobilebridge.Save(b.ConfigPath, mobilebridge.State{
		Enabled:       true,
		Password:      pw,
		LastPort:      port,
		TunnelEnabled: prevState.TunnelEnabled,
	}); err != nil {
		// Persist failed after the listener came up. Roll back so reality matches
		// the unchanged persisted state (and the UI's "enable failed"). A rotate on
		// an already-running listener (wasRunning) keeps serving on the prior hash;
		// a fresh enable tears the listener back down.
		if !wasRunning {
			ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
			defer cancel()
			_ = b.LAN.Stop(ctx)
		}
		b.LAN.SetPasswordHash(prevHash)
		b.LAN.SetPasswordStrong(prevStrong)
		return MobileStatusResponse{}, err
	}
	if b.Tunnel != nil {
		b.Tunnel.SetLocalPort(port)
	}
	return b.Status(), nil
}

// Enable generates a fresh password, arms the auth hash, and starts the LAN
// listener, persisting the enabled state.
func (b *BridgeService) Enable() (MobileStatusResponse, error) {
	pw, err := mobilebridge.GeneratePassword()
	if err != nil {
		return MobileStatusResponse{}, err
	}
	return b.enableWithPassword(pw)
}

// Regenerate rotates the connection password on the running listener, which
// drops the currently paired phone (it authenticates against the new hash).
func (b *BridgeService) Regenerate() (MobileStatusResponse, error) {
	generate := mobilebridge.GeneratePassword
	if st, loadErr := mobilebridge.Load(b.ConfigPath); loadErr == nil && st.TunnelEnabled {
		generate = func() (string, error) { return mobilebridge.GeneratePasswordN(mobilebridge.TunnelPasswordLength) }
	}
	pw, err := generate()
	if err != nil {
		return MobileStatusResponse{}, err
	}
	return b.enableWithPassword(pw) // rotate → drops current phone (new hash)
}

// Disable stops the LAN listener and persists the disabled state.
func (b *BridgeService) Disable() error {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if err := b.LAN.Stop(ctx); err != nil {
		return err
	}
	st, _ := mobilebridge.Load(b.ConfigPath)
	st.Enabled = false
	return mobilebridge.Save(b.ConfigPath, st)
}

func (b *BridgeService) TunnelEnable() (MobileStatusResponse, error) {
	if !b.LAN.Running() {
		return MobileStatusResponse{}, errors.New("enable mobile access before making it reachable from the internet")
	}
	st, err := mobilebridge.Load(b.ConfigPath)
	if err != nil {
		return MobileStatusResponse{}, err
	}
	if !st.TunnelEnabled || len(st.Password) < mobilebridge.TunnelPasswordLength {
		pw, genErr := mobilebridge.GeneratePasswordN(mobilebridge.TunnelPasswordLength)
		if genErr != nil {
			return MobileStatusResponse{}, genErr
		}
		if _, enableErr := b.enableWithPassword(pw); enableErr != nil {
			return MobileStatusResponse{}, enableErr
		}
	}
	if err := b.setTunnelIntent(true); err != nil {
		return MobileStatusResponse{}, err
	}
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	if err := b.Tunnel.Enable(ctx); err != nil {
		return b.Status(), nil
	}
	return b.Status(), nil
}

func (b *BridgeService) TunnelDisable() (MobileStatusResponse, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := b.Tunnel.Disable(ctx); err != nil {
		return MobileStatusResponse{}, err
	}
	if err := b.setTunnelIntent(false); err != nil {
		return MobileStatusResponse{}, err
	}
	return b.Status(), nil
}

func (b *BridgeService) SetAuthtoken(token string) (MobileStatusResponse, error) {
	trimmed := strings.TrimSpace(token)
	if trimmed == "" {
		return MobileStatusResponse{}, errors.New("authtoken must not be empty")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
	defer cancel()
	if err := b.Tunnel.SetAuthtoken(ctx, trimmed); err != nil {
		return MobileStatusResponse{}, errors.New(redactSecret(err.Error(), trimmed))
	}
	return b.Status(), nil
}

func redactSecret(text, secret string) string {
	if secret == "" {
		return text
	}
	return strings.ReplaceAll(text, secret, "[redacted]")
}

func (b *BridgeService) setTunnelIntent(on bool) error {
	st, err := mobilebridge.Load(b.ConfigPath)
	if err != nil {
		return err
	}
	st.TunnelEnabled = on
	return mobilebridge.Save(b.ConfigPath, st)
}

func ngrokStatusFrom(info tunnel.NgrokInfo) MobileNgrokStatus {
	logs := make([]MobileNgrokLogLine, 0, len(info.Logs))
	for _, l := range info.Logs {
		logs = append(logs, MobileNgrokLogLine{Time: l.Time, Level: l.Level, Message: l.Message})
	}
	return MobileNgrokStatus{
		Credential: MobileNgrokCredential{Present: info.Credential.Present, Source: info.Credential.Source, SystemConfigPath: info.Credential.SystemConfigPath, Suffix: info.Credential.Suffix},
		Agent:      MobileNgrokAgent{BinaryPath: info.Agent.BinaryPath, Source: info.Agent.Source, Version: info.Agent.Version, UpdateAvailable: info.Agent.UpdateAvailable},
		Session:    MobileNgrokSession{Status: info.Session.Status, Region: info.Session.Region, Latency: info.Session.Latency, PublicURL: info.Session.PublicURL, Connections: info.Session.Connections, HTTPRequests: info.Session.HTTPRequests},
		Domain:     info.Domain,
		APIKey:     MobileNgrokAPIKey{Present: info.APIKey},
		Logs:       logs,
	}
}

func ngrokAccountFrom(acc tunnel.NgrokAccount) MobileNgrokAccount {
	credentials := make([]MobileNgrokAccountCredential, 0, len(acc.Credentials))
	for _, c := range acc.Credentials {
		credentials = append(credentials, MobileNgrokAccountCredential{ID: c.ID, Description: c.Description, CreatedAt: c.CreatedAt, IsOperator: c.IsOperator})
	}
	sessions := make([]MobileNgrokAccountSession, 0, len(acc.Sessions))
	for _, s := range acc.Sessions {
		sessions = append(sessions, MobileNgrokAccountSession{ID: s.ID, Region: s.Region, IP: s.IP, AgentVersion: s.AgentVersion, OS: s.OS, StartedAt: s.StartedAt, IsThisMachine: s.IsThisMachine})
	}
	endpoints := make([]MobileNgrokAccountEndpoint, 0, len(acc.Endpoints))
	for _, e := range acc.Endpoints {
		endpoints = append(endpoints, MobileNgrokAccountEndpoint{ID: e.ID, PublicURL: e.PublicURL, Proto: e.Proto, CreatedAt: e.CreatedAt})
	}
	domains := make([]MobileNgrokReservedDomain, 0, len(acc.ReservedDomains))
	for _, d := range acc.ReservedDomains {
		domains = append(domains, MobileNgrokReservedDomain{ID: d.ID, Domain: d.Domain})
	}
	return MobileNgrokAccount{
		Valid:           acc.Valid,
		Error:           acc.Error,
		Credentials:     credentials,
		Sessions:        sessions,
		Endpoints:       endpoints,
		ReservedDomains: domains,
	}
}

func ngrokDiagnosisFrom(d tunnel.NgrokDiagnosis) MobileNgrokDiagnosis {
	checks := make([]MobileNgrokCheck, 0, len(d.Checks))
	for _, c := range d.Checks {
		checks = append(checks, MobileNgrokCheck{Name: c.Name, OK: c.OK, Detail: c.Detail})
	}
	return MobileNgrokDiagnosis{Checks: checks, Summary: d.Summary}
}

func (b *BridgeService) NgrokStatus(ctx context.Context) MobileNgrokStatus {
	if b.Tunnel == nil {
		return ngrokStatusFrom(tunnel.NgrokInfo{})
	}
	return ngrokStatusFrom(b.Tunnel.NgrokInfo(ctx))
}

func (b *BridgeService) RemoveAuthtoken() (MobileStatusResponse, error) {
	if err := b.Tunnel.RemoveAuthtoken(); err != nil {
		return MobileStatusResponse{}, err
	}
	return b.Status(), nil
}

func (b *BridgeService) SetAPIKey(ctx context.Context, key string) (MobileNgrokAccount, error) {
	if err := b.Tunnel.SetAPIKey(ctx, key); err != nil {
		return MobileNgrokAccount{}, err
	}
	return ngrokAccountFrom(b.Tunnel.NgrokAccount(ctx)), nil
}

func (b *BridgeService) RemoveAPIKey() (MobileNgrokStatus, error) {
	if err := b.Tunnel.RemoveAPIKey(); err != nil {
		return MobileNgrokStatus{}, err
	}
	return b.NgrokStatus(context.Background()), nil
}

func (b *BridgeService) NgrokAccount(ctx context.Context) MobileNgrokAccount {
	return ngrokAccountFrom(b.Tunnel.NgrokAccount(ctx))
}

func (b *BridgeService) MintCredential(ctx context.Context) (MobileNgrokStatus, error) {
	if err := b.Tunnel.MintOperatorCredential(ctx); err != nil {
		return MobileNgrokStatus{}, err
	}
	return b.NgrokStatus(ctx), nil
}

func (b *BridgeService) RevokeCredential(ctx context.Context, id string) (MobileNgrokAccount, error) {
	if err := b.Tunnel.RevokeCredential(ctx, id); err != nil {
		return MobileNgrokAccount{}, err
	}
	return b.NgrokAccount(ctx), nil
}

func (b *BridgeService) SetDomain(ctx context.Context, domain string) (MobileNgrokStatus, error) {
	if err := b.Tunnel.SetStableDomain(ctx, domain); err != nil {
		return MobileNgrokStatus{}, err
	}
	st, err := mobilebridge.Load(b.ConfigPath)
	if err != nil {
		return MobileNgrokStatus{}, err
	}
	st.NgrokDomain = strings.TrimSpace(domain)
	if err := mobilebridge.Save(b.ConfigPath, st); err != nil {
		return MobileNgrokStatus{}, err
	}
	if live := b.Tunnel.Status(); live.State == tunnel.StateLive && live.Provider == "ngrok" {
		if err := b.Tunnel.Disable(ctx); err != nil {
			return MobileNgrokStatus{}, err
		}
		if err := b.Tunnel.Enable(ctx); err != nil {
			return MobileNgrokStatus{}, err
		}
	}
	return b.NgrokStatus(ctx), nil
}

func (b *BridgeService) Diagnose(ctx context.Context) MobileNgrokDiagnosis {
	return ngrokDiagnosisFrom(b.Tunnel.NgrokDiagnose(ctx))
}
