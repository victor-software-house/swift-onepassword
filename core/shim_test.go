package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"runtime"
	"strconv"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/1password/onepassword-sdk-go"
)

// coldChildEnv makes the test binary open one client with a malformed token and print the time,
// so a benchmark can measure the first open of a fresh process.
const coldChildEnv = "OP_SHIM_COLD_CHILD"

func TestMain(m *testing.M) {
	if os.Getenv(coldChildEnv) == "1" {
		start := time.Now()
		out := open("malformed-token", "shim-test", "0")
		elapsed := time.Since(start)
		if !strings.Contains(out, `"kind":"authentication"`) {
			fmt.Fprintln(os.Stderr, "a malformed token did not give the authentication kind")
			os.Exit(1)
		}
		fmt.Println(elapsed.Nanoseconds())
		return
	}
	os.Exit(m.Run())
}

type vaultsStub struct {
	onepassword.VaultsAPI
	list func() ([]onepassword.VaultOverview, error)
}

func (s vaultsStub) List(context.Context, ...onepassword.VaultListParams) ([]onepassword.VaultOverview, error) {
	return s.list()
}

// register adds a client whose APIs are the given stubs, and removes it when the test ends.
func register(tb testing.TB, client *onepassword.Client) uint64 {
	tb.Helper()
	mu.Lock()
	next++
	handle := next
	clients[handle] = client
	mu.Unlock()
	tb.Cleanup(func() { closeClient(handle) })
	return handle
}

func parse(tb testing.TB, out string) reply {
	tb.Helper()
	var r reply
	if err := json.Unmarshal([]byte(out), &r); err != nil {
		tb.Fatalf("reply %q is not JSON: %v", out, err)
	}
	return r
}

func wantKind(t *testing.T, out, kind string) {
	t.Helper()
	r := parse(t, out)
	if r.Error == nil || r.Error.Kind != kind {
		t.Fatalf("reply %s: want error kind %s", out, kind)
	}
}

func TestUnknownHandle(t *testing.T) {
	wantKind(t, call(1<<40, `{"method":"vaults.list"}`), kindUnknownHandle)
}

func TestClosedHandleGivesTheTypedError(t *testing.T) {
	handle := register(t, &onepassword.Client{})
	closeClient(handle)
	wantKind(t, call(handle, `{"method":"vaults.list"}`), kindUnknownHandle)
	closeClient(handle) // a second close is harmless
}

func TestBadRequests(t *testing.T) {
	handle := register(t, &onepassword.Client{})
	for name, req := range map[string]string{
		"not JSON":            `{`,
		"unknown method":      `{"method":"vaults.delete"}`,
		"items.list no vault": `{"method":"items.list"}`,
		"items.get no item":   `{"method":"items.get","vaultId":"v"}`,
		"items.get no vault":  `{"method":"items.get","itemId":"i"}`,
		"empty request":       ``,
	} {
		t.Run(name, func(t *testing.T) { wantKind(t, call(handle, req), kindBadRequest) })
	}
}

func TestVaultsListResult(t *testing.T) {
	updated := time.Date(2026, 11, 17, 12, 30, 45, 123456789, time.UTC)
	handle := register(t, &onepassword.Client{VaultsAPI: vaultsStub{list: func() ([]onepassword.VaultOverview, error) {
		return []onepassword.VaultOverview{{ID: "v1", Title: "SSH keys", ContentVersion: 41, UpdatedAt: updated}}, nil
	}}})

	r := parse(t, call(handle, `{"method":"vaults.list"}`))
	if r.Error != nil {
		t.Fatalf("unexpected error %+v", r.Error)
	}
	var vaults []struct {
		ID             string `json:"id"`
		ContentVersion uint32 `json:"contentVersion"`
		UpdatedAt      string `json:"updatedAt"`
	}
	if err := json.Unmarshal(r.Result, &vaults); err != nil {
		t.Fatal(err)
	}
	if len(vaults) != 1 || vaults[0].ID != "v1" || vaults[0].ContentVersion != 41 {
		t.Fatalf("unexpected vaults %+v", vaults)
	}
	// Swift decodes this exact format, with nine fractional digits.
	if vaults[0].UpdatedAt != "2026-11-17T12:30:45.123456789Z" {
		t.Fatalf("unexpected timestamp %s", vaults[0].UpdatedAt)
	}
}

func TestSDKErrorsMapToKinds(t *testing.T) {
	for name, tc := range map[string]struct {
		err  error
		kind string
	}{
		"rate limited":         {&onepassword.RateLimitExceededError{}, kindRateLimited},
		"wrapped rate limited": {fmt.Errorf("call failed: %w", &onepassword.RateLimitExceededError{}), kindRateLimited},
		"refused token":        {errors.New("bad service account token, please rotate it: 401"), kindAuthentication},
		"not authenticated":    {errors.New("you are not authenticated"), kindAuthentication},
		"wrapped unauthorized": {fmt.Errorf("call failed: %w", errors.New("you are not authenticated")), kindAuthentication},
		"no permission":        {errors.New("you don't have the right permissions to access this resource"), kindOther},
		"network error":        {errors.New("dial tcp: lookup my.1password.com: no such host"), kindOther},
		"other":                {errors.New("boom"), kindOther},
	} {
		t.Run(name, func(t *testing.T) {
			handle := register(t, &onepassword.Client{VaultsAPI: vaultsStub{list: func() ([]onepassword.VaultOverview, error) {
				return nil, tc.err
			}}})
			wantKind(t, call(handle, `{"method":"vaults.list"}`), tc.kind)
		})
	}
}

// NewClient wraps the core's error in "error initializing client: %w", so the messages carry that prefix.
func TestOpenErrorsMapToKinds(t *testing.T) {
	for name, tc := range map[string]struct {
		err  error
		kind string
	}{
		"malformed token": {
			fmt.Errorf("error initializing client: %w", errors.New("invalid user input: encountered the following errors: service account token had invalid format")),
			kindAuthentication,
		},
		"unusable token": {
			fmt.Errorf("error initializing client: %w", errors.New("invalid service account token, please make sure you provide a valid service account token as parameter: x")),
			kindAuthentication,
		},
		"refused token": {
			fmt.Errorf("error initializing client: %w", errors.New("bad service account token, please rotate it: 401")),
			kindAuthentication,
		},
		"not authenticated": {
			fmt.Errorf("error initializing client: %w", errors.New("authentication error: you are not authenticated")),
			kindAuthentication,
		},
		"network error": {
			fmt.Errorf("error initializing client: %w", errors.New("authentication error: dial tcp: lookup my.1password.com: no such host")),
			kindOther,
		},
		"request timeout": {
			fmt.Errorf("error initializing client: %w", errors.New("request timeout")),
			kindOther,
		},
		"context deadline": {
			fmt.Errorf("error initializing client: %w", context.DeadlineExceeded),
			kindOther,
		},
		"rate limited": {
			fmt.Errorf("error initializing client: %w", &onepassword.RateLimitExceededError{}),
			kindRateLimited,
		},
	} {
		t.Run(name, func(t *testing.T) {
			if got := kindOf(tc.err); got != tc.kind {
				t.Fatalf("kindOf(%q) = %s, want %s", tc.err, got, tc.kind)
			}
		})
	}
}

func TestPanicIsRecovered(t *testing.T) {
	// A client with no APIs makes the SDK call dereference nil.
	handle := register(t, &onepassword.Client{})
	r := parse(t, call(handle, `{"method":"vaults.list"}`))
	if r.Error == nil || r.Error.Kind != kindOther || !strings.Contains(r.Error.Message, "panicked") {
		t.Fatalf("unexpected reply %+v", r)
	}
}

func TestMalformedTokenIsAuthentication(t *testing.T) {
	const token = "malformed-token-sentinel"
	out := open(token, "shim-test", "0")
	wantKind(t, out, kindAuthentication)
	if strings.Contains(out, token) {
		t.Fatalf("the error message holds the token: %s", out)
	}
}

func TestConcurrentUse(t *testing.T) {
	stub := &onepassword.Client{VaultsAPI: vaultsStub{list: func() ([]onepassword.VaultOverview, error) {
		return []onepassword.VaultOverview{}, nil
	}}}
	shared := register(t, stub)

	var wg sync.WaitGroup
	for range 32 {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for range 200 {
				if r := parse(t, call(shared, `{"method":"vaults.list"}`)); r.Error != nil {
					t.Errorf("unexpected error %+v", r.Error)
					return
				}
				own := register(t, stub)
				closeClient(own)
				if r := parse(t, call(own, `{"method":"vaults.list"}`)); r.Error == nil || r.Error.Kind != kindUnknownHandle {
					t.Errorf("a closed handle answered %+v", r)
					return
				}
			}
		}()
	}
	wg.Wait()
}

// A failed call builds one reply, so its allocations stay small and fixed.
func TestAllocationsPerCall(t *testing.T) {
	const bound = 10
	allocs := testing.AllocsPerRun(1000, func() { call(1<<40, `{"method":"vaults.list"}`) })
	t.Logf("unknown handle: %.0f allocations per call", allocs)
	if allocs > bound {
		t.Fatalf("%.0f allocations per call, more than %d", allocs, bound)
	}
}

// residentMiB is the process's resident size now, which ps reads.
func residentMiB(tb testing.TB) float64 {
	tb.Helper()
	out, err := exec.Command("ps", "-o", "rss=", "-p", strconv.Itoa(os.Getpid())).Output()
	if err != nil {
		tb.Fatal(err)
	}
	kib, err := strconv.ParseFloat(strings.TrimSpace(string(out)), 64)
	if err != nil {
		tb.Fatalf("ps printed %q", out)
	}
	return kib / 1024
}

type memory struct{ heapMiB, residentMiB float64 }

// snapshot collects garbage first, so the heap is what the program still holds.
func snapshot(tb testing.TB) memory {
	tb.Helper()
	runtime.GC()
	var stats runtime.MemStats
	runtime.ReadMemStats(&stats)
	return memory{heapMiB: float64(stats.HeapAlloc) / (1 << 20), residentMiB: residentMiB(tb)}
}

// An agent opens one client and keeps it, calling it every few minutes for days. A thousand calls
// on one client, through the stub clients and through the core with failing opens, must leave the
// Go heap and the resident size where they were; a slow leak shows as growth.
func TestLongLivedClientMemory(t *testing.T) {
	stub := register(t, &onepassword.Client{VaultsAPI: vaultsStub{list: func() ([]onepassword.VaultOverview, error) {
		return []onepassword.VaultOverview{{ID: "v1", Title: "SSH keys", ContentVersion: 41}}, nil
	}}})
	open("malformed-token", "shim-test", "0") // loads the core, which the numbers below start after
	for range 100 {
		call(stub, `{"method":"vaults.list"}`)
		open("malformed-token", "shim-test", "0")
	}
	start := snapshot(t)

	for range 1000 {
		call(stub, `{"method":"vaults.list"}`)
		open("malformed-token", "shim-test", "0")
	}
	end := snapshot(t)

	t.Logf("start: Go heap %.1f MiB, resident %.1f MiB", start.heapMiB, start.residentMiB)
	t.Logf("end:   Go heap %.1f MiB, resident %.1f MiB", end.heapMiB, end.residentMiB)
	if growth := end.heapMiB - start.heapMiB; growth > 2 {
		t.Fatalf("the Go heap grew by %.1f MiB over 1000 calls", growth)
	}
	if growth := end.residentMiB - start.residentMiB; growth > 16 {
		t.Fatalf("the resident size grew by %.1f MiB over 1000 calls", growth)
	}
}
