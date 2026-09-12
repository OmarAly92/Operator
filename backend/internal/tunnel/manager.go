package tunnel

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"net"
	"os/exec"
	"strconv"
	"sync"
	"time"
)

const (
	urlPollInterval  = 250 * time.Millisecond
	startTimeout     = 60 * time.Second
	healthInterval   = 15 * time.Second
	backoffFloor     = time.Second
	backoffCeiling   = 60 * time.Second
	healthResetAfter = 60 * time.Second
	stopGrace        = 5 * time.Second
	logRetention     = 200
)

func itoa(value int) string { return strconv.Itoa(value) }

type Deps struct {
	Log         *slog.Logger
	Dir         string
	Providers   []Provider
	Binaries    BinaryStore
	Now         func() time.Time
	Sleep       func(context.Context, time.Duration) error
	ReservePort func() (int, error)
	OnProvider  func(clientIPHeader string)
}

type Manager struct {
	log         *slog.Logger
	dir         string
	providers   []Provider
	binaries    BinaryStore
	now         func() time.Time
	sleep       func(context.Context, time.Duration) error
	reservePort func() (int, error)
	onProvider  func(string)

	mu         sync.Mutex
	status     Status
	localPort  int
	enabled    bool
	stickyFrom map[string]bool
	cmd        *exec.Cmd
	cancel     context.CancelFunc
	done       chan struct{}
	awaitDone  chan struct{}
	logs       *lineRing
}

func New(deps Deps) *Manager {
	log := deps.Log
	if log == nil {
		log = slog.Default()
	}
	now := deps.Now
	if now == nil {
		now = time.Now
	}
	sleep := deps.Sleep
	if sleep == nil {
		sleep = sleepContext
	}
	reserve := deps.ReservePort
	if reserve == nil {
		reserve = reserveLoopbackPort
	}
	onProvider := deps.OnProvider
	if onProvider == nil {
		onProvider = func(string) {}
	}
	return &Manager{
		log:         log,
		dir:         deps.Dir,
		providers:   deps.Providers,
		binaries:    deps.Binaries,
		now:         now,
		sleep:       sleep,
		reservePort: reserve,
		onProvider:  onProvider,
		status:      Status{State: StateOff},
		stickyFrom:  map[string]bool{},
	}
}

func (m *Manager) SetLocalPort(port int) {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.localPort = port
}

func (m *Manager) Status() Status {
	m.mu.Lock()
	defer m.mu.Unlock()
	return m.status
}

func (m *Manager) Enable(ctx context.Context) error {
	m.mu.Lock()
	if m.enabled {
		m.mu.Unlock()
		return nil
	}
	m.enabled = true
	m.status = Status{State: StateStarting}
	m.mu.Unlock()

	if err := m.startFirstWorkingProvider(ctx); err != nil {
		m.mu.Lock()
		m.enabled = false
		m.status = Status{State: StateFailed, Error: err.Error(), NeedsAuthtoken: m.status.NeedsAuthtoken}
		m.mu.Unlock()
		return err
	}
	return nil
}

func (m *Manager) Disable(ctx context.Context) error {
	m.mu.Lock()
	m.enabled = false
	cancel, done, awaitDone := m.cancel, m.done, m.awaitDone
	m.cancel, m.done, m.awaitDone = nil, nil, nil
	m.stickyFrom = map[string]bool{}
	m.mu.Unlock()

	if cancel != nil {
		cancel()
	}
	deadlineCtx, cancelDeadline := context.WithTimeout(context.Background(), stopGrace+time.Second)
	defer cancelDeadline()
	if done != nil {
		select {
		case <-done:
		case <-deadlineCtx.Done():
		}
	}
	if awaitDone != nil {
		select {
		case <-awaitDone:
		case <-deadlineCtx.Done():
		}
	}

	m.mu.Lock()
	m.status = Status{State: StateOff}
	m.mu.Unlock()
	m.onProvider("")
	return nil
}

func (m *Manager) Close() {
	stopCtx, cancel := context.WithTimeout(context.Background(), stopGrace)
	defer cancel()
	_ = m.Disable(stopCtx)
}

func (m *Manager) startFirstWorkingProvider(ctx context.Context) error {
	var lastErr error
	for _, provider := range m.providers {
		m.mu.Lock()
		skip := m.stickyFrom[provider.Name()]
		m.mu.Unlock()
		if skip {
			continue
		}
		if err := m.launch(ctx, provider); err != nil {
			lastErr = err
			m.log.Warn("tunnel provider unavailable", "provider", provider.Name(), "err", err)
			continue
		}
		return nil
	}
	if lastErr == nil {
		lastErr = errors.New("no tunnel provider available")
	}
	return lastErr
}

func (m *Manager) launch(ctx context.Context, provider Provider) error {
	m.setState(StateDownloading, provider.Name())
	binary, err := m.binaries.Ensure(ctx, provider.Binary())
	if err != nil {
		return err
	}
	controlPort, err := m.reservePort()
	if err != nil {
		return err
	}

	m.mu.Lock()
	localPort := m.localPort
	m.mu.Unlock()

	runCtx, cancel := context.WithCancel(context.Background())
	cmd := newTunnelCommand(binary, provider.Args(localPort, controlPort)...)
	logs := newLineRing(logRetention)
	cmd.Stdout = logs
	cmd.Stderr = logs
	if err := cmd.Start(); err != nil {
		cancel()
		return err
	}

	done := make(chan struct{})
	awaitDone := make(chan struct{})
	liveConfirmed := make(chan struct{})
	m.mu.Lock()
	m.cmd, m.cancel, m.done, m.awaitDone, m.logs = cmd, cancel, done, awaitDone, logs
	m.status = Status{State: StateStarting, Provider: provider.Name()}
	m.mu.Unlock()

	m.recordPID(provider.Name(), cmd)
	m.setState(StateStarting, provider.Name())

	go m.supervise(runCtx, provider, cmd, controlPort, logs, done, liveConfirmed)
	go m.runAwaitURL(runCtx, provider, controlPort, cancel, done, awaitDone, liveConfirmed)

	return nil
}

func (m *Manager) runAwaitURL(ctx context.Context, provider Provider, controlPort int, cancel context.CancelFunc, done chan struct{}, awaitDone chan struct{}, liveConfirmed chan struct{}) {
	defer close(awaitDone)
	if err := m.awaitURL(ctx, provider, controlPort); err != nil {
		if ctx.Err() != nil {
			return
		}
		m.mu.Lock()
		m.status = Status{State: StateFailed, Error: err.Error()}
		m.mu.Unlock()
		cancel()
		<-done
		return
	}
	close(liveConfirmed)
}

func (m *Manager) awaitURL(ctx context.Context, provider Provider, controlPort int) error {
	deadline := m.now().Add(startTimeout)
	for m.now().Before(deadline) {
		select {
		case <-ctx.Done():
			return ctx.Err()
		default:
		}
		url, err := provider.PublicURL(ctx, controlPort)
		if err == nil && url != "" {
			if ctx.Err() != nil {
				return ctx.Err()
			}
			m.publishURL(provider, url)
			return nil
		}
		if err := m.sleep(ctx, urlPollInterval); err != nil {
			return err
		}
	}
	return fmt.Errorf("tunnel: %s published no url within %s", provider.Name(), startTimeout)
}

func (m *Manager) publishURL(provider Provider, url string) {
	m.mu.Lock()
	m.status.State = StateLive
	m.status.Provider = provider.Name()
	m.status.URL = url
	m.status.Error = ""
	if m.status.Since.IsZero() {
		m.status.Since = m.now()
	}
	m.mu.Unlock()
	m.onProvider(provider.ClientIPHeader())
}

func (m *Manager) setState(state State, providerName string) {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.status.State = state
	m.status.Provider = providerName
}

func sleepContext(ctx context.Context, d time.Duration) error {
	timer := time.NewTimer(d)
	defer timer.Stop()
	select {
	case <-ctx.Done():
		return ctx.Err()
	case <-timer.C:
		return nil
	}
}

func reserveLoopbackPort() (int, error) {
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		return 0, err
	}
	defer func() { _ = listener.Close() }()
	addr, ok := listener.Addr().(*net.TCPAddr)
	if !ok {
		return 0, errors.New("tunnel: reserved listener returned no TCP address")
	}
	return addr.Port, nil
}

type lineRing struct {
	mu      sync.Mutex
	max     int
	lines   []string
	partial string
}

func newLineRing(capacity int) *lineRing { return &lineRing{max: capacity} }

func (r *lineRing) Write(data []byte) (int, error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	text := r.partial + string(data)
	for {
		index := indexByte(text, '\n')
		if index < 0 {
			break
		}
		r.appendLocked(trimCR(text[:index]))
		text = text[index+1:]
	}
	r.partial = text
	if len(r.partial) > 8192 {
		r.partial = r.partial[len(r.partial)-8192:]
	}
	return len(data), nil
}

func (r *lineRing) Lines() []string {
	r.mu.Lock()
	defer r.mu.Unlock()
	out := append([]string{}, r.lines...)
	if r.partial != "" {
		out = append(out, r.partial)
	}
	return out
}

func (r *lineRing) appendLocked(line string) {
	r.lines = append(r.lines, line)
	if len(r.lines) > r.max {
		r.lines = append([]string{}, r.lines[len(r.lines)-r.max:]...)
	}
}

func indexByte(text string, target byte) int {
	for i := 0; i < len(text); i++ {
		if text[i] == target {
			return i
		}
	}
	return -1
}

func trimCR(line string) string {
	if len(line) > 0 && line[len(line)-1] == '\r' {
		return line[:len(line)-1]
	}
	return line
}

func (m *Manager) supervise(ctx context.Context, provider Provider, cmd *exec.Cmd, controlPort int, logs *lineRing, done chan struct{}, liveConfirmed chan struct{}) {
	defer close(done)

	current := cmd
	currentPort := controlPort
	currentLogs := logs
	backoff := backoffFloor
	var liveSince time.Time
	firstAttempt := true

	for {
		exited := make(chan error, 1)
		go func(c *exec.Cmd) { exited <- c.Wait() }(current)

		healthCtx, healthCancel := context.WithCancel(ctx)
		healthy := m.watchHealth(healthCtx, provider, currentPort)

		var confirmed bool
		if firstAttempt {
			firstAttempt = false
			select {
			case <-ctx.Done():
				healthCancel()
				m.stopChild(current, exited)
				return
			case <-exited:
			case <-liveConfirmed:
				confirmed = true
			}
		} else {
			urlCtx, urlCancel := context.WithCancel(ctx)
			urlResult := make(chan error, 1)
			go func() { urlResult <- m.awaitURL(urlCtx, provider, currentPort) }()

			select {
			case <-ctx.Done():
				urlCancel()
				healthCancel()
				m.stopChild(current, exited)
				return
			case <-exited:
				urlCancel()
			case err := <-urlResult:
				urlCancel()
				if err == nil {
					confirmed = true
				}
			}
		}

		if confirmed {
			liveSince = m.now()

			var stopped bool
			select {
			case <-ctx.Done():
				healthCancel()
				m.stopChild(current, exited)
				stopped = true
			case <-healthy:
				healthCancel()
				m.stopChild(current, exited)
			case <-exited:
				healthCancel()
			}
			if stopped {
				return
			}
		} else {
			healthCancel()
		}

		published := m.Status().URL != ""
		failure := provider.ClassifyFailure(currentLogs.Lines())
		class := combineFailure(published, failure)

		if class == FailureCredential || class == FailureRefused {
			m.handleProviderRefusal(ctx, provider, failure, class)
			return
		}

		m.mu.Lock()
		if !m.enabled {
			m.mu.Unlock()
			return
		}
		m.status.State = StateReconnecting
		m.status.URL = ""
		if failure.Message != "" {
			m.status.Error = failure.Message
		}
		m.status.Restarts++
		m.mu.Unlock()
		m.onProvider("")

		if !liveSince.IsZero() && m.now().Sub(liveSince) >= healthResetAfter {
			backoff = backoffFloor
		}
		liveSince = time.Time{}

		if err := m.sleep(ctx, backoff); err != nil {
			return
		}
		backoff *= 2
		if backoff > backoffCeiling {
			backoff = backoffCeiling
		}

		next, nextPort, nextLogs, err := m.spawn(provider)
		if err != nil {
			m.mu.Lock()
			m.status.Error = err.Error()
			m.mu.Unlock()
			continue
		}
		current, currentPort, currentLogs = next, nextPort, nextLogs

		m.mu.Lock()
		m.cmd = current
		m.logs = currentLogs
		m.mu.Unlock()
		m.recordPID(provider.Name(), current)
	}
}

func (m *Manager) watchHealth(ctx context.Context, provider Provider, controlPort int) <-chan struct{} {
	unhealthy := make(chan struct{})
	go func() {
		for m.Status().State != StateLive {
			select {
			case <-ctx.Done():
				return
			case <-time.After(2 * time.Millisecond):
			}
		}
		strikes := 0
		for {
			if err := m.sleep(ctx, healthInterval); err != nil {
				return
			}
			if m.Status().State != StateLive {
				return
			}
			ok, err := provider.Healthy(ctx, controlPort)
			if err == nil && ok {
				strikes = 0
				select {
				case <-ctx.Done():
					return
				case <-time.After(time.Millisecond):
				}
				continue
			}
			strikes++
			if strikes >= 2 {
				close(unhealthy)
				return
			}
		}
	}()
	return unhealthy
}

func (m *Manager) stopChild(cmd *exec.Cmd, exited chan error) {
	_ = terminateProcess(cmd)
	if exited == nil {
		return
	}
	select {
	case <-exited:
	case <-time.After(stopGrace):
		_ = forceKillProcess(cmd)
		<-exited
	}
}

func (m *Manager) spawn(provider Provider) (*exec.Cmd, int, *lineRing, error) {
	binary, err := m.binaries.Ensure(context.Background(), provider.Binary())
	if err != nil {
		return nil, 0, nil, err
	}
	controlPort, err := m.reservePort()
	if err != nil {
		return nil, 0, nil, err
	}
	m.mu.Lock()
	localPort := m.localPort
	m.mu.Unlock()

	logs := newLineRing(logRetention)
	cmd := newTunnelCommand(binary, provider.Args(localPort, controlPort)...)
	cmd.Stdout = logs
	cmd.Stderr = logs
	if err := cmd.Start(); err != nil {
		return nil, 0, nil, err
	}
	return cmd, controlPort, logs, nil
}

func combineFailure(published bool, failure Failure) FailureClass {
	switch failure.Class {
	case FailureCredential, FailureRefused, FailureNetwork:
		return failure.Class
	}
	if published {
		return FailureNetwork
	}
	return FailureRefused
}

func (m *Manager) handleProviderRefusal(context.Context, Provider, Failure, FailureClass) {}

func (m *Manager) recordPID(string, *exec.Cmd) {}
