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
	Method  string `json:"method"`
	VaultID string `json:"vaultId"`
	ItemID  string `json:"itemId"`
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
