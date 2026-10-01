// glow is a bounded-memory terminal dashboard for one ordinary rsync process.
package main

import (
	"bytes"
	"fmt"
	"os"
	"os/exec"
	"os/signal"
	"regexp"
	"strconv"
	"strings"
	"syscall"
	"time"
	"unicode"
	"unicode/utf8"
	"unsafe"
)

const (
	marker   = "@@RSYNC_GLOW@@"
	minWidth = 60

	hideCursor = "\x1b[?25l"
	showCursor = "\x1b[?25h"

	brightCyan        = "96"
	brightMagenta     = "95"
	boldBrightCyan    = "1;96"
	boldBrightMagenta = "1;95"
	boldWhite         = "1;37"
	bold              = "1"
	cyan              = "36"
	magenta           = "35"
	white             = "37"
	dim               = "2"
	yellow            = "33"
	red               = "31"
	barBack           = "38;5;237"
)

const helpText = `glow — neon rsync dashboard

Usage: glow [rsync options] SOURCE... DEST
Example: glow -a --partial /source/ user@host:/destination/

Uses ordinary rsync semantics; no archive, deletion, or resume flags are added.
File bars show logical bytes processed, not network bytes.
Overall bar counts file-list entries checked; totals may grow during scanning.
Dry runs, redirected output, and quiet mode use plain rsync output.
Dashboard owns --info, --out-format, --outbuf and human-readable formatting.
`

var (
	progressRe = regexp.MustCompile(`^\s*([\d,]+)\s+(\d+)%\s+(\S+)\s+(\S+)(.*)$`)
	checkedRe  = regexp.MustCompile(`(ir|to)-chk=(\d+)/(\d+)`)
)

func st(style, s string) string {
	if style == "" || s == "" {
		return s
	}
	return "\x1b[" + style + "m" + s + "\x1b[0m"
}

func width(s string) int { return utf8.RuneCountInString(s) }

func truncate(s string, w int) string {
	if w <= 0 {
		return ""
	}
	if width(s) <= w {
		return s
	}
	r := []rune(s)
	return string(r[:w-1]) + "…"
}

func safe(s string) string {
	var b strings.Builder
	for _, r := range s {
		if unicode.IsPrint(r) {
			b.WriteRune(r)
		} else {
			b.WriteByte('?')
		}
	}
	return b.String()
}

// sanitize is safe() but keeps newlines and tabs, for diagnostics.
func sanitize(s string) string {
	var b strings.Builder
	for _, r := range s {
		if r == '\n' || r == '\t' || unicode.IsPrint(r) {
			b.WriteRune(r)
		} else {
			b.WriteByte('?')
		}
	}
	return b.String()
}

func size(v float64) string {
	units := []string{"B", "KiB", "MiB", "GiB", "TiB"}
	for i, u := range units {
		if v < 1024 || i == len(units)-1 {
			return fmt.Sprintf("%.1f %s", v, u)
		}
		v /= 1024
	}
	return ""
}

func commas(n int64) string {
	s := strconv.FormatInt(n, 10)
	sign := ""
	if strings.HasPrefix(s, "-") {
		sign, s = "-", s[1:]
	}
	var b strings.Builder
	for i, c := range s {
		if i > 0 && (len(s)-i)%3 == 0 {
			b.WriteByte(',')
		}
		b.WriteRune(c)
	}
	return sign + b.String()
}

func isDigits(s string) bool {
	if s == "" {
		return false
	}
	for _, c := range s {
		if c < '0' || c > '9' {
			return false
		}
	}
	return true
}

func indexOf(args []string, want string) int {
	for i, a := range args {
		if a == want {
			return i
		}
	}
	return -1
}

func pushLimited[T any](s []T, v T, limit int) []T {
	s = append(s, v)
	if len(s) > limit {
		s = s[len(s)-limit:]
	}
	return s
}

type file struct {
	name     string
	total    int64
	done     int64
	complete bool
}

type dashboard struct {
	files      []*file
	events     []string
	current    *file
	completed  int
	bytes      int64
	speed      string
	eta        string
	checked    int64
	total      int64
	scanning   bool
	started    time.Time
	samples    []float64
	lastBytes  int64
	lastSample time.Time
	status     string
}

func newDashboard() *dashboard {
	now := time.Now()
	return &dashboard{
		speed:      "—",
		eta:        "—",
		scanning:   true,
		started:    now,
		lastSample: now,
		status:     "CONNECTING / SCANNING",
	}
}

func (d *dashboard) consume(line string) {
	if strings.HasPrefix(line, marker+"|") {
		fields := strings.SplitN(line, "|", 4)
		if len(fields) != 4 {
			return
		}
		item, length, name := fields[1], strings.TrimSpace(fields[2]), fields[3]
		if len(item) >= 2 && (item[0] == '<' || item[0] == '>') && item[1] == 'f' && isDigits(length) {
			n, _ := strconv.ParseInt(length, 10, 64)
			d.current = &file{name: safe(name), total: n}
			d.files = pushLimited(d.files, d.current, 64)
			d.status = "TRANSFERRING"
		} else {
			d.events = pushLimited(d.events, safe(item+"  "+name), 4)
		}
		return
	}
	if m := progressRe.FindStringSubmatch(line); m != nil && d.current != nil {
		amount, _ := strconv.ParseInt(strings.ReplaceAll(m[1], ",", ""), 10, 64)
		d.speed, d.eta = m[3], m[4]
		tail := m[5]
		if delta := amount - d.current.done; delta > 0 {
			d.bytes += delta
		}
		d.current.done = amount
		if c := checkedRe.FindStringSubmatch(tail); c != nil {
			remaining, _ := strconv.ParseInt(c[2], 10, 64)
			total, _ := strconv.ParseInt(c[3], 10, 64)
			d.total = total
			d.checked = total - remaining
			d.scanning = c[1] == "ir"
		}
		if strings.Contains(tail, "xfr#") && !d.current.complete {
			d.current.complete = true
			d.completed++
			d.eta = "—"
		}
		return
	}
	if t := strings.TrimSpace(line); t != "" {
		d.events = pushLimited(d.events, safe(t), 4)
	}
}

// line is pre-styled text plus its visible width.
type line struct {
	s string
	w int
}

type seg struct {
	text  string
	style string
}

func fit(w int, segs ...seg) line {
	var b strings.Builder
	used := 0
	for _, sg := range segs {
		if used >= w {
			break
		}
		t := truncate(sg.text, w-used)
		b.WriteString(st(sg.style, t))
		used += width(t)
	}
	return line{b.String(), used}
}

func bar(done, total int64, w int, color, finished string) line {
	if w <= 0 {
		return line{}
	}
	if total < 1 {
		total = 1
	}
	if done > total {
		done = total
	}
	if done < 0 {
		done = 0
	}
	if done == total {
		color = finished
	}
	filled := int(done * int64(w) / total)
	return line{st(color, strings.Repeat("━", filled)) + st(barBack, strings.Repeat("━", w-filled)), w}
}

// pulse sweeps a segment across the bar while rsync has no total yet.
func pulse(w int, elapsed time.Duration) line {
	const span = 10
	pos := int(elapsed/(80*time.Millisecond)) % (w + span)
	var b strings.Builder
	for i := 0; i < w; i++ {
		if i >= pos-span && i < pos {
			b.WriteString(st(brightMagenta, "━"))
		} else {
			b.WriteString(st(barBack, "━"))
		}
	}
	return line{b.String(), w}
}

func panel(lines []line, w int, border, title, titleStyle string) []string {
	inner := w - 4
	out := make([]string, 0, len(lines)+2)
	if title == "" {
		out = append(out, st(border, "╭"+strings.Repeat("─", w-2)+"╮"))
	} else {
		t := truncate(" "+title+" ", w-2)
		left := (w - 2 - width(t)) / 2
		right := w - 2 - width(t) - left
		out = append(out, st(border, "╭"+strings.Repeat("─", left))+st(titleStyle, t)+st(border, strings.Repeat("─", right)+"╮"))
	}
	for _, l := range lines {
		pad := inner - l.w
		if pad < 0 {
			pad = 0
		}
		out = append(out, st(border, "│")+" "+l.s+strings.Repeat(" ", pad)+" "+st(border, "│"))
	}
	return append(out, st(border, "╰"+strings.Repeat("─", w-2)+"╯"))
}

func cell(text string, w int, style string, right bool) string {
	t := truncate(text, w)
	pad := strings.Repeat(" ", w-width(t))
	if right {
		return " " + pad + st(style, t) + " "
	}
	return " " + st(style, t) + pad + " "
}

func (d *dashboard) render(cols, rows int, now time.Time) []string {
	if since := now.Sub(d.lastSample); since >= 500*time.Millisecond {
		rate := float64(d.bytes-d.lastBytes) / since.Seconds()
		if rate < 0 {
			rate = 0
		}
		d.samples = pushLimited(d.samples, rate, 36)
		d.lastBytes, d.lastSample = d.bytes, now
	}
	peak := 0.0
	for _, s := range d.samples {
		if s > peak {
			peak = s
		}
	}
	if peak == 0 {
		peak = 1
	}
	levels := []rune("▁▂▃▄▅▆▇█")
	var trace strings.Builder
	for _, s := range d.samples {
		i := int(s / peak * 7)
		if i > 7 {
			i = 7
		}
		trace.WriteRune(levels[i])
	}
	elapsed := int(now.Sub(d.started).Seconds())

	w := cols
	if w < minWidth {
		w = minWidth
	}
	inner := w - 4

	label := []seg{{fmt.Sprintf("FILE LIST CHECKED   %s / %s", commas(d.checked), commas(d.total)), dim}}
	if d.scanning {
		label = append(label, seg{"   discovering files…", brightMagenta})
	}
	overall := pulse(inner, now.Sub(d.started))
	if d.total > 0 {
		overall = bar(d.checked, d.total, inner, cyan, brightCyan)
	}
	overview := []line{
		fit(inner, seg{"◈  GLOW", boldBrightCyan}, seg{"   /   " + d.status, boldBrightMagenta}),
		{},
		fit(inner, seg{fmt.Sprintf("%s processed   •   %d files   •   %02d:%02d elapsed",
			size(float64(d.bytes)), d.completed, elapsed/60, elapsed%60), white}),
		fit(inner, seg{d.speed + "   " + trace.String(), brightCyan}, seg{"   file ETA " + d.eta, brightMagenta}),
		{},
		fit(inner, label...),
		overall,
	}

	const markW, pctW, sizeW = 1, 4, 23
	flex := inner - (markW + pctW + sizeW + 5*2)
	fileW := flex * 3 / 5
	progW := flex - fileW

	deck := []line{{
		cell("", markW, "", false) + cell("FILE", fileW, bold, false) + cell("PROGRESS", progW, bold, false) +
			cell("%", pctW, bold, true) + cell("SIZE", sizeW, bold, true),
		inner,
	}}
	count := rows - 19
	if count > 8 {
		count = 8
	}
	if count < 1 {
		count = 1
	}
	start := len(d.files) - count
	if start < 0 {
		start = 0
	}
	for _, f := range d.files[start:] {
		color, mark, nameStyle := brightMagenta, "›", boldWhite
		total := f.total
		if total < 1 {
			total = 1
		}
		done := f.done
		if f.complete {
			color, mark, nameStyle, done = brightCyan, "✓", dim, total
		}
		pct := done * 100 / total
		if pct > 100 {
			pct = 100
		}
		pctText := fmt.Sprintf("%d%%", pct)
		if f.complete {
			pctText = "100%"
		}
		row := cell(mark, markW, color, false) + cell(f.name, fileW, nameStyle, false) +
			" " + bar(done, total, progW, color, color).s + " " + cell(pctText, pctW, color, true) +
			cell(size(float64(f.done))+" / "+size(float64(f.total)), sizeW, color, true)
		deck = append(deck, line{row, inner})
	}
	if len(d.files) == 0 {
		row := cell("", markW, "", false) + cell("Waiting for files…", fileW, dim, false) +
			cell("", progW, "", false) + cell("", pctW, "", true) + cell("", sizeW, "", true)
		deck = append(deck, line{row, inner})
	}

	out := panel(overview, w, brightCyan, "", "")
	out = append(out, panel(deck, w, magenta, "TRANSFER DECK", boldBrightMagenta)...)
	for _, e := range d.events {
		out = append(out, st(dim, truncate(e, w)))
	}
	out = append(out, st(dim, truncate("  rsync engine  •  Ctrl+C cancel  •  tmux detach keeps running", w)))
	// Taller than the terminal and the cursor-up redraw would smear.
	if rows > 1 && len(out) > rows-1 {
		out = out[:rows-1]
	}
	return out
}

func diagnosticsPanel(text string, cols int, border string) []string {
	w := cols
	if w < minWidth {
		w = minWidth
	}
	inner := w - 4
	var lines []line
	for _, raw := range strings.Split(strings.TrimRight(sanitize(text), " \t\n"), "\n") {
		r := []rune(strings.ReplaceAll(raw, "\t", "    "))
		for len(r) > inner {
			lines = append(lines, line{string(r[:inner]), inner})
			r = r[inner:]
		}
		lines = append(lines, line{string(r), len(r)})
	}
	return panel(lines, w, border, "SSH / rsync diagnostics", border)
}

// live redraws a frame in place, like Rich's Live.
type live struct {
	out   *os.File
	drawn int
}

func (l *live) update(frame []string) {
	var b strings.Builder
	b.WriteString(hideCursor)
	if l.drawn > 0 {
		fmt.Fprintf(&b, "\r\x1b[%dA", l.drawn)
	}
	b.WriteString("\x1b[J")
	for _, s := range frame {
		b.WriteString(s)
		b.WriteByte('\n')
	}
	_, _ = l.out.WriteString(b.String())
	l.drawn = len(frame)
}

// stop keeps the last frame; the next update draws below whatever follows it.
func (l *live) stop() { l.drawn = 0 }

func isTerminal(f *os.File) bool {
	var t syscall.Termios
	_, _, errno := syscall.Syscall(syscall.SYS_IOCTL, f.Fd(), uintptr(syscall.TCGETS), uintptr(unsafe.Pointer(&t)))
	return errno == 0
}

func termSize(f *os.File) (cols, rows int) {
	var ws struct{ Row, Col, X, Y uint16 }
	_, _, errno := syscall.Syscall(syscall.SYS_IOCTL, f.Fd(), uintptr(syscall.TIOCGWINSZ), uintptr(unsafe.Pointer(&ws)))
	if errno != 0 || ws.Col == 0 || ws.Row == 0 {
		return 80, 24
	}
	return int(ws.Col), int(ws.Row)
}

func plainMode(options []string, tty bool, term string) bool {
	if !tty || term == "dumb" {
		return true
	}
	for _, a := range options {
		switch a {
		case "--dry-run", "--quiet", "--help", "--version", "--list-only", "--daemon", "--server":
			return true
		}
		if strings.HasPrefix(a, "-") && !strings.HasPrefix(a, "--") && strings.ContainsAny(a[1:], "nqV") {
			return true
		}
	}
	return false
}

// command inserts the dashboard's flags before -- so dash-prefixed operands keep their meaning.
func command(args []string) []string {
	i := indexOf(args, "--")
	if i < 0 {
		i = len(args)
	}
	out := append([]string{}, args[:i]...)
	out = append(out, "--no-human-readable", "--outbuf=N", "--info=progress1,name1", "--out-format="+marker+"|%i|%l|%n")
	return append(out, args[i:]...)
}

// splitComplete holds back a trailing partial UTF-8 sequence for the next read.
func splitComplete(b []byte) ([]byte, []byte) {
	for i := len(b) - 1; i >= 0 && i >= len(b)-3; i-- {
		if utf8.RuneStart(b[i]) {
			if !utf8.FullRune(b[i:]) {
				return b[:i], b[i:]
			}
			break
		}
	}
	return b, nil
}

type chunk struct {
	stderr bool
	data   []byte
	eof    bool
}

func pump(f *os.File, stderr bool, out chan<- chunk) {
	buf := make([]byte, 65536)
	for {
		n, err := f.Read(buf)
		if n > 0 {
			out <- chunk{stderr: stderr, data: append([]byte(nil), buf[:n]...)}
		}
		if err != nil {
			out <- chunk{stderr: stderr, eof: true}
			return
		}
	}
}

func running(done <-chan struct{}) bool {
	select {
	case <-done:
		return false
	default:
		return true
	}
}

func exitStatus(ps *os.ProcessState) int {
	if ps == nil {
		return 1
	}
	if ws, ok := ps.Sys().(syscall.WaitStatus); ok && ws.Signaled() {
		return 128 + int(ws.Signal())
	}
	return ps.ExitCode()
}

func cancel(cmd *exec.Cmd, done <-chan struct{}) int {
	_ = cmd.Process.Signal(os.Interrupt)
	select {
	case <-done:
	case <-time.After(5 * time.Second):
		_ = cmd.Process.Kill()
		<-done
	}
	fmt.Println(st(yellow, "Transfer cancelled."))
	return 130
}

func dashboardRun(args []string) int {
	outR, outW, err := os.Pipe()
	if err != nil {
		fmt.Fprintln(os.Stderr, "glow:", err)
		return 1
	}
	errR, errW, err := os.Pipe()
	if err != nil {
		fmt.Fprintln(os.Stderr, "glow:", err)
		return 1
	}
	// Keep stdin and the controlling TTY for SSH authentication.
	cmd := exec.Command("rsync", command(args)...)
	cmd.Stdin = os.Stdin
	cmd.Stdout = outW
	cmd.Stderr = errW
	cmd.Env = append(os.Environ(), "LC_ALL=C")
	if err := cmd.Start(); err != nil {
		fmt.Fprintln(os.Stderr, "glow:", err)
		return 127
	}
	outW.Close()
	errW.Close()

	// *os.File outputs mean Wait never touches the pipes, so it can run alongside the readers.
	done := make(chan struct{})
	go func() {
		_ = cmd.Wait()
		close(done)
	}()
	chunks := make(chan chunk, 64)
	go pump(outR, false, chunks)
	go pump(errR, true, chunks)

	sigs := make(chan os.Signal, 1)
	signal.Notify(sigs, os.Interrupt, syscall.SIGTERM, syscall.SIGHUP)
	defer signal.Stop(sigs)
	defer os.Stdout.WriteString(showCursor)

	d := newDashboard()
	lv := &live{out: os.Stdout}
	cols, rows := termSize(os.Stdout)
	lv.update(d.render(cols, rows, time.Now()))

	ticker := time.NewTicker(100 * time.Millisecond)
	defer ticker.Stop()
	var pending, carry, diagnostics []byte
	var lastPaint time.Time
	for open := 2; open > 0; {
		select {
		case c := <-chunks:
			if c.stderr {
				data := append(append([]byte(nil), carry...), c.data...)
				var text []byte
				if c.eof {
					text, carry = data, nil
					open--
				} else {
					text, carry = splitComplete(data)
				}
				if len(text) > 0 {
					diagnostics = append(diagnostics, text...)
					if len(diagnostics) > 65536 {
						diagnostics = diagnostics[len(diagnostics)-65536:]
					}
					// Stop painting while a diagnostic or prompt is written.
					lv.stop()
					os.Stdout.WriteString(sanitize(string(text)))
				}
				continue
			}
			pending = append(pending, c.data...)
			for {
				i := bytes.IndexAny(pending, "\r\n")
				if i < 0 {
					break
				}
				d.consume(string(pending[:i]))
				pending = pending[i+1:]
			}
			if c.eof {
				d.consume(string(pending))
				pending = nil
				open--
			}
		case <-ticker.C:
		case <-sigs:
			return cancel(cmd, done)
		}
		// No repaint during connection/authentication: SSH may prompt on /dev/tty.
		if d.current != nil && running(done) && time.Since(lastPaint) >= 50*time.Millisecond {
			cols, rows = termSize(os.Stdout)
			lv.update(d.render(cols, rows, time.Now()))
			lastPaint = time.Now()
		}
	}

	select {
	case <-done:
	case <-sigs:
		return cancel(cmd, done)
	}
	code := exitStatus(cmd.ProcessState)
	d.scanning = false
	if code == 0 {
		d.status = "COMPLETE"
		d.checked = d.total
	} else {
		d.status = fmt.Sprintf("FAILED / EXIT %d", code)
	}
	cols, rows = termSize(os.Stdout)
	lv.update(d.render(cols, rows, time.Now()))
	if strings.TrimSpace(string(diagnostics)) != "" {
		border := yellow
		if code != 0 {
			border = red
		}
		for _, l := range diagnosticsPanel(string(diagnostics), cols, border) {
			fmt.Println(l)
		}
	}
	return code
}

func run(args []string) int {
	if len(args) == 0 || (len(args) == 1 && args[0] == "--help") {
		fmt.Print(helpText)
		return 0
	}
	options := args
	if i := indexOf(args, "--"); i >= 0 {
		options = args[:i]
	}
	if plainMode(options, isTerminal(os.Stdout), os.Getenv("TERM")) {
		path, err := exec.LookPath("rsync")
		if err != nil {
			fmt.Fprintln(os.Stderr, "glow: rsync not found in PATH")
			return 127
		}
		err = syscall.Exec(path, append([]string{"rsync"}, args...), os.Environ())
		fmt.Fprintln(os.Stderr, "glow:", err)
		return 127
	}
	return dashboardRun(args)
}

func main() { os.Exit(run(os.Args[1:])) }
