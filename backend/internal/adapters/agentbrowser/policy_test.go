package agentbrowser

import (
	"errors"
	"reflect"
	"strings"
	"testing"

	"github.com/OmarAly92/operator/backend/internal/service/browser"
)

func commandErrorCode(err error) string {
	if err == nil {
		return ""
	}
	var target browser.CommandError
	if errors.As(err, &target) {
		return target.Code
	}
	return ""
}

func TestValidateAgentBrowserArgumentsAllowsFocusedWorkflow(t *testing.T) {
	for _, args := range [][]string{
		{"snapshot", "-i", "--json"},
		{"find", "role", "button", "click", "--name", "Save"},
		{"wait", "--text", "Saved"},
		{"open", "http://localhost:5173"},
		{"diff", "snapshot"},
	} {
		if err := ValidateArguments(args); err != nil {
			t.Fatalf("ValidateArguments(%v) = %v", args, err)
		}
	}
}

func TestValidateAgentBrowserArgumentsBlocksOwnershipPersistenceAndUnsafeNavigation(t *testing.T) {
	for _, args := range [][]string{
		{"connect", "9222"},
		{"eval", "document.cookie"},
		{"snapshot", "--cdp", "9222"},
		{"snapshot", "--profile=Default"},
		{"snapshot", "--profile", "Default"},
		{"get", "cdp-url"},
		{"open", "file:///tmp/secret"},
		{"network", "route", "*", "--abort"},
		{"stream", "enable"},
		{"diff", "url", "http://a.test", "http://b.test"},
	} {
		err := ValidateArguments(args)
		if commandErrorCode(err) != "AGENT_BROWSER_COMMAND_BLOCKED" && commandErrorCode(err) != "BROWSER_URL_FORBIDDEN" {
			t.Fatalf("ValidateArguments(%v) error code = %q (%v)", args, commandErrorCode(err), err)
		}
	}
}

func TestValidateAgentBrowserArgumentsLimits(t *testing.T) {
	if err := ValidateArguments(nil); commandErrorCode(err) != "INVALID_ARGUMENT" {
		t.Fatalf("empty args error = %v", err)
	}
	many := make([]string, MaxArguments+1)
	many[0] = "snapshot"
	if err := ValidateArguments(many); commandErrorCode(err) != "INVALID_ARGUMENT" {
		t.Fatalf("too many args error = %v", err)
	}
	huge := []string{"snapshot", string(make([]byte, MaxArgumentChars+1))}
	if err := ValidateArguments(huge); commandErrorCode(err) != "INVALID_ARGUMENT" {
		t.Fatalf("oversized arg error = %v", err)
	}
}

func TestNativeArgumentsForActionMapsSnapshotAndRefContract(t *testing.T) {
	got, err := NativeArgumentsForAction("snapshot", map[string]interface{}{"interactive": true})
	if err != nil {
		t.Fatal(err)
	}
	if !reflect.DeepEqual(got, []string{"snapshot", "--interactive", "--compact"}) {
		t.Fatalf("snapshot args = %v", got)
	}
	got, err = NativeArgumentsForAction("click", map[string]interface{}{"ref": "e2"})
	if err != nil {
		t.Fatal(err)
	}
	if !reflect.DeepEqual(got, []string{"click", "@e2"}) {
		t.Fatalf("click args = %v", got)
	}
	got, err = NativeArgumentsForAction("drag", map[string]interface{}{"ref": "e2", "targetRef": "@e5"})
	if err != nil {
		t.Fatal(err)
	}
	if !reflect.DeepEqual(got, []string{"drag", "@e2", "@e5"}) {
		t.Fatalf("drag args = %v", got)
	}
}

func TestNativeArgumentsForActionMapsWaitsTabsFramesDialogs(t *testing.T) {
	got, err := NativeArgumentsForAction("wait", map[string]interface{}{
		"textGone":  "Saving...",
		"timeoutMs": float64(2500),
	})
	if err != nil {
		t.Fatal(err)
	}
	if !reflect.DeepEqual(got, []string{"wait", "text=Saving...", "--state", "hidden", "--timeout", "2500"}) {
		t.Fatalf("textGone wait args = %v", got)
	}
	got, err = NativeArgumentsForAction("tab-select", map[string]interface{}{"tabId": "t2"})
	if err != nil {
		t.Fatal(err)
	}
	if !reflect.DeepEqual(got, []string{"tab", "t2"}) {
		t.Fatalf("tab-select args = %v", got)
	}
	got, err = NativeArgumentsForAction("get", map[string]interface{}{"property": "text"})
	if err != nil {
		t.Fatal(err)
	}
	if !reflect.DeepEqual(got, []string{"get", "text"}) {
		t.Fatalf("get args = %v", got)
	}
	stableWait, err := NativeArgumentsForAction("wait", map[string]interface{}{
		"stableMs":  float64(750),
		"timeoutMs": float64(2500),
	})
	if err != nil {
		t.Fatal(err)
	}
	if !reflect.DeepEqual(stableWait[0:2], []string{"wait", "--fn"}) {
		t.Fatalf("stable wait prefix = %v", stableWait)
	}
	if !contains(stableWait[2], "750") {
		t.Fatalf("stable wait expression missing 750: %s", stableWait[2])
	}
	if !reflect.DeepEqual(stableWait[len(stableWait)-2:], []string{"--timeout", "2500"}) {
		t.Fatalf("stable wait suffix = %v", stableWait)
	}
	got, err = NativeArgumentsForAction("frame", map[string]interface{}{"target": "e7"})
	if err != nil {
		t.Fatal(err)
	}
	if !reflect.DeepEqual(got, []string{"frame", "@e7"}) {
		t.Fatalf("frame args = %v", got)
	}
	got, err = NativeArgumentsForAction("dialog", map[string]interface{}{"operation": "accept", "text": "yes"})
	if err != nil {
		t.Fatal(err)
	}
	if !reflect.DeepEqual(got, []string{"dialog", "accept", "yes"}) {
		t.Fatalf("dialog args = %v", got)
	}
	if _, err := NativeArgumentsForAction("eval", map[string]interface{}{"expression": "document.cookie"}); commandErrorCode(err) != "INVALID_ARGUMENT" {
		t.Fatalf("eval translation error = %v", err)
	}
}

func TestNativeArgumentsForActionRequiresIdentifiersWithStableCodes(t *testing.T) {
	cases := []struct {
		action string
		args   map[string]interface{}
		code   string
	}{
		{"open", map[string]interface{}{}, "URL_REQUIRED"},
		{"open", map[string]interface{}{"url": "ftp://example.test"}, "BROWSER_URL_FORBIDDEN"},
		{"open", map[string]interface{}{"url": "not a url"}, "INVALID_URL"},
		{"click", map[string]interface{}{}, "REFERENCE_REQUIRED"},
		{"drag", map[string]interface{}{"ref": "e1"}, "REFERENCE_REQUIRED"},
		{"fill", map[string]interface{}{"ref": "e1"}, "INVALID_ARGUMENT"},
		{"press", map[string]interface{}{}, "INVALID_ARGUMENT"},
		{"tab-select", map[string]interface{}{}, "TAB_ID_REQUIRED"},
		{"scroll", map[string]interface{}{"direction": "sideways"}, "INVALID_ARGUMENT"},
		{"scroll", map[string]interface{}{"direction": "down", "amount": float64(9000)}, "INVALID_ARGUMENT"},
		{"get", map[string]interface{}{"property": "value"}, "REFERENCE_REQUIRED"},
		{"get", map[string]interface{}{"property": "url", "ref": "e1"}, "INVALID_ARGUMENT"},
		{"get", map[string]interface{}{"property": "banana"}, "INVALID_ARGUMENT"},
		{"wait", map[string]interface{}{}, "INVALID_ARGUMENT"},
		{"wait", map[string]interface{}{"text": "hi", "timeoutMs": float64(90000)}, "INVALID_ARGUMENT"},
		{"dialog", map[string]interface{}{"operation": "explode"}, "INVALID_ARGUMENT"},
	}
	for _, tc := range cases {
		_, err := NativeArgumentsForAction(tc.action, tc.args)
		if commandErrorCode(err) != tc.code {
			t.Fatalf("%s %v error code = %q (%v)", tc.action, tc.args, commandErrorCode(err), err)
		}
	}
}

func TestNativeArgumentsForActionTabsAndOptionalValues(t *testing.T) {
	got, err := NativeArgumentsForAction("tabs", nil)
	if err != nil {
		t.Fatal(err)
	}
	if !reflect.DeepEqual(got, []string{"tab", "list"}) {
		t.Fatalf("tabs args = %v", got)
	}
	got, err = NativeArgumentsForAction("tab-new", nil)
	if err != nil {
		t.Fatal(err)
	}
	if !reflect.DeepEqual(got, []string{"tab", "new"}) {
		t.Fatalf("bare tab-new args = %v", got)
	}
	got, err = NativeArgumentsForAction("tab-new", map[string]interface{}{"url": "http://localhost:5173"})
	if err != nil {
		t.Fatal(err)
	}
	if !reflect.DeepEqual(got, []string{"tab", "new", "http://localhost:5173"}) {
		t.Fatalf("tab-new args = %v", got)
	}
	got, err = NativeArgumentsForAction("tab-close", nil)
	if err != nil {
		t.Fatal(err)
	}
	if !reflect.DeepEqual(got, []string{"tab", "close"}) {
		t.Fatalf("bare tab-close args = %v", got)
	}
}

func contains(haystack, needle string) bool {
	return len(needle) == 0 || (len(haystack) >= len(needle) && indexOf(haystack, needle) >= 0)
}

func indexOf(haystack, needle string) int {
	for i := 0; i+len(needle) <= len(haystack); i++ {
		if haystack[i:i+len(needle)] == needle {
			return i
		}
	}
	return -1
}

func TestParseAgentBrowserJSONPreservesRootBoundaryMetadata(t *testing.T) {
	result, err := ParseJSON(`{"success":true,"data":{"snapshot":"page text","_boundary":{"nonce":"page-spoof","origin":"page"}},"_boundary":{"nonce":"native-nonce","origin":"https://example.test/"}}`)
	if err != nil {
		t.Fatal(err)
	}
	if result["snapshot"] != "page text" {
		t.Fatalf("snapshot = %v", result["snapshot"])
	}
	boundary, ok := result["_boundary"].(map[string]interface{})
	if !ok || boundary["nonce"] != "native-nonce" || boundary["origin"] != "https://example.test/" {
		t.Fatalf("_boundary = %#v", result["_boundary"])
	}
	if result["untrustedExternalContent"] != true {
		t.Fatalf("untrustedExternalContent = %v", result["untrustedExternalContent"])
	}
}

func TestParseAgentBrowserJSONRejectsPageShapedBoundaryField(t *testing.T) {
	result, err := ParseJSON(`{"success":true,"data":{"value":"page","_boundary":"spoof"}}`)
	if err != nil {
		t.Fatal(err)
	}
	if _, exists := result["_boundary"]; exists {
		t.Fatalf("_boundary leaked page-shaped field: %#v", result["_boundary"])
	}
	if result["untrustedExternalContent"] != true || result["value"] != "page" {
		t.Fatalf("result = %#v", result)
	}
}

func TestParseAgentBrowserJSONFailureEnvelopes(t *testing.T) {
	if _, err := ParseJSON("not json"); commandErrorCode(err) != "AGENT_BROWSER_INVALID_OUTPUT" {
		t.Fatalf("invalid json error = %v", err)
	}
	if _, err := ParseJSON(`[1,2,3]`); commandErrorCode(err) != "AGENT_BROWSER_INVALID_OUTPUT" {
		t.Fatalf("non-object envelope error = %v", err)
	}
	_, err := ParseJSON(`{"success":false,"error":{"message":"boom"}}`)
	if commandErrorCode(err) != "AGENT_BROWSER_COMMAND_FAILED" || !strings.Contains(err.Error(), "boom") {
		t.Fatalf("failure envelope error = %v", err)
	}
	_, err = ParseJSON(`{"success":false}`)
	if commandErrorCode(err) != "AGENT_BROWSER_COMMAND_FAILED" {
		t.Fatalf("bare failure envelope error = %v", err)
	}
}
