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
		if !strings.Contains(out, `"code":"authenticationFailed"`) {
			fmt.Fprintln(os.Stderr, "a malformed token did not give the authenticationFailed code")
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

func parse(tb testing.TB, out string) response {
	tb.Helper()
	var res response
	if err := json.Unmarshal([]byte(out), &res); err != nil {
		tb.Fatalf("response %q is not JSON: %v", out, err)
	}
	return res
}

func wantCode(t *testing.T, out, code string) {
	t.Helper()
	res := parse(t, out)
	if res.Error == nil || res.Error.Code != code {
		t.Fatalf("response %s: want error code %s", out, code)
	}
}

func TestUnknownHandle(t *testing.T) {
	wantCode(t, call(1<<40, `{"method":"vaults.list"}`), codeUnknownClient)
}

func TestClosedHandleGivesTheTypedError(t *testing.T) {
	handle := register(t, &onepassword.Client{})
	closeClient(handle)
	wantCode(t, call(handle, `{"method":"vaults.list"}`), codeUnknownClient)
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
		t.Run(name, func(t *testing.T) { wantCode(t, call(handle, req), codeInvalidRequest) })
	}
}

func TestVaultsListResult(t *testing.T) {
	updated := time.Date(2026, 11, 17, 12, 30, 45, 123456789, time.UTC)
	handle := register(t, &onepassword.Client{VaultsAPI: vaultsStub{list: func() ([]onepassword.VaultOverview, error) {
		return []onepassword.VaultOverview{{ID: "v1", Title: "SSH keys", ContentVersion: 41, UpdatedAt: updated}}, nil
	}}})

	res := parse(t, call(handle, `{"method":"vaults.list"}`))
	if res.Error != nil {
		t.Fatalf("unexpected error %+v", res.Error)
	}
	var vaults []struct {
		ID             string `json:"id"`
		ContentVersion uint32 `json:"contentVersion"`
		UpdatedAt      string `json:"updatedAt"`
	}
	if err := json.Unmarshal(res.Result, &vaults); err != nil {
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

func TestSDKErrorsMapToCodes(t *testing.T) {
	for name, tc := range map[string]struct {
		err  error
		code string
	}{
		"rate limited":         {&onepassword.RateLimitExceededError{}, codeRateLimited},
		"wrapped rate limited": {fmt.Errorf("call failed: %w", &onepassword.RateLimitExceededError{}), codeRateLimited},
		"refused token":        {errors.New("bad service account token, please rotate it: 401"), codeAuthenticationFailed},
		"not authenticated":    {errors.New("you are not authenticated"), codeAuthenticationFailed},
		"wrapped unauthorized": {fmt.Errorf("call failed: %w", errors.New("you are not authenticated")), codeAuthenticationFailed},
		"no permission":        {errors.New("you don't have the right permissions to access this resource"), codeRequestFailed},
		"network error":        {errors.New("dial tcp: lookup my.1password.com: no such host"), codeRequestFailed},
		"other":                {errors.New("boom"), codeRequestFailed},
	} {
		t.Run(name, func(t *testing.T) {
			handle := register(t, &onepassword.Client{VaultsAPI: vaultsStub{list: func() ([]onepassword.VaultOverview, error) {
				return nil, tc.err
			}}})
			wantCode(t, call(handle, `{"method":"vaults.list"}`), tc.code)
		})
	}
}

// NewClient wraps the core's error in "error initializing client: %w", so the messages carry that prefix.
func TestOpenErrorsMapToCodes(t *testing.T) {
	for name, tc := range map[string]struct {
		err  error
		code string
	}{
		"malformed token": {
			fmt.Errorf("error initializing client: %w", errors.New("invalid user input: encountered the following errors: service account token had invalid format")),
			codeAuthenticationFailed,
		},
		"unusable token": {
			fmt.Errorf("error initializing client: %w", errors.New("invalid service account token, please make sure you provide a valid service account token as parameter: x")),
			codeAuthenticationFailed,
		},
		"refused token": {
			fmt.Errorf("error initializing client: %w", errors.New("bad service account token, please rotate it: 401")),
			codeAuthenticationFailed,
		},
		"not authenticated": {
			fmt.Errorf("error initializing client: %w", errors.New("authentication error: you are not authenticated")),
			codeAuthenticationFailed,
		},
		"network error": {
			fmt.Errorf("error initializing client: %w", errors.New("authentication error: dial tcp: lookup my.1password.com: no such host")),
			codeRequestFailed,
		},
		"request timeout": {
			fmt.Errorf("error initializing client: %w", errors.New("request timeout")),
			codeRequestFailed,
		},
		"context deadline": {
			fmt.Errorf("error initializing client: %w", context.DeadlineExceeded),
			codeRequestFailed,
		},
		"rate limited": {
			fmt.Errorf("error initializing client: %w", &onepassword.RateLimitExceededError{}),
			codeRateLimited,
		},
	} {
		t.Run(name, func(t *testing.T) {
			if got := codeOf(tc.err); got != tc.code {
				t.Fatalf("codeOf(%q) = %s, want %s", tc.err, got, tc.code)
			}
		})
	}
}

func TestPanicIsRecovered(t *testing.T) {
	// A client with no APIs makes the SDK call dereference nil.
	handle := register(t, &onepassword.Client{})
	res := parse(t, call(handle, `{"method":"vaults.list"}`))
	if res.Error == nil || res.Error.Code != codeRequestFailed || !strings.Contains(res.Error.Message, "panicked") {
		t.Fatalf("unexpected response %+v", res)
	}
}

func TestMalformedTokenIsAuthentication(t *testing.T) {
	const token = "malformed-token-sentinel"
	out := open(token, "shim-test", "0")
	wantCode(t, out, codeAuthenticationFailed)
	if strings.Contains(out, token) {
		t.Fatalf("the error message contains the token: %s", out)
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
				if res := parse(t, call(shared, `{"method":"vaults.list"}`)); res.Error != nil {
					t.Errorf("unexpected error %+v", res.Error)
					return
				}
				own := register(t, stub)
				closeClient(own)
				if res := parse(t, call(own, `{"method":"vaults.list"}`)); res.Error == nil || res.Error.Code != codeUnknownClient {
					t.Errorf("a closed handle answered %+v", res)
					return
				}
			}
		}()
	}
	wg.Wait()
}

// A failed call builds one response, so its allocations stay small and fixed.
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

// snapshot collects garbage first, so the heap is what the program still uses.
func snapshot(tb testing.TB) memory {
	tb.Helper()
	runtime.GC()
	var stats runtime.MemStats
	runtime.ReadMemStats(&stats)
	return memory{heapMiB: float64(stats.HeapAlloc) / (1 << 20), residentMiB: residentMiB(tb)}
}

// An agent opens one client and keeps it, calling it every few minutes for days.
// A thousand calls on one client must leave the Go heap and the resident size where they were.
// The calls go through the stub clients, and through the core with failing opens.
// A slow leak shows as growth.
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
