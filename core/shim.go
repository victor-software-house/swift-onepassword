// Command core exports a small C interface over 1Password's Go SDK. It is built with
// -buildmode=c-archive, so the package's main function is never run.
package main

/*
#include <stdint.h>
#include <stdlib.h>
*/
import "C"

import (
	"context"
	"encoding/json"
	"errors"
	"strings"
	"sync"
	"time"
	"unsafe"

	"github.com/1password/onepassword-sdk-go"
)

// callTimeout bounds each call into the SDK.
const callTimeout = 60 * time.Second

// Error codes of a response.
const (
	codeAuthenticationFailed = "authenticationFailed"
	codeRateLimited          = "rateLimited"
	codeUnknownClient        = "unknownClient"
	codeInvalidRequest       = "invalidRequest"
	codeRequestFailed        = "requestFailed"
)

var (
	mu      sync.Mutex
	clients = map[uint64]*onepassword.Client{}
	next    uint64
)

type responseError struct {
	Code    string `json:"code"`
	Message string `json:"message"`
}

type response struct {
	Handle *uint64         `json:"handle,omitempty"`
	Result json.RawMessage `json:"result,omitempty"`
	Error  *responseError  `json:"error,omitempty"`
}

type request struct {
	Method  string          `json:"method"`
	VaultID string          `json:"vaultId"`
	ItemID  string          `json:"itemId"`
	Items   json.RawMessage `json:"items"`
	ItemIDs []string        `json:"itemIds"`
	Content *content        `json:"content"`
}

// content is the part of an item that items.update sets.
type content struct {
	Title    string                    `json:"title"`
	Fields   []onepassword.ItemField   `json:"fields"`
	Sections []onepassword.ItemSection `json:"sections"`
	Notes    string                    `json:"notes"`
	Tags     []string                  `json:"tags"`
}

// entry is the result of one item of a batch: the item, or the SDK's type of its failure.
// The SDK's error message is unexported, so a marshalled SDK response would lose it.
type entry struct {
	Item    *onepassword.Item `json:"item,omitempty"`
	Failure string            `json:"failure,omitempty"`
}

// entries turns the individual responses of a batch into entries, in the order the SDK returned them.
// The caller keeps the order of its input, so a count that differs is an error.
func entries[E any](
	responses []onepassword.Response[onepassword.Item, E], want int, failure func(E) string,
) ([]entry, error) {
	if len(responses) != want {
		return nil, errors.New("the SDK answered a different number of items than the request had")
	}
	out := make([]entry, len(responses))
	for i, r := range responses {
		switch {
		case r.Content != nil:
			out[i] = entry{Item: r.Content}
		case r.Error != nil:
			out[i] = entry{Failure: failure(*r.Error)}
		default:
			return nil, errors.New("the SDK answered an item with neither content nor error")
		}
	}
	return out, nil
}

func createAll(
	ctx context.Context, items onepassword.ItemsAPI, vaultID string, params []onepassword.ItemCreateParams,
) (any, error) {
	res, err := items.CreateAll(ctx, vaultID, params)
	if err != nil {
		return nil, err
	}
	return entries(res.IndividualResponses, len(params), func(e onepassword.ItemUpdateFailureReason) string {
		return string(e.Type)
	})
}

func getAll(ctx context.Context, items onepassword.ItemsAPI, vaultID string, ids []string) (any, error) {
	res, err := items.GetAll(ctx, vaultID, ids)
	if err != nil {
		return nil, err
	}
	return entries(res.IndividualResponses, len(ids), func(e onepassword.ItemsGetAllError) string {
		return string(e.Type)
	})
}

// update reads the item and writes it back with the five parts of c replaced, so the parts the core
// does not model, such as websites and files, stay as they were.
func update(
	ctx context.Context, items onepassword.ItemsAPI, vaultID, itemID string, c content,
) (onepassword.Item, error) {
	item, err := items.Get(ctx, vaultID, itemID)
	if err != nil {
		return onepassword.Item{}, err
	}
	item.Title = c.Title
	item.Fields = c.Fields
	item.Sections = c.Sections
	item.Notes = c.Notes
	item.Tags = c.Tags
	return items.Put(ctx, item)
}

// deleteAll returns the type of the failure of each item that could not be deleted.
func deleteAll(ctx context.Context, items onepassword.ItemsAPI, vaultID string, ids []string) (any, error) {
	res, err := items.DeleteAll(ctx, vaultID, ids)
	if err != nil {
		return nil, err
	}
	failed := map[string]string{}
	for id, r := range res.IndividualResponses {
		if r.Error != nil {
			failed[id] = string(r.Error.Type)
		}
	}
	return failed, nil
}

func encode(res response) string {
	data, err := json.Marshal(res)
	if err != nil {
		return `{"error":{"code":"requestFailed","message":"the response could not be encoded"}}`
	}
	return string(data)
}

func fail(code, message string) string {
	return encode(response{Error: &responseError{Code: code, Message: message}})
}

// safely turns a panic into an error response.
// A panic that crosses the C boundary ends the process.
func safely(work func() string) (out string) {
	defer func() {
		if r := recover(); r != nil {
			out = fail(codeRequestFailed, "the SDK panicked")
		}
	}()
	return work()
}

// refusedTokenMessages are the parts of an SDK message that show 1Password refused the token.
//
// onepassword-sdk-go v0.4.1 has two typed errors, DesktopSessionExpiredError and
// RateLimitExceededError.
//
// For any other error name in the core's JSON, it returns a plain error with the core's message.
// NewClient wraps that error in "error initializing client".
// The message text is the only sign that tells a refused token from a network error.
// So the match is a substring.
//
// The core's messages are string constants in internal/wasm/core.wasm:
//
//   - Each message about the token has "service account token" in it.
//     They cover a bad format, a failed base64 decoding, an invalid token, a missing token,
//     an invalid throttle token, and a token to rotate.
//   - "you are not authenticated" is the answer to an unauthorized request,
//     such as one with a token revoked after the client opened.
//
// The core's "authentication error: " prefix is not matched, because a network error can carry it.
// "you don't have the right permissions to access this resource" is not matched either.
// The token is accepted there, and only the vault is out of its reach.
var refusedTokenMessages = [...]string{
	"service account token",
	"you are not authenticated",
}

// codeOf maps an SDK error to the code of a response error.
func codeOf(err error) string {
	var limited *onepassword.RateLimitExceededError
	if errors.As(err, &limited) {
		return codeRateLimited
	}
	message := err.Error()
	for _, refused := range refusedTokenMessages {
		if strings.Contains(message, refused) {
			return codeAuthenticationFailed
		}
	}
	return codeRequestFailed
}

// open is the Go side of op_client_open.
func open(token, name, version string) string {
	return safely(func() string {
		ctx, cancel := context.WithTimeout(context.Background(), callTimeout)
		defer cancel()

		client, err := onepassword.NewClient(ctx,
			onepassword.WithServiceAccountToken(token),
			onepassword.WithIntegrationInfo(name, version),
		)
		if err != nil {
			return fail(codeOf(err), err.Error())
		}

		mu.Lock()
		next++
		handle := next
		clients[handle] = client
		mu.Unlock()
		return encode(response{Handle: &handle})
	})
}

// call is the Go side of op_call.
func call(handle uint64, req string) string {
	return safely(func() string {
		mu.Lock()
		client, ok := clients[handle]
		mu.Unlock()
		if !ok {
			return fail(codeUnknownClient, "no client has this handle")
		}

		var r request
		if err := json.Unmarshal([]byte(req), &r); err != nil {
			return fail(codeInvalidRequest, "the request is not valid JSON")
		}

		ctx, cancel := context.WithTimeout(context.Background(), callTimeout)
		defer cancel()

		var (
			value any
			err   error
		)
		switch r.Method {
		case "vaults.list":
			value, err = client.Vaults().List(ctx)
		case "items.list":
			if r.VaultID == "" {
				return fail(codeInvalidRequest, "items.list needs vaultId")
			}
			value, err = client.Items().List(ctx, r.VaultID)
		case "items.get":
			if r.VaultID == "" || r.ItemID == "" {
				return fail(codeInvalidRequest, "items.get needs vaultId and itemId")
			}
			value, err = client.Items().Get(ctx, r.VaultID, r.ItemID)
		case "items.createAll":
			var params []onepassword.ItemCreateParams
			if r.VaultID == "" || json.Unmarshal(r.Items, &params) != nil || len(params) == 0 {
				return fail(codeInvalidRequest, "items.createAll needs vaultId and items")
			}
			for i := range params {
				params[i].VaultID = r.VaultID
			}
			value, err = createAll(ctx, client.Items(), r.VaultID, params)
		case "items.getAll":
			if r.VaultID == "" || len(r.ItemIDs) == 0 {
				return fail(codeInvalidRequest, "items.getAll needs vaultId and itemIds")
			}
			value, err = getAll(ctx, client.Items(), r.VaultID, r.ItemIDs)
		case "items.update":
			if r.VaultID == "" || r.ItemID == "" || r.Content == nil || r.Content.Title == "" {
				return fail(codeInvalidRequest, "items.update needs vaultId, itemId and content with a title")
			}
			value, err = update(ctx, client.Items(), r.VaultID, r.ItemID, *r.Content)
		case "items.deleteAll":
			if r.VaultID == "" || len(r.ItemIDs) == 0 {
				return fail(codeInvalidRequest, "items.deleteAll needs vaultId and itemIds")
			}
			value, err = deleteAll(ctx, client.Items(), r.VaultID, r.ItemIDs)
		case "items.archive":
			if r.VaultID == "" || r.ItemID == "" {
				return fail(codeInvalidRequest, "items.archive needs vaultId and itemId")
			}
			if err := client.Items().Archive(ctx, r.VaultID, r.ItemID); err != nil {
				return fail(codeOf(err), err.Error())
			}
			return encode(response{})
		default:
			return fail(codeInvalidRequest, "unknown method")
		}
		if err != nil {
			return fail(codeOf(err), err.Error())
		}

		result, err := json.Marshal(value)
		if err != nil {
			return fail(codeRequestFailed, "the result could not be encoded")
		}
		return encode(response{Result: result})
	})
}

func closeClient(handle uint64) {
	mu.Lock()
	delete(clients, handle)
	mu.Unlock()
}

//export op_client_open
func op_client_open(token, name, version *C.char) *C.char {
	return C.CString(open(C.GoString(token), C.GoString(name), C.GoString(version)))
}

//export op_call
func op_call(handle C.uint64_t, req *C.char) *C.char {
	return C.CString(call(uint64(handle), C.GoString(req)))
}

//export op_client_close
func op_client_close(handle C.uint64_t) {
	closeClient(uint64(handle))
}

//export op_free
func op_free(p *C.char) {
	C.free(unsafe.Pointer(p))
}

func main() {}
