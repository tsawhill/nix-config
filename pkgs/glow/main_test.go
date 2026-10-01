package main

import (
	"bytes"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"
	"testing"
	"time"
	"unicode/utf8"
)

var ansi = regexp.MustCompile(`\x1b\[[0-9;?]*[a-zA-Z]`)

func TestCommandKeepsOperandsAfterDoubleDash(t *testing.T) {
	got := strings.Join(command([]string{"-a", "--", "-src/", "dst/"}), " ")
	want := "-a --no-human-readable --outbuf=N --info=progress1,name1 --out-format=" + marker + "|%i|%l|%n -- -src/ dst/"
	if got != want {
		t.Fatalf("got  %q\nwant %q", got, want)
	}
}

func TestPlainMode(t *testing.T) {
	cases := []struct {
		opts []string
		tty  bool
		term string
		want bool
	}{
		{[]string{"-a"}, true, "xterm", false},
		{[]string{"-an"}, true, "xterm", true},
		{[]string{"-aq"}, true, "xterm", true},
		{[]string{"-a", "--dry-run"}, true, "xterm", true},
		{[]string{"--info=name"}, true, "xterm", false},
		{[]string{"-a"}, false, "xterm", true},
		{[]string{"-a"}, true, "dumb", true},
	}
	for _, c := range cases {
		if got := plainMode(c.opts, c.tty, c.term); got != c.want {
			t.Errorf("plainMode(%q, %v, %q) = %v", c.opts, c.tty, c.term, got)
		}
	}
}

func TestFormatting(t *testing.T) {
	if got := size(0); got != "0.0 B" {
		t.Errorf("size(0) = %q", got)
	}
	if got := size(1536); got != "1.5 KiB" {
		t.Errorf("size(1536) = %q", got)
	}
	if got := commas(1234567); got != "1,234,567" {
		t.Errorf("commas = %q", got)
	}
	if got := safe("a\x1bb"); got != "a?b" {
		t.Errorf("safe = %q", got)
	}
}

func TestSplitCompleteHoldsPartialRune(t *testing.T) {
	text, rest := splitComplete([]byte("ok \xe2\x94"))
	if string(text) != "ok " || string(rest) != "\xe2\x94" {
		t.Fatalf("got %q / %q", text, rest)
	}
}

// Every bordered line must be exactly the terminal width, or the in-place redraw drifts.
func TestRenderFitsWidth(t *testing.T) {
	scenarios := map[string]func(d *dashboard){
		"empty": func(d *dashboard) {},
		"busy": func(d *dashboard) {
			d.consume(marker + "|>f+++++++++|5000000|" + strings.Repeat("very long name ", 20))
			d.consume("      5,000,000 100%   10.00MB/s    0:00:00 (xfr#1, ir-chk=1/3)")
			d.consume(marker + "|>f+++++++++|5000000|b")
			d.consume("      2,500,000  50%   10.00MB/s    0:00:01")
			d.consume(marker + "|cd+++++++++|0|some/dir/")
			d.consume("rsync: a warning that is quite long " + strings.Repeat("x", 300))
		},
	}
	for name, setup := range scenarios {
		for _, cols := range []int{40, 60, 97, 200} {
			for _, rows := range []int{10, 40} {
				d := newDashboard()
				setup(d)
				frame := d.render(cols, rows, time.Now().Add(2*time.Second))
				if len(frame) > rows-1 {
					t.Errorf("%s %dx%d: %d lines", name, cols, rows, len(frame))
				}
				w := cols
				if w < minWidth {
					w = minWidth
				}
				for i, l := range frame {
					visible := ansi.ReplaceAllString(l, "")
					n := utf8.RuneCountInString(visible)
					boxed := strings.HasPrefix(visible, "╭") || strings.HasPrefix(visible, "│") || strings.HasPrefix(visible, "╰")
					if (boxed && n != w) || n > w {
						t.Errorf("%s %dx%d line %d: width %d, want %d: %q", name, cols, rows, i, n, w, visible)
					}
				}
			}
		}
	}
	for _, l := range diagnosticsPanel("ssh: connect\n"+strings.Repeat("y", 150), 60, red) {
		if n := utf8.RuneCountInString(ansi.ReplaceAllString(l, "")); n != 60 {
			t.Errorf("diagnostics width %d: %q", n, l)
		}
	}
}

func TestRealRsync(t *testing.T) {
	if _, err := exec.LookPath("rsync"); err != nil {
		t.Skip("rsync not on PATH")
	}
	tmp := t.TempDir()
	src := filepath.Join(tmp, "src")
	if err := os.Mkdir(src, 0o755); err != nil {
		t.Fatal(err)
	}
	files := map[string]int{"big.iso": 2000000, "small [bold]|test": 123, "empty": 0, "new\nline": 42}
	for name, n := range files {
		if err := os.WriteFile(filepath.Join(src, name), bytes.Repeat([]byte("x"), n), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	dst := filepath.Join(tmp, "dst")
	cmd := exec.Command("rsync", command([]string{"-a", src + "/", dst})...)
	cmd.Env = append(os.Environ(), "LC_ALL=C")
	out, err := cmd.Output()
	if err != nil {
		t.Fatalf("rsync: %v", err)
	}
	d := newDashboard()
	for _, l := range regexp.MustCompile(`[\r\n]`).Split(string(out), -1) {
		d.consume(l)
	}
	if d.completed != 4 || d.bytes != 2000165 {
		t.Fatalf("completed=%d bytes=%d\n%s", d.completed, d.bytes, out)
	}
	for name := range files {
		a, _ := os.ReadFile(filepath.Join(src, name))
		b, err := os.ReadFile(filepath.Join(dst, name))
		if err != nil || !bytes.Equal(a, b) {
			t.Fatalf("%q differs after copy", name)
		}
	}
}
