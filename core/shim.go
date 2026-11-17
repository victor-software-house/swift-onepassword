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

// Error kinds of the JSON error object.
const (
	kindAuthentication = "authentication"
	kindRateLimited    = "rateLimited"
	kindUnknownHandle  = "unknownHandle"
	kindBadRequest     = "badRequest"
	kindOther          = "other"
)

var (
	mu      sync.Mutex
	clients = map[uint64]*onepassword.Client{}
	next    uint64
)

type failure struct {
	Kind    string `json:"kind"`
	Message string `json:"message"`
}

type reply struct {
	Handle *uint64         `json:"handle,omitempty"`
	Result json.RawMessage `json:"result,omitempty"`
	Error  *failure        `json:"error,omitempty"`
}

type request struct {
	Method  string `json:"method"`
	VaultID string `json:"vaultId"`
	ItemID  string `json:"itemId"`
}

func encode(r reply) string {
	data, err := json.Marshal(r)
	if err != nil {
		return `{"error":{"kind":"other","message":"reply could not be encoded"}}`
	}
	return string(data)
}

func fail(kind, message string) string {
	return encode(reply{Error: &failure{Kind: kind, Message: message}})
}

// safely turns a panic into an error reply, because a panic that crosses the C boundary ends the process.
func safely(work func() string) (out string) {
	defer func() {
		if r := recover(); r != nil {
			out = fail(kindOther, "the SDK panicked")
		}
	}()
	return work()
}

// refusedTokenMessages are the parts of the SDK core's messages that mean the token is refused,
// unusable or not authenticated.
//
// onepassword-sdk-go v0.4.1 has two typed errors, DesktopSessionExpiredError and
// RateLimitExceededError (errors.go:10-24). unmarshalError (errors.go:26-46) reads the JSON that
// the core returns, {"name": ..., "message": ...} (integration_tests/integration_test.go:102 and
// 127), and for every other name returns errors.New(message). NewClient wraps what it gets in
// "error initializing client: %w" (client_builder.go:52). The message is therefore all that tells
// a refused token from a network failure, so a message is matched as a substring. The core's
// messages are string constants in internal/wasm/core.wasm:
//
//   - Every message about the token holds "service account token": "service account token had
//     invalid format, please create another token: ", "service account token base64 decoding
//     failed, please create another token", "service account token is invalid: ", "service
//     account token was not specified", "service account token's throttle token is invalid.
//     please create a new service account token: ", "invalid service account token, please make
//     sure you provide a valid service account token as parameter: ", and "bad service account
//     token, please rotate it: ", which 1Password's refusal of a token gives.
//   - "you are not authenticated", the answer to an unauthorized request, such as one with a token
//     revoked after the client opened.
//
// The core's "authentication error: " prefix is not matched, because it can hold a network
// failure, and "you don't have the right permissions to access this resource" is not matched,
// because the token is accepted there and only the vault is out of its reach.
var refusedTokenMessages = [...]string{
	"service account token",
	"you are not authenticated",
}

// kindOf maps an SDK error to the kind of the JSON error object.
func kindOf(err error) string {
	var limited *onepassword.RateLimitExceededError
	if errors.As(err, &limited) {
		return kindRateLimited
	}
	message := err.Error()
	for _, refused := range refusedTokenMessages {
		if strings.Contains(message, refused) {
			return kindAuthentication
		}
	}
	return kindOther
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
			return fail(kindOf(err), err.Error())
		}

		mu.Lock()
		next++
		handle := next
		clients[handle] = client
		mu.Unlock()
		return encode(reply{Handle: &handle})
	})
}

// call is the Go side of op_call.
func call(handle uint64, req string) string {
	return safely(func() string {
		mu.Lock()
		client, ok := clients[handle]
		mu.Unlock()
		if !ok {
			return fail(kindUnknownHandle, "no client has this handle")
		}

		var r request
		if err := json.Unmarshal([]byte(req), &r); err != nil {
			return fail(kindBadRequest, "the request is not valid JSON")
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
				return fail(kindBadRequest, "items.list needs vaultId")
			}
			value, err = client.Items().List(ctx, r.VaultID)
		case "items.get":
			if r.VaultID == "" || r.ItemID == "" {
				return fail(kindBadRequest, "items.get needs vaultId and itemId")
			}
			value, err = client.Items().Get(ctx, r.VaultID, r.ItemID)
		default:
			return fail(kindBadRequest, "unknown method")
		}
		if err != nil {
			return fail(kindOf(err), err.Error())
		}

		result, err := json.Marshal(value)
		if err != nil {
			return fail(kindOther, "the result could not be encoded")
		}
		return encode(reply{Result: result})
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
