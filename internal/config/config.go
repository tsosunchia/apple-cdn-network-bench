package config

import (
	"fmt"
	"os"
	"regexp"
	"strconv"
	"strings"
)

const (
	DefaultDLURL        = "https://mensura.cdn-apple.com/api/v1/gm/large"
	DefaultULURL        = "https://mensura.cdn-apple.com/api/v1/gm/slurp"
	DefaultLatencyURL   = "https://mensura.cdn-apple.com/api/v1/gm/small"
	DefaultMax          = "2G"
	DefaultTimeout      = 10
	DefaultThreads      = 4
	DefaultLatencyCount = 20
	UserAgent           = "networkQuality/194.80.3 CFNetwork/3860.400.51 Darwin/25.3.0"
)

type Config struct {
	DLURL        string
	ULURL        string
	LatencyURL   string
	Max          string
	MaxBytes     int64
	Timeout      int
	Threads      int
	LatencyCount int
}

func Load() (*Config, error) {
	c := &Config{
		DLURL:        envOr("DL_URL", DefaultDLURL),
		ULURL:        envOr("UL_URL", DefaultULURL),
		LatencyURL:   envOr("LATENCY_URL", DefaultLatencyURL),
		Max:          envOr("MAX", DefaultMax),
		Timeout:      envInt("TIMEOUT", DefaultTimeout),
		Threads:      envInt("THREADS", DefaultThreads),
		LatencyCount: envInt("LATENCY_COUNT", DefaultLatencyCount),
	}
	var err error
	c.MaxBytes, err = ParseSize(c.Max)
	if err != nil {
		return nil, fmt.Errorf("invalid MAX %q: %w", c.Max, err)
	}
	if c.MaxBytes <= 0 {
		return nil, fmt.Errorf("MAX must be > 0")
	}
	if c.Timeout <= 0 {
		return nil, fmt.Errorf("TIMEOUT must be > 0")
	}
	if c.Threads <= 0 {
		return nil, fmt.Errorf("THREADS must be > 0")
	}
	if c.LatencyCount <= 0 {
		return nil, fmt.Errorf("LATENCY_COUNT must be > 0")
	}
	if c.Timeout > 120 {
		return nil, fmt.Errorf("TIMEOUT must be <= 120")
	}
	if c.Threads > 64 {
		return nil, fmt.Errorf("THREADS must be <= 64")
	}
	if c.LatencyCount > 100 {
		return nil, fmt.Errorf("LATENCY_COUNT must be <= 100")
	}
	for _, u := range []struct{ name, val string }{
		{"DL_URL", c.DLURL},
		{"UL_URL", c.ULURL},
		{"LATENCY_URL", c.LatencyURL},
	} {
		if !strings.HasPrefix(u.val, "http://") && !strings.HasPrefix(u.val, "https://") {
			return nil, fmt.Errorf("%s must start with http(s)://", u.name)
		}
	}
	return c, nil
}

func (c *Config) Summary() string {
	return fmt.Sprintf("timeout=%ds  max=%s  threads=%d  latency_count=%d",
		c.Timeout, c.Max, c.Threads, c.LatencyCount)
}

var sizeRe = regexp.MustCompile(`(?i)^\s*([\d.]+)\s*([a-z]*)\s*$`)

func ParseSize(s string) (int64, error) {
	m := sizeRe.FindStringSubmatch(s)
	if m == nil {
		return 0, fmt.Errorf("cannot parse size %q", s)
	}
	num, err := strconv.ParseFloat(m[1], 64)
	if err != nil {
		return 0, err
	}
	unit := m[2]
	if unit == "" {
		return int64(num), nil
	}
	mul := int64(1)
	switch strings.ToLower(unit) {
	case "k", "kb":
		mul = 1000
	case "m", "mb":
		mul = 1000 * 1000
	case "g", "gb":
		mul = 1000 * 1000 * 1000
	case "t", "tb":
		mul = 1000 * 1000 * 1000 * 1000
	case "kib":
		mul = 1024
	case "mib":
		mul = 1024 * 1024
	case "gib":
		mul = 1024 * 1024 * 1024
	case "tib":
		mul = 1024 * 1024 * 1024 * 1024
	default:
		return 0, fmt.Errorf("unknown unit %q", unit)
	}
	return int64(num * float64(mul)), nil
}

func HumanBytes(b int64) string {
	switch {
	case b >= 1<<30:
		return fmt.Sprintf("%.2f GiB", float64(b)/float64(1<<30))
	case b >= 1<<20:
		return fmt.Sprintf("%.1f MiB", float64(b)/float64(1<<20))
	case b >= 1<<10:
		return fmt.Sprintf("%.0f KiB", float64(b)/float64(1<<10))
	default:
		return fmt.Sprintf("%d B", b)
	}
}

func envOr(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

func envInt(key string, fallback int) int {
	v := os.Getenv(key)
	if v == "" {
		return fallback
	}
	n, err := strconv.Atoi(v)
	if err != nil {
		return fallback
	}
	return n
}
