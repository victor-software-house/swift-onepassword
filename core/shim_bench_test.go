package main

import (
	"os"
	"os/exec"
	"strconv"
	"strings"
	"sync"
	"testing"

	"github.com/1password/onepassword-sdk-go"
)

var warm sync.Once

// warmCore loads 1Password's core once, which the SDK keeps for the life of the process.
func warmCore() { warm.Do(func() { open("malformed-token", "bench", "0") }) }

// BenchmarkOpenCold times the first open of a fresh process, which loads the WebAssembly core. Each
// iteration runs the test binary again, so the time is the cold start and not a cached core.
func BenchmarkOpenCold(b *testing.B) {
	exe, err := os.Executable()
	if err != nil {
		b.Fatal(err)
	}
	var total int64
	for range b.N {
		cmd := exec.Command(exe)
		cmd.Env = append(os.Environ(), coldChildEnv+"=1")
		out, err := cmd.Output()
		if err != nil {
			b.Fatal(err)
		}
		ns, err := strconv.ParseInt(strings.TrimSpace(string(out)), 10, 64)
		if err != nil {
			b.Fatalf("child printed %q", out)
		}
		total += ns
	}
	b.ReportMetric(float64(total)/float64(b.N)/1e6, "cold-ms/open")
}

// BenchmarkOpenMalformedToken times an open that fails, once the core is loaded.
func BenchmarkOpenMalformedToken(b *testing.B) {
	warmCore()
	b.ReportAllocs()
	for b.Loop() {
		open("malformed-token", "bench", "0")
	}
}

func BenchmarkCallUnknownHandle(b *testing.B) {
	b.ReportAllocs()
	for b.Loop() {
		call(1<<40, `{"method":"vaults.list"}`)
	}
}

func BenchmarkCallBadRequest(b *testing.B) {
	handle := register(b, &onepassword.Client{})
	b.ReportAllocs()
	for b.Loop() {
		call(handle, `{"method":"items.get","vaultId":"v"}`)
	}
}

func BenchmarkCallUnknownMethod(b *testing.B) {
	handle := register(b, &onepassword.Client{})
	b.ReportAllocs()
	for b.Loop() {
		call(handle, `{"method":"vaults.delete"}`)
	}
}
