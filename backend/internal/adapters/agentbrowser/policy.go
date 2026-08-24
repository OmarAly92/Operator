// Package agentbrowser owns the daemon's standalone browser automation: it
// runs the packaged agent-browser binary against an isolated, managed Chromium
// with a minimal allowlisted child environment. The public REST contract and
// capability authorization stay in internal/service/browser.
package agentbrowser

import (
	"encoding/json"
	"fmt"
	"net/url"
	"regexp"
	"sort"
	"strings"

	"github.com/OmarAly92/operator/backend/internal/service/browser"
)

const (
	// MaxArguments bounds one native command's argument count.
	MaxArguments = 100
	// MaxArgumentChars bounds each native command argument's length.
	MaxArgumentChars = 16_384
)

var allowedCommands = map[string]struct{}{
	"open": {}, "snapshot": {}, "click": {}, "dblclick": {}, "focus": {}, "type": {}, "fill": {}, "press": {},
	"keyboard": {}, "keydown": {}, "keyup": {}, "hover": {}, "select": {}, "check": {}, "uncheck": {},
	"scroll": {}, "scrollintoview": {}, "drag": {}, "screenshot": {}, "wait": {}, "get": {}, "is": {},
	"find": {}, "tab": {}, "frame": {}, "dialog": {}, "console": {}, "errors": {}, "highlight": {}, "diff": {},
}

var forbiddenFlags = []string{
	"--cdp", "--auto-connect", "--session", "--namespace", "--profile", "--state", "--restore",
	"--executable-path", "--extension", "--init-script", "--args", "--headers", "--proxy",
	"--plugin", "--allowed-domains",
}

func commandError(code, message string) error {
	return browser.CommandError{Code: code, Message: message}
}

// ValidateArguments enforces Operator's native-command policy: only known
// automation commands, no ownership/persistence/transport flags, and explicit
// HTTP(S)-only navigation.
func ValidateArguments(args []string) error {
	if len(args) == 0 {
		return commandError("INVALID_ARGUMENT", "An agent-browser command is required")
	}
	if len(args) > MaxArguments {
		return commandError("INVALID_ARGUMENT", "Too many agent-browser arguments")
	}
	for _, arg := range args {
		if arg == "" || len([]rune(arg)) > MaxArgumentChars {
			return commandError("INVALID_ARGUMENT", "agent-browser arguments are invalid or too large")
		}
	}
	command := strings.ToLower(args[0])
	if _, ok := allowedCommands[command]; !ok {
		return commandError("AGENT_BROWSER_COMMAND_BLOCKED", fmt.Sprintf("agent-browser command is not enabled in Operator: %s", command))
	}
	for _, arg := range args {
		lower := strings.ToLower(arg)
		for _, flag := range forbiddenFlags {
			if lower == flag || strings.HasPrefix(lower, flag+"=") {
				return commandError("AGENT_BROWSER_COMMAND_BLOCKED", fmt.Sprintf("agent-browser flag is managed by Operator: %s", arg))
			}
		}
	}
	if command == "open" && len(args) > 1 && !strings.HasPrefix(args[1], "-") {
		if err := assertHTTPURL(args[1]); err != nil {
			return err
		}
	}
	if command == "diff" && (len(args) < 2 || strings.ToLower(args[1]) != "snapshot") {
		return commandError("AGENT_BROWSER_COMMAND_BLOCKED", "Only snapshot diff is enabled in Operator")
	}
	if command == "get" && len(args) > 1 && strings.ToLower(args[1]) == "cdp-url" {
		return commandError("AGENT_BROWSER_COMMAND_BLOCKED", "The private Operator CDP endpoint cannot be displayed")
	}
	return nil
}

func assertHTTPURL(raw string) error {
	parsed, err := url.Parse(strings.TrimSpace(raw))
	if err != nil {
		return commandError("INVALID_URL", "agent-browser navigation requires an explicit HTTP(S) URL")
	}
	scheme := strings.ToLower(parsed.Scheme)
	if scheme == "" {
		return commandError("INVALID_URL", "agent-browser navigation requires an explicit HTTP(S) URL")
	}
	if scheme != "http" && scheme != "https" {
		return commandError("BROWSER_URL_FORBIDDEN", fmt.Sprintf("Unsupported browser URL scheme: %s:", scheme))
	}
	if parsed.Host == "" {
		return commandError("INVALID_URL", "agent-browser navigation requires an explicit HTTP(S) URL")
	}
	return nil
}

var refPattern = regexp.MustCompile(`(?i)^@?e\d+$`)

func nativeRef(value string) string {
	if refPattern.MatchString(value) {
		return "@" + strings.TrimPrefix(value, "@")
	}
	return value
}

// NativeArgumentsForAction translates one public action plus its JSON args
// into validated native agent-browser arguments. Identifier-shaped failures
// use the stable codes the HTTP layer has always surfaced.
func NativeArgumentsForAction(action string, args map[string]interface{}) ([]string, error) {
	ref := func() (string, error) {
		value, ok := stringArg(args, "ref", false)
		if !ok {
			return "", commandError("REFERENCE_REQUIRED", "ref is required")
		}
		return nativeRef(value), nil
	}
	switch action {
	case "open":
		raw, ok := stringArg(args, "url", false)
		if !ok {
			return nil, commandError("URL_REQUIRED", "url is required")
		}
		if err := assertHTTPURL(raw); err != nil {
			return nil, err
		}
		return []string{"open", raw}, nil
	case "snapshot":
		out := []string{"snapshot"}
		if boolArg(args, "interactive") {
			out = append(out, "--interactive")
		}
		return append(out, "--compact"), nil
	case "click", "dblclick", "focus", "hover", "highlight", "scrollintoview", "check", "uncheck":
		elementRef, err := ref()
		if err != nil {
			return nil, err
		}
		return []string{action, elementRef}, nil
	case "fill", "type":
		elementRef, err := ref()
		if err != nil {
			return nil, err
		}
		text, ok := stringArg(args, "text", true)
		if !ok {
			return nil, commandError("INVALID_ARGUMENT", "text is required")
		}
		return []string{action, elementRef, text}, nil
	case "press":
		key, ok := stringArg(args, "key", false)
		if !ok {
			return nil, commandError("INVALID_ARGUMENT", "key is required")
		}
		return []string{"press", key}, nil
	case "drag":
		sourceRef, err := ref()
		if err != nil {
			return nil, err
		}
		targetRefValue, ok := stringArg(args, "targetRef", false)
		if !ok {
			return nil, commandError("REFERENCE_REQUIRED", "target ref is required")
		}
		return []string{"drag", sourceRef, nativeRef(targetRefValue)}, nil
	case "select":
		elementRef, err := ref()
		if err != nil {
			return nil, err
		}
		value, ok := stringArg(args, "value", true)
		if !ok {
			return nil, commandError("INVALID_ARGUMENT", "value is required")
		}
		return []string{"select", elementRef, value}, nil
	case "tabs":
		return []string{"tab", "list"}, nil
	case "tab-new":
		out := []string{"tab", "new"}
		if raw, ok := stringArg(args, "url", false); ok {
			if err := assertHTTPURL(raw); err != nil {
				return nil, err
			}
			out = append(out, raw)
		}
		return out, nil
	case "tab-select":
		tabID, ok := stringArg(args, "tabId", false)
		if !ok {
			return nil, commandError("TAB_ID_REQUIRED", "tabId is required")
		}
		return []string{"tab", tabID}, nil
	case "tab-close":
		out := []string{"tab", "close"}
		if tabID, ok := stringArg(args, "tabId", false); ok {
			out = append(out, tabID)
		}
		return out, nil
	case "scroll":
		direction, ok := stringArg(args, "direction", false)
		if !ok {
			return nil, commandError("INVALID_ARGUMENT", "direction is required")
		}
		switch strings.ToLower(direction) {
		case "up", "down", "left", "right":
		default:
			return nil, commandError("INVALID_ARGUMENT", "direction must be up, down, left, or right")
		}
		amount, err := numberArg(args, "amount", 600, 1, 5000)
		if err != nil {
			return nil, err
		}
		return []string{"scroll", strings.ToLower(direction), formatInt(int(amount))}, nil
	case "get":
		property, ok := stringArg(args, "property", false)
		if !ok {
			return nil, commandError("INVALID_ARGUMENT", "property is required")
		}
		property = strings.ToLower(property)
		switch property {
		case "url", "title", "text", "value", "checked":
		default:
			return nil, commandError("INVALID_ARGUMENT", fmt.Sprintf("Unsupported browser property: %s", property))
		}
		target, hasTarget := stringArg(args, "ref", false)
		if (property == "url" || property == "title") && hasTarget {
			return nil, commandError("INVALID_ARGUMENT", fmt.Sprintf("%s does not accept an element ref", property))
		}
		if (property == "value" || property == "checked") && !hasTarget {
			return nil, commandError("REFERENCE_REQUIRED", fmt.Sprintf("%s requires an element ref", property))
		}
		out := []string{"get", property}
		if hasTarget {
			out = append(out, nativeRef(target))
		}
		return out, nil
	case "wait":
		return nativeWaitArguments(args)
	case "frame":
		target, ok := stringArg(args, "target", false)
		if !ok {
			return nil, commandError("INVALID_ARGUMENT", "frame target is required")
		}
		if target == "main" {
			return []string{"frame", "main"}, nil
		}
		return []string{"frame", nativeRef(target)}, nil
	case "dialog":
		operation, ok := stringArg(args, "operation", false)
		if !ok {
			return nil, commandError("INVALID_ARGUMENT", "dialog operation is required")
		}
		switch strings.ToLower(operation) {
		case "accept", "dismiss", "status":
		default:
			return nil, commandError("INVALID_ARGUMENT", "dialog operation must be accept, dismiss, or status")
		}
		out := []string{"dialog", strings.ToLower(operation)}
		if text, ok := stringArg(args, "text", false); ok {
			out = append(out, text)
		}
		return out, nil
	case "console", "errors":
		return []string{action}, nil
	default:
		return nil, commandError("INVALID_ARGUMENT", fmt.Sprintf("Unsupported native browser action: %s", action))
	}
}

func nativeWaitArguments(args map[string]interface{}) ([]string, error) {
	timeout, err := numberArg(args, "timeoutMs", 10_000, 1, 55_000)
	if err != nil {
		return nil, err
	}
	timeoutText := formatInt(int(timeout))
	if text, ok := stringArg(args, "text", false); ok {
		return []string{"wait", "--text", text, "--timeout", timeoutText}, nil
	}
	if textGone, ok := stringArg(args, "textGone", false); ok {
		return []string{"wait", "text=" + textGone, "--state", "hidden", "--timeout", timeoutText}, nil
	}
	if selector, ok := stringArg(args, "selector", false); ok {
		return []string{"wait", selector, "--timeout", timeoutText}, nil
	}
	if selectorGone, ok := stringArg(args, "selectorGone", false); ok {
		return []string{"wait", selectorGone, "--state", "detached", "--timeout", timeoutText}, nil
	}
	if waitURL, ok := stringArg(args, "url", false); ok {
		return []string{"wait", "--url", "**" + waitURL + "**", "--timeout", timeoutText}, nil
	}
	if boolArg(args, "load") {
		return []string{"wait", "--load", "load", "--timeout", timeoutText}, nil
	}
	if stableMs, ok := numericField(args, "stableMs"); ok && stableMs > 0 {
		stable, err := numberArg(args, "stableMs", 500, 1, 60_000)
		if err != nil {
			return nil, err
		}
		expression := fmt.Sprintf(`(() => { const key = "__aoDomStability"; const now = performance.now(); let state = globalThis[key]; if (!state) { state = { lastMutation: now }; state.observer = new MutationObserver(() => { state.lastMutation = performance.now(); }); state.observer.observe(document, { subtree: true, childList: true, attributes: true, characterData: true }); globalThis[key] = state; } if (performance.now() - state.lastMutation < %d) return false; state.observer.disconnect(); delete globalThis[key]; return true; })()`, int(stable))
		return []string{"wait", "--fn", expression, "--timeout", timeoutText}, nil
	}
	if ms, ok := numericField(args, "ms"); ok && ms > 0 {
		return []string{"wait", formatInt(int(ms))}, nil
	}
	return nil, commandError("INVALID_ARGUMENT", "A wait condition is required")
}

func stringArg(args map[string]interface{}, key string, allowEmpty bool) (string, bool) {
	value, ok := args[key].(string)
	if !ok {
		return "", false
	}
	if !allowEmpty && strings.TrimSpace(value) == "" {
		return "", false
	}
	if allowEmpty {
		return value, true
	}
	return strings.TrimSpace(value), true
}

func boolArg(args map[string]interface{}, key string) bool {
	value, _ := args[key].(bool)
	return value
}

func numericField(args map[string]interface{}, key string) (float64, bool) {
	switch value := args[key].(type) {
	case float64:
		return value, true
	case int:
		return float64(value), true
	default:
		return 0, false
	}
}

func numberArg(args map[string]interface{}, key string, fallback float64, minimum, maximum float64) (float64, error) {
	value, present := numericField(args, key)
	if !present {
		return fallback, nil
	}
	bounds := fmt.Sprintf("Numeric argument must be between %d and %d", int(minimum), int(maximum))
	if value != value || value < minimum || value > maximum {
		return 0, commandError("INVALID_ARGUMENT", bounds)
	}
	return round(value), nil
}

func round(value float64) float64 {
	if value < 0 {
		return -float64(int(-value + 0.5))
	}
	return float64(int(value + 0.5))
}

func formatInt(value int) string {
	return fmt.Sprintf("%d", value)
}

// ParseJSON decodes agent-browser's structured envelope, propagates failures as
// stable command errors, and preserves the trusted root content-boundary field
// without ever forwarding a page-shaped `_boundary` lookalike.
func ParseJSON(stdout string) (map[string]interface{}, error) {
	var envelope interface{}
	if err := json.Unmarshal([]byte(stdout), &envelope); err != nil {
		return nil, commandError("AGENT_BROWSER_INVALID_OUTPUT", "Browser automation returned invalid structured output")
	}
	record, ok := envelope.(map[string]interface{})
	if !ok {
		return nil, commandError("AGENT_BROWSER_INVALID_OUTPUT", "Browser automation returned invalid output")
	}
	if success, exists := record["success"]; exists && success == false {
		message := stringError(record["error"])
		if message == "" {
			message = "Browser automation failed"
		}
		return nil, commandError("AGENT_BROWSER_COMMAND_FAILED", message)
	}
	boundary := validContentBoundary(record["_boundary"])
	result := map[string]interface{}{}
	if data, ok := record["data"].(map[string]interface{}); ok {
		for key, value := range data {
			result[key] = value
		}
	} else if data, exists := record["data"]; exists {
		result["value"] = data
	}
	delete(result, "_boundary")
	if boundary != nil {
		result["_boundary"] = boundary
	}
	result["untrustedExternalContent"] = true
	return result, nil
}

func validContentBoundary(value interface{}) map[string]interface{} {
	record, ok := value.(map[string]interface{})
	if !ok {
		return nil
	}
	nonce, nonceOK := record["nonce"].(string)
	origin, originOK := record["origin"].(string)
	if !nonceOK || nonce == "" || !originOK {
		return nil
	}
	return map[string]interface{}{"nonce": nonce, "origin": origin}
}

func stringError(value interface{}) string {
	if text, ok := value.(string); ok {
		return text
	}
	if record, ok := value.(map[string]interface{}); ok {
		if message, ok := record["message"].(string); ok {
			return message
		}
	}
	return ""
}

// inheritAllowedEnv copies the parent environment's execution and locale
// essentials, dropping everything else so shell credentials, API tokens, proxy
// configuration, and injection flags never reach the third-party binary.
func inheritAllowedEnv(parent map[string]string) map[string]string {
	env := make(map[string]string, len(parent)+16)
	for name, value := range parent {
		switch strings.ToLower(name) {
		case "path", "pathext", "systemroot", "windir", "comspec", "lang",
			"lc_all", "lc_ctype", "term", "colorterm", "no_color", "force_color":
			env[name] = value
		}
	}
	return env
}

// flattenEnv renders an environment map in exec.Cmd's KEY=VALUE form with
// deterministic ordering so logs and tests are stable.
func flattenEnv(env map[string]string) []string {
	names := make([]string, 0, len(env))
	for name := range env {
		names = append(names, name)
	}
	sort.Strings(names)
	out := make([]string, 0, len(names))
	for _, name := range names {
		out = append(out, name+"="+env[name])
	}
	return out
}
