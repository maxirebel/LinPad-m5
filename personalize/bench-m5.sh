#!/bin/sh
# LinPad M5 baseline measurement.
#
# Read-only: it measures the running system and appends one block to
# ~/linpad-perf/bench.md. Nothing else is written, no package is installed.
#
#   sh bench-m5.sh "1.5.1 before S1"
#
# Timing uses /proc/uptime (centisecond resolution), so it works with busybox and
# without extra tools. Run it the same way every time: same build, cool device,
# charger connected, no other user apps, screen on.

set -u

LABEL=${1:-unlabelled}
OUT=${LINPAD_BENCH_OUT:-$HOME/linpad-perf}
mkdir -p "$OUT"

up() { cut -d' ' -f1 /proc/uptime; }
since() { awk -v a="$1" -v b="$2" 'BEGIN { printf "%.2f", b - a }'; }

mem_total=$(awk '/^MemTotal:/ {print int($2/1024)}' /proc/meminfo 2>/dev/null || echo 0)
mem_avail=$(awk '/^MemAvailable:/ {print int($2/1024)}' /proc/meminfo 2>/dev/null || echo 0)
cpus=$(grep -c '^processor' /proc/cpuinfo 2>/dev/null || echo 0)
load=$(cut -d' ' -f1-3 /proc/loadavg 2>/dev/null || echo '?')
rootver=$(cat /root/root.version 2>/dev/null | tr -d '\n' || echo '?')
alpine=$(cat /etc/alpine-release 2>/dev/null || echo '?')

# 1) POSIX shell: 200k iterations.
a=$(up); i=0; while [ "$i" -lt 200000 ]; do i=$((i + 1)); done; b=$(up)
shell_s=$(since "$a" "$b")

# 2) Node: 100 million loop iterations, when node is installed.
node_s='n/a'
if command -v node >/dev/null 2>&1; then
    a=$(up); node -e 'for (let i = 0; i < 1e8; i++) {}' >/dev/null 2>&1; b=$(up)
    node_s=$(since "$a" "$b")
fi

# 3) Firefox: loading the binary and its libraries (not a full window).
ff_s='n/a'
if command -v firefox-esr >/dev/null 2>&1; then
    a=$(up); firefox-esr --version >/dev/null 2>&1; b=$(up)
    ff_s=$(since "$a" "$b")
fi

# 4) Idle CPU: sample /proc/stat over two seconds.
idle_before=$(awk '/^cpu / {print $5, $2+$3+$4+$5+$6+$7+$8}' /proc/stat)
sleep 2
idle_after=$(awk '/^cpu / {print $5, $2+$3+$4+$5+$6+$7+$8}' /proc/stat)
idle_pct=$(echo "$idle_before $idle_after" | awk '{ d = $4 - $2; t = $3 - $1; if (t > 0) printf "%.0f", 100 * d / t; else print 0 }')

# 5) Firefox resident memory, if it is running.
ff_rss=$(ps -o rss= -C firefox-esr 2>/dev/null | awk '{ s += $1 } END { printf "%d", s / 1024 }')
[ -n "${ff_rss:-}" ] || ff_rss=0

report="$OUT/bench.md"
{
    echo
    echo "## $LABEL"
    echo
    echo "| metric | value |"
    echo "|---|---|"
    echo "| recorded (UTC) | $(date -u '+%Y-%m-%d %H:%M') |"
    echo "| rootfs version | $rootver |"
    echo "| alpine | $alpine |"
    echo "| kernel | $(uname -r) |"
    echo "| cpus | $cpus |"
    echo "| memory (MB total/available) | $mem_total / $mem_avail |"
    echo "| load average | $load |"
    echo "| shell 200k iterations (s) | $shell_s |"
    echo "| node 1e8 iterations (s) | $node_s |"
    echo "| firefox-esr load (s) | $ff_s |"
    echo "| idle CPU (%) | $idle_pct |"
    echo "| firefox resident (MB) | $ff_rss |"
} >> "$report"

cat "$report" | tail -n 18
echo
echo "appended to $report"
