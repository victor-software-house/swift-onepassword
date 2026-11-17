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

// encode returns the reply as a C string that the caller releases with op_free.
func encode(r reply) *C.char {
	data, err := json.Marshal(r)
	if err != nil {
		data = []byte(`{"error":{"kind":"other","message":"reply could not be encoded"}}`)
	}
	return C.CString(string(data))
}

func fail(kind, message string) *C.char {
	return encode(reply{Error: &failure{Kind: kind, Message: message}})
}

// recovered turns a panic into an error reply, because a panic that crosses the C boundary ends the process.
func recovered(out **C.char) {
	if r := recover(); r != nil {
		*out = fail(kindOther, "the SDK panicked")
	}
}

//export op_client_open
func op_client_open(token, name, version *C.char) (out *C.char) {
	defer recovered(&out)

	ctx, cancel := context.WithTimeout(context.Background(), callTimeout)
	defer cancel()

	client, err := onepassword.NewClient(ctx,
		onepassword.WithServiceAccountToken(C.GoString(token)),
		onepassword.WithIntegrationInfo(C.GoString(name), C.GoString(version)),
	)
	if err != nil {
		return fail(kindAuthentication, err.Error())
	}

	mu.Lock()
	next++
	handle := next
	clients[handle] = client
	mu.Unlock()
	return encode(reply{Handle: &handle})
}

//export op_call
func op_call(handle C.uint64_t, req *C.char) (out *C.char) {
	defer recovered(&out)

	mu.Lock()
	client, ok := clients[uint64(handle)]
	mu.Unlock()
	if !ok {
		return fail(kindUnknownHandle, "no client has this handle")
	}

	var r request
	if err := json.Unmarshal([]byte(C.GoString(req)), &r); err != nil {
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
		var limited *onepassword.RateLimitExceededError
		if errors.As(err, &limited) {
			return fail(kindRateLimited, err.Error())
		}
		return fail(kindOther, err.Error())
	}

	result, err := json.Marshal(value)
	if err != nil {
		return fail(kindOther, "the result could not be encoded")
	}
	return encode(reply{Result: result})
}

//export op_client_close
func op_client_close(handle C.uint64_t) {
	mu.Lock()
	delete(clients, uint64(handle))
	mu.Unlock()
}

//export op_free
func op_free(p *C.char) {
	C.free(unsafe.Pointer(p))
}

func main() {}
