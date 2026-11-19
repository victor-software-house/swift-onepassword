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

// itemsStub stubs the items API. A method with no function makes the test fail, so a test that
// expects no SDK call stubs nothing.
type itemsStub struct {
	onepassword.ItemsAPI
	tb        testing.TB
	createAll func(vaultID string, params []onepassword.ItemCreateParams) (onepassword.ItemsUpdateAllResponse, error)
	getAll    func(vaultID string, ids []string) (onepassword.ItemsGetAllResponse, error)
	get       func(vaultID, itemID string) (onepassword.Item, error)
	put       func(item onepassword.Item) (onepassword.Item, error)
	deleteAll func(vaultID string, ids []string) (onepassword.ItemsDeleteAllResponse, error)
	archive   func(vaultID, itemID string) error
}

func (s itemsStub) CreateAll(_ context.Context, vaultID string, params []onepassword.ItemCreateParams) (onepassword.ItemsUpdateAllResponse, error) {
	if s.createAll == nil {
		s.tb.Error("unexpected call to CreateAll")
		return onepassword.ItemsUpdateAllResponse{}, nil
	}
	return s.createAll(vaultID, params)
}

func (s itemsStub) GetAll(_ context.Context, vaultID string, ids []string) (onepassword.ItemsGetAllResponse, error) {
	if s.getAll == nil {
		s.tb.Error("unexpected call to GetAll")
		return onepassword.ItemsGetAllResponse{}, nil
	}
	return s.getAll(vaultID, ids)
}

func (s itemsStub) Get(_ context.Context, vaultID, itemID string) (onepassword.Item, error) {
	if s.get == nil {
		s.tb.Error("unexpected call to Get")
		return onepassword.Item{}, nil
	}
	return s.get(vaultID, itemID)
}

func (s itemsStub) Put(_ context.Context, item onepassword.Item) (onepassword.Item, error) {
	if s.put == nil {
		s.tb.Error("unexpected call to Put")
		return onepassword.Item{}, nil
	}
	return s.put(item)
}

func (s itemsStub) DeleteAll(_ context.Context, vaultID string, ids []string) (onepassword.ItemsDeleteAllResponse, error) {
	if s.deleteAll == nil {
		s.tb.Error("unexpected call to DeleteAll")
		return onepassword.ItemsDeleteAllResponse{}, nil
	}
	return s.deleteAll(vaultID, ids)
}

func (s itemsStub) Archive(_ context.Context, vaultID, itemID string) error {
	if s.archive == nil {
		s.tb.Error("unexpected call to Archive")
		return nil
	}
	return s.archive(vaultID, itemID)
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

func TestWriteBadRequests(t *testing.T) {
	handle := register(t, &onepassword.Client{ItemsAPI: itemsStub{tb: t}})
	for name, req := range map[string]string{
		"createAll no vault":         `{"method":"items.createAll","items":[{"title":"t"}]}`,
		"createAll no items":         `{"method":"items.createAll","vaultId":"v"}`,
		"createAll empty items":      `{"method":"items.createAll","vaultId":"v","items":[]}`,
		"createAll items not a list": `{"method":"items.createAll","vaultId":"v","items":{"title":"t"}}`,
		"getAll no vault":            `{"method":"items.getAll","itemIds":["i"]}`,
		"getAll no ids":              `{"method":"items.getAll","vaultId":"v"}`,
		"getAll empty ids":           `{"method":"items.getAll","vaultId":"v","itemIds":[]}`,
		"update no vault":            `{"method":"items.update","itemId":"i","content":{"title":"t"}}`,
		"update no item":             `{"method":"items.update","vaultId":"v","content":{"title":"t"}}`,
		"update no content":          `{"method":"items.update","vaultId":"v","itemId":"i"}`,
		"update no title":            `{"method":"items.update","vaultId":"v","itemId":"i","content":{"notes":"n"}}`,
		"deleteAll no vault":         `{"method":"items.deleteAll","itemIds":["i"]}`,
		"deleteAll no ids":           `{"method":"items.deleteAll","vaultId":"v"}`,
		"deleteAll empty ids":        `{"method":"items.deleteAll","vaultId":"v","itemIds":[]}`,
		"archive no vault":           `{"method":"items.archive","itemId":"i"}`,
		"archive no item":            `{"method":"items.archive","vaultId":"v"}`,
	} {
		t.Run(name, func(t *testing.T) { wantCode(t, call(handle, req), codeInvalidRequest) })
	}
}

// batchEntry reads one entry of an items.createAll or items.getAll result.
type batchEntry struct {
	Item *struct {
		ID      string `json:"id"`
		VaultID string `json:"vaultId"`
		Title   string `json:"title"`
	} `json:"item"`
	Failure string `json:"failure"`
}

func batchResult(t *testing.T, out string) []batchEntry {
	t.Helper()
	res := parse(t, out)
	if res.Error != nil {
		t.Fatalf("unexpected error %+v", res.Error)
	}
	var got []batchEntry
	if err := json.Unmarshal(res.Result, &got); err != nil {
		t.Fatal(err)
	}
	return got
}

func TestCreateAllKeepsOrderAndFailureTypes(t *testing.T) {
	var sent []onepassword.ItemCreateParams
	handle := register(t, &onepassword.Client{ItemsAPI: itemsStub{tb: t,
		createAll: func(vaultID string, params []onepassword.ItemCreateParams) (onepassword.ItemsUpdateAllResponse, error) {
			if vaultID != "v" {
				t.Errorf("vault %q, want v", vaultID)
			}
			sent = params
			created := onepassword.Item{ID: "i1", VaultID: "v", Title: "first"}
			rejected := onepassword.NewItemUpdateFailureReasonTypeVariantItemValidationError("a message the core drops")
			return onepassword.ItemsUpdateAllResponse{IndividualResponses: []onepassword.Response[onepassword.Item, onepassword.ItemUpdateFailureReason]{
				{Content: &created},
				{Error: &rejected},
			}}, nil
		}}})

	req := `{"method":"items.createAll","vaultId":"v","items":[
		{"category":"SecureNote","title":"first","notes":"n","tags":["t"],"fields":[{"id":"f","title":"f","fieldType":"Concealed","value":"x"}]},
		{"category":"SshKey","title":"second"}]}`
	got := batchResult(t, call(handle, req))

	if len(got) != 2 || got[0].Item == nil || got[0].Item.ID != "i1" || got[0].Failure != "" {
		t.Fatalf("unexpected first entry in %+v", got)
	}
	if got[1].Item != nil || got[1].Failure != "itemValidationError" {
		t.Fatalf("unexpected second entry in %+v", got)
	}
	if len(sent) != 2 || sent[0].Title != "first" || sent[1].Title != "second" || sent[0].Category != onepassword.ItemCategorySecureNote {
		t.Fatalf("unexpected params %+v", sent)
	}
	if sent[0].VaultID != "v" || sent[1].VaultID != "v" {
		t.Fatalf("the core must set the vault of each item: %+v", sent)
	}
	if len(sent[0].Fields) != 1 || sent[0].Fields[0].FieldType != onepassword.ItemFieldTypeConcealed || sent[0].Fields[0].Value != "x" {
		t.Fatalf("unexpected fields %+v", sent[0].Fields)
	}
	if sent[0].Notes == nil || *sent[0].Notes != "n" || len(sent[0].Tags) != 1 {
		t.Fatalf("unexpected notes or tags in %+v", sent[0])
	}
}

func TestGetAllKeepsOrderAndFailureTypes(t *testing.T) {
	handle := register(t, &onepassword.Client{ItemsAPI: itemsStub{tb: t,
		getAll: func(vaultID string, ids []string) (onepassword.ItemsGetAllResponse, error) {
			if vaultID != "v" || len(ids) != 3 || ids[0] != "a" || ids[1] != "b" || ids[2] != "c" {
				t.Errorf("unexpected arguments %q %q", vaultID, ids)
			}
			first := onepassword.Item{ID: "a", Title: "A"}
			third := onepassword.Item{ID: "c", Title: "C"}
			missing := onepassword.NewItemsGetAllErrorTypeVariantItemNotFound()
			return onepassword.ItemsGetAllResponse{IndividualResponses: []onepassword.Response[onepassword.Item, onepassword.ItemsGetAllError]{
				{Content: &first},
				{Error: &missing},
				{Content: &third},
			}}, nil
		}}})

	got := batchResult(t, call(handle, `{"method":"items.getAll","vaultId":"v","itemIds":["a","b","c"]}`))

	if len(got) != 3 || got[0].Item == nil || got[0].Item.ID != "a" || got[2].Item == nil || got[2].Item.ID != "c" {
		t.Fatalf("unexpected entries %+v", got)
	}
	if got[1].Item != nil || got[1].Failure != "itemNotFound" {
		t.Fatalf("unexpected second entry in %+v", got)
	}
}

func TestBatchAnswerOfTheWrongSizeFails(t *testing.T) {
	handle := register(t, &onepassword.Client{ItemsAPI: itemsStub{tb: t,
		getAll: func(string, []string) (onepassword.ItemsGetAllResponse, error) {
			return onepassword.ItemsGetAllResponse{}, nil
		}}})
	wantCode(t, call(handle, `{"method":"items.getAll","vaultId":"v","itemIds":["a"]}`), codeRequestFailed)
}

func TestWriteSDKErrorsMapToCodes(t *testing.T) {
	boom := func() error { return &onepassword.RateLimitExceededError{} }
	handle := register(t, &onepassword.Client{ItemsAPI: itemsStub{tb: t,
		createAll: func(string, []onepassword.ItemCreateParams) (onepassword.ItemsUpdateAllResponse, error) {
			return onepassword.ItemsUpdateAllResponse{}, boom()
		},
		archive: func(string, string) error { return boom() },
	}})
	wantCode(t, call(handle, `{"method":"items.createAll","vaultId":"v","items":[{"title":"t"}]}`), codeRateLimited)
	wantCode(t, call(handle, `{"method":"items.archive","vaultId":"v","itemId":"i"}`), codeRateLimited)
}

func TestDeleteAllReportsOnlyFailedIDs(t *testing.T) {
	handle := register(t, &onepassword.Client{ItemsAPI: itemsStub{tb: t,
		deleteAll: func(vaultID string, ids []string) (onepassword.ItemsDeleteAllResponse, error) {
			if vaultID != "v" || len(ids) != 2 {
				t.Errorf("unexpected arguments %q %q", vaultID, ids)
			}
			denied := onepassword.NewItemUpdateFailureReasonTypeVariantItemStatusPermissionError()
			return onepassword.ItemsDeleteAllResponse{IndividualResponses: map[string]onepassword.Response[struct{}, onepassword.ItemUpdateFailureReason]{
				"ok":     {Content: &struct{}{}},
				"denied": {Error: &denied},
			}}, nil
		}}})

	res := parse(t, call(handle, `{"method":"items.deleteAll","vaultId":"v","itemIds":["ok","denied"]}`))
	if res.Error != nil {
		t.Fatalf("unexpected error %+v", res.Error)
	}
	var failed map[string]string
	if err := json.Unmarshal(res.Result, &failed); err != nil {
		t.Fatal(err)
	}
	if len(failed) != 1 || failed["denied"] != "itemStatusPermissionError" {
		t.Fatalf("unexpected failures %+v", failed)
	}
}

func TestDeleteAllWithNoFailureGivesAnEmptyObject(t *testing.T) {
	handle := register(t, &onepassword.Client{ItemsAPI: itemsStub{tb: t,
		deleteAll: func(string, []string) (onepassword.ItemsDeleteAllResponse, error) {
			return onepassword.ItemsDeleteAllResponse{IndividualResponses: map[string]onepassword.Response[struct{}, onepassword.ItemUpdateFailureReason]{
				"ok": {Content: &struct{}{}},
			}}, nil
		}}})

	res := parse(t, call(handle, `{"method":"items.deleteAll","vaultId":"v","itemIds":["ok"]}`))
	if res.Error != nil || string(res.Result) != "{}" {
		t.Fatalf("unexpected response %+v %s", res.Error, res.Result)
	}
}

func TestUpdateKeepsWhatContentDoesNotSet(t *testing.T) {
	read := onepassword.Item{
		ID:       "i",
		Title:    "old",
		Category: onepassword.ItemCategoryLogin,
		VaultID:  "v",
		Fields:   []onepassword.ItemField{{ID: "old", Title: "old", FieldType: onepassword.ItemFieldTypeText, Value: "old"}},
		Sections: []onepassword.ItemSection{{ID: "old", Title: "old"}},
		Notes:    "old",
		Tags:     []string{"old"},
		Websites: []onepassword.Website{{URL: "https://example.invalid", Label: "site", AutofillBehavior: onepassword.AutofillBehaviorNever}},
		Version:  7,
		Files:    []onepassword.ItemFile{{SectionID: "s", FieldID: "f"}},
		Document: &onepassword.FileAttributes{Name: "doc", ID: "d", Size: 3},
	}
	var written onepassword.Item
	handle := register(t, &onepassword.Client{ItemsAPI: itemsStub{tb: t,
		get: func(vaultID, itemID string) (onepassword.Item, error) {
			if vaultID != "v" || itemID != "i" {
				t.Errorf("unexpected arguments %q %q", vaultID, itemID)
			}
			return read, nil
		},
		put: func(item onepassword.Item) (onepassword.Item, error) {
			written = item
			item.Version++
			return item, nil
		}}})

	req := `{"method":"items.update","vaultId":"v","itemId":"i","content":{
		"title":"new","notes":"n","tags":["a","b"],
		"fields":[{"id":"f","title":"F","fieldType":"Concealed","value":"x"}],
		"sections":[{"id":"s","title":"S"}]}}`
	res := parse(t, call(handle, req))
	if res.Error != nil {
		t.Fatalf("unexpected error %+v", res.Error)
	}

	if written.Title != "new" || written.Notes != "n" || len(written.Tags) != 2 || written.Tags[1] != "b" {
		t.Fatalf("the five parts are not replaced: %+v", written)
	}
	if len(written.Fields) != 1 || written.Fields[0].ID != "f" || len(written.Sections) != 1 || written.Sections[0].ID != "s" {
		t.Fatalf("fields or sections not replaced: %+v", written)
	}
	if written.ID != "i" || written.VaultID != "v" || written.Category != onepassword.ItemCategoryLogin || written.Version != 7 {
		t.Fatalf("identity, category or version changed: %+v", written)
	}
	if len(written.Websites) != 1 || len(written.Files) != 1 || written.Document == nil || written.Document.Name != "doc" {
		t.Fatalf("websites, files or document lost: %+v", written)
	}
	var updated struct {
		Title   string `json:"title"`
		Version uint32 `json:"version"`
	}
	if err := json.Unmarshal(res.Result, &updated); err != nil {
		t.Fatal(err)
	}
	if updated.Title != "new" || updated.Version != 8 {
		t.Fatalf("the result is not the item Put returned: %s", res.Result)
	}
}

func TestUpdateFailsWhenPutFails(t *testing.T) {
	handle := register(t, &onepassword.Client{ItemsAPI: itemsStub{tb: t,
		get: func(string, string) (onepassword.Item, error) { return onepassword.Item{ID: "i"}, nil },
		put: func(onepassword.Item) (onepassword.Item, error) {
			return onepassword.Item{}, errors.New("incorrect item version")
		}}})
	out := call(handle, `{"method":"items.update","vaultId":"v","itemId":"i","content":{"title":"t"}}`)
	wantCode(t, out, codeRequestFailed)
	if !strings.Contains(out, "incorrect item version") {
		t.Fatalf("the SDK's message is lost: %s", out)
	}
}

func TestArchiveHasNoResult(t *testing.T) {
	var vault, item string
	handle := register(t, &onepassword.Client{ItemsAPI: itemsStub{tb: t,
		archive: func(vaultID, itemID string) error {
			vault, item = vaultID, itemID
			return nil
		}}})

	res := parse(t, call(handle, `{"method":"items.archive","vaultId":"v","itemId":"i"}`))
	if res.Error != nil || len(res.Result) != 0 || vault != "v" || item != "i" {
		t.Fatalf("unexpected response %+v %s, called with %q %q", res.Error, res.Result, vault, item)
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

func TestUpdateKeepsTheDetailsOfAFieldSentWithout(t *testing.T) {
	var address onepassword.ItemFieldDetails
	if err := json.Unmarshal([]byte(`{"type":"Address","content":{"street":"1 Main St","city":"Town","country":"us","zip":"1","state":"S"}}`), &address); err != nil {
		t.Fatal(err)
	}
	read := onepassword.Item{ID: "i", VaultID: "v", Title: "t", Category: onepassword.ItemCategoryIdentity,
		Fields: []onepassword.ItemField{{ID: "addr", Title: "address", FieldType: onepassword.ItemFieldTypeAddress, Details: &address}}}
	var written onepassword.Item
	handle := register(t, &onepassword.Client{ItemsAPI: itemsStub{tb: t,
		get: func(string, string) (onepassword.Item, error) { return read, nil },
		put: func(item onepassword.Item) (onepassword.Item, error) {
			written = item
			return item, nil
		}}})

	req := `{"method":"items.update","vaultId":"v","itemId":"i","content":{"title":"t",
		"fields":[{"id":"addr","title":"address","fieldType":"Address","value":""},{"id":"new","title":"n","fieldType":"Text","value":"x"}]}}`
	if res := parse(t, call(handle, req)); res.Error != nil {
		t.Fatalf("unexpected error %+v", res.Error)
	}
	if len(written.Fields) != 2 || written.Fields[0].Details == nil {
		t.Fatalf("the stored address details are lost: %+v", written.Fields)
	}
	kept, err := json.Marshal(written.Fields[0].Details)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(kept), "1 Main St") {
		t.Fatalf("the stored address details changed: %s", kept)
	}
	if written.Fields[1].Details != nil {
		t.Fatalf("a new field gained details: %+v", written.Fields[1])
	}
}
