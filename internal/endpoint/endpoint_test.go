package endpoint

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/tsosunchia/apple-cdn-network-bench/internal/render"
)

func newTestBus() *render.Bus {
	return render.NewBus(render.NewPlainRenderer(&strings.Builder{}))
}

func TestHostFromURL(t *testing.T) {
	tests := []struct {
		input, want string
	}{
		{"https://mensura.cdn-apple.com/api/v1/gm/large", "mensura.cdn-apple.com"},
		{"http://example.com:8080/path", "example.com"},
		{"not-a-url", ""},
	}
	for _, tt := range tests {
		got := HostFromURL(tt.input)
		if got != tt.want {
			t.Errorf("HostFromURL(%q) = %q, want %q", tt.input, got, tt.want)
		}
	}
}

func TestChooseEmptyHost(t *testing.T) {
	bus := newTestBus()
	defer bus.Close()
	ep := Choose(context.Background(), "", bus, false)
	if ep.IP != "" {
		t.Errorf("expected empty endpoint, got %+v", ep)
	}
}

func TestFetchInfoMockSuccess(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		resp := map[string]string{
			"status":     "success",
			"query":      "1.2.3.4",
			"as":         "AS1234 Example",
			"isp":        "Example ISP",
			"city":       "Tokyo",
			"regionName": "Tokyo",
			"country":    "Japan",
		}
		json.NewEncoder(w).Encode(resp)
	}))
	defer srv.Close()

	// We cannot easily override the URL in FetchInfo, so test the JSON parsing path
	// by calling the server directly
	resp, err := http.Get(srv.URL)
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	var info IPInfo
	if err := json.NewDecoder(resp.Body).Decode(&info); err != nil {
		t.Fatal(err)
	}
	if info.Status != "success" {
		t.Errorf("status = %q", info.Status)
	}
	if info.City != "Tokyo" {
		t.Errorf("city = %q", info.City)
	}
}

func TestResolveDoHMock(t *testing.T) {
	// Test with the structured AliDNS response format
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprint(w, `{"Answer":[{"data":"1.2.3.4"},{"data":"5.6.7.8"}]}`)
	}))
	defer srv.Close()

	// Can't directly test resolveDoH without refactoring, but test the JSON parsing
	var dr dohResponse
	resp, _ := http.Get(srv.URL)
	defer resp.Body.Close()
	json.NewDecoder(resp.Body).Decode(&dr)
	if len(dr.Answer) != 2 {
		t.Errorf("expected 2 answers, got %d", len(dr.Answer))
	}
}

func TestResolveDoHFallbackRegex(t *testing.T) {
	// Test with raw text containing IPs (like the short=1 format)
	body := "1.2.3.4\n5.6.7.8\n1.2.3.4\n"
	ips := ipv4Re.FindAllString(body, -1)
	if len(ips) != 3 {
		t.Errorf("expected 3 matches, got %d", len(ips))
	}
	// Deduplicate
	seen := map[string]bool{}
	var unique []string
	for _, ip := range ips {
		if !seen[ip] {
			seen[ip] = true
			unique = append(unique, ip)
		}
	}
	if len(unique) != 2 {
		t.Errorf("expected 2 unique, got %d", len(unique))
	}
}
