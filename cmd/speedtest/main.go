package main

import (
	"context"
	"fmt"
	"os"
	"os/signal"
	"syscall"

	"github.com/tsosunchia/apple-cdn-network-bench/internal/config"
	"github.com/tsosunchia/apple-cdn-network-bench/internal/render"
	"github.com/tsosunchia/apple-cdn-network-bench/internal/runner"
)

func main() {
	cfg, err := config.Load()
	if err != nil {
		fmt.Fprintf(os.Stderr, "  [\u2717] %s\n", err)
		os.Exit(1)
	}

	var r render.Renderer
	isTTY := render.IsTTY()
	if isTTY {
		r = render.NewTTYRenderer()
	} else {
		r = render.NewPlainRenderer(os.Stderr)
	}

	bus := render.NewBus(r)
	defer bus.Close()

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	runner.Run(ctx, cfg, bus, isTTY)
}
