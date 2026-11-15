#!/bin/sh
# LinPad Phase 0 — the "no rebuild" setup, in one command.
#
# What it does, in order:
#   1. writes a baseline of five measurements (so improvements can be proven, not guessed)
#   2. applies the 12 GB profile (personalize/m5-tune.sh: Firefox prefs, malloc arenas, node heap)
#   3. prints the three settings that must be tapped on the iPad, and the command to run after
#
#   sh phase0.sh            apply, with a baseline first if none exists
#   sh phase0.sh --before   only measure (run this before changing anything)
#   sh phase0.sh --after    measure again and compare with the baseline
#   sh phase0.sh --check    environment and current state, no changes
#   sh phase0.sh --undo     remove the profile (m5-tune.sh --undo)
#
# Keep this file next to m5-tune.sh. Everything it changes is reversible.
set -eu

HERE=$(cd "$(dirname "$0")" && pwd)
# The tuning script usually sits next to this one; also look where a copied file lands.
TUNE=$HERE/m5-tune.sh
[ -f "$TUNE" ] || TUNE=/root/m5-tune.sh
[ -f "$TUNE" ] || TUNE=/usr/local/share/linpad/m5-tune.sh
STATE=/root/linpad-perf
MARKER="LinPad M5 profile"

say() { printf '%s\n' "$*"; }
step() { printf '\n== %s\n' "$*"; }
warn() { printf 'phase0: %s\n' "$*" >&2; }
die() { printf 'phase0: %s\n' "$*" >&2; exit 1; }

need_root() {
    [ "$(id -u)" = 0 ] || die "run this as root (the LinPad terminal is root by default)"
    [ -r /proc/meminfo ] || die "this does not look like the LinPad guest"
}

# ---------------------------------------------------------------- measurements

now() { cut -d' ' -f1 /proc/uptime; }

elapsed() {
    # $1 = start timestamp; prints seconds with two decimals
    awk -v a="$1" -v b="$(now)" 'BEGIN { printf "%.2f", b - a }'
}

bench_shell() {
    t0=$(now)
    i=0
    while [ $i -lt 200000 ]; do i=$((i + 1)); done
    elapsed "$t0"
}

bench_node() {
    if ! command -v node >/dev/null 2>&1; then
        printf 'n/a'
        return 0
    fi
    t0=$(now)
    node -e 'let s=0; for (let i=0;i<1e8;i++) s+=i; if (s===0) console.log(s)' >/dev/null 2>&1 || true
    elapsed "$t0"
}

idle_percent() {
    # Two samples of /proc/stat five seconds apart.
    read -r _ u1 n1 s1 i1 w1 q1 h1 si1 st1 < /proc/stat 2>/dev/null || {
        printf 'n/a'
        return 0
    }
    sleep 5
    read -r _ u2 n2 s2 i2 w2 q2 h2 si2 st2 < /proc/stat 2>/dev/null || {
        printf 'n/a'
        return 0
    }
    awk -v u1="$u1" -v n1="$n1" -v s1="$s1" -v i1="$i1" -v w1="$w1" -v q1="$q1" -v h1="$h1" -v si1="$si1" -v st1="$st1" \
        -v u2="$u2" -v n2="$n2" -v s2="$s2" -v i2="$i2" -v w2="$w2" -v q2="$q2" -v h2="$h2" -v si2="$si2" -v st2="$st2" '
        BEGIN {
            t1 = u1 + n1 + s1 + i1 + w1 + q1 + h1 + si1 + st1
            t2 = u2 + n2 + s2 + i2 + w2 + q2 + h2 + si2 + st2
            idle = (i2 - i1)
            total = t2 - t1
            if (total <= 0) print "n/a"; else printf "%.0f", 100 * idle / total
        }'
}

# Picks the two numbers from /proc/ish/memory that matter.
memory_numbers() {
    if [ -r /proc/ish/memory ]; then
        awk '
            /^footprint_mb:/ { f = $2 }
            /^allowance_mb:/ { a = $2 }
            END { if (f == "") f = "n/a"; if (a == "" || a == 0) a = "n/a"; printf "%s %s", f, a }' \
            /proc/ish/memory
    else
        printf 'n/a n/a'
    fi
}

run_bench() {
    label=$1
    mkdir -p "$STATE"
    file=$STATE/$label.txt
    say "measuring ($label) — close Firefox and other heavy apps first, takes ~15 s"
    mem=$(memory_numbers)
    footprint=${mem% *}
    allowance=${mem#* }
    shell_s=$(bench_shell)
    node_s=$(bench_node)
    idle=$(idle_percent)
    {
        printf 'when=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        printf 'footprint_mb=%s\n' "$footprint"
        printf 'allowance_mb=%s\n' "$allowance"
        printf 'shell_200k_s=%s\n' "$shell_s"
        printf 'node_1e8_s=%s\n' "$node_s"
        printf 'idle_pct=%s\n' "$idle"
    } > "$file"
    say "saved: $file"
    say "  memory   ${footprint} MB of ${allowance} MB"
    say "  shell    200k loops in ${shell_s} s"
    say "  node     1e8 loops in ${node_s} s"
    say "  idle     ${idle}% of the CPU"
}

metric() {
    # $1 = file, $2 = key
    sed -n "s/^$2=//p" "$1" 2>/dev/null | head -n1
}

verdict() {
    # $1 = key, $2 = before, $3 = after; prints a short human hint
    case $1 in
    shell_200k_s | node_1e8_s)
        awk -v b="$2" -v a="$3" 'BEGIN {
            if (b == "" || a == "" || b + 0 == 0) { print ""; exit }
            d = (a - b) / b * 100
            if (d < -10) printf "faster (%.0f%%)", -d
            else if (d > 10) printf "SLOWER (+%.0f%%)", d
            else printf "same"
        }'
        ;;
    idle_pct)
        awk -v b="$2" -v a="$3" 'BEGIN {
            if (b == "" || a == "") { print ""; exit }
            if (a + 0 > b + 0) printf "more idle (good)"
            else if (a + 0 < b + 0) printf "less idle (check)"
            else printf "same"
        }'
        ;;
    footprint_mb)
        awk -v b="$2" -v a="$3" 'BEGIN {
            if (b == "" || a == "" || b == "n/a") { print ""; exit }
            printf "%+d MB", a - b
        }'
        ;;
    *) printf '' ;;
    esac
}

compare() {
    before=$1
    after=$2
    printf '%-18s %-10s %-10s %s\n' "metric" "before" "after" "change"
    printf '%-18s %-10s %-10s %s\n' "------" "------" "-----" "------"
    for key in footprint_mb shell_200k_s node_1e8_s idle_pct; do
        b=$(metric "$before" "$key")
        a=$(metric "$after" "$key")
        [ -n "$b" ] || continue
        v=$(verdict "$key" "$b" "$a")
        unit=
        case $key in
        shell_200k_s | node_1e8_s) unit=" s" ;;
        footprint_mb) unit=" MB" ;;
        idle_pct) unit=" %" ;;
        esac
        printf '%-18s %-10s %-10s %s\n' "$key" "$b$unit" "$a$unit" "$v"
    done
}

# ---------------------------------------------------------------- modes

status() {
    say "phase0 status"
    say "  kernel:  $(uname -r)"
    mem=$(memory_numbers)
    say "  memory:  ${mem% *} MB used of ${mem#* } MB allowed"
    if [ -f /etc/ishwl/session.d/25-m5.sh ] && grep -q "$MARKER" /etc/ishwl/session.d/25-m5.sh 2>/dev/null; then
        say "  profile: applied (session hook present)"
    else
        say "  profile: not applied"
    fi
    if [ -f /usr/lib/firefox-esr/browser/defaults/preferences/ish-tune.js ] &&
        grep -q "$MARKER" /usr/lib/firefox-esr/browser/defaults/preferences/ish-tune.js 2>/dev/null; then
        say "  firefox: M5 block present"
    else
        say "  firefox: stock prefs"
    fi
    if [ -e /lib/ld-linux-aarch64.so.1 ] && [ -e /usr/lib/aarch64-linux-gnu/libc.so.6 ]; then
        say "  glibc:   island present"
    else
        say "  glibc:   island absent (only needed for Debian apps)"
    fi
    if [ -f "$STATE/baseline.txt" ]; then
        say "  baseline: $(metric "$STATE/baseline.txt" when)"
    else
        say "  baseline: none yet (run: sh phase0.sh --before)"
    fi
}

apply() {
    need_root
    mkdir -p "$STATE"
    if [ ! -f "$STATE/baseline.txt" ]; then
        step "baseline"
        run_bench baseline
    else
        say "baseline already exists ($(metric "$STATE/baseline.txt" when)); keeping it"
    fi

    step "applying the 12 GB profile"
    if [ -f "$TUNE" ]; then
        if ! sh "$TUNE"; then
            warn "m5-tune.sh declined to apply the profile (its reason is above)."
            warn "The baseline was kept. If this really is a 12 GB iPad but iPadOS reports"
            warn "a small allowance, run:  sh $TUNE --force"
            exit 1
        fi
    else
        die "m5-tune.sh not found next to phase0.sh; copy both files together"
    fi

    step "three settings that only you can tap on the iPad"
    say "  1. Settings > Fast Mode > Code cache: 512 MB  (then quit and reopen LinPad)"
    say "  2. Settings > Desktop > Performance overlay: ON"
    say "  3. Settings > Memory > Never close: code, firefox-esr"
    say ""
    say "  Then restart the Linux session (Lock Screen > Restart Desktop Session) so the"
    say "  session hook runs."
    say ""
    say "after a day of normal use, measure again and compare:"
    say "  sh phase0.sh --after"
}

selftest() {
    # Exercises compare() against synthetic data; used by the repository's checks.
    tmp=$(mktemp -d)
    printf 'when=x\nfootprint_mb=1200\nshell_200k_s=9.80\nnode_1e8_s=12.00\nidle_pct=70\n' > "$tmp/a"
    printf 'when=y\nfootprint_mb=1300\nshell_200k_s=1.30\nnode_1e8_s=2.50\nidle_pct=75\n' > "$tmp/b"
    compare "$tmp/a" "$tmp/b"
    rm -rf "$tmp"
}

case ${1:-} in
'' | --apply) apply ;;
--before)
    need_root
    run_bench baseline
    ;;
--after)
    need_root
    [ -f "$STATE/baseline.txt" ] || die "no baseline yet; run: sh phase0.sh --before"
    run_bench after
    step "baseline ($(metric "$STATE/baseline.txt" when)) vs now"
    compare "$STATE/baseline.txt" "$STATE/after.txt"
    say ""
    say "reminder: a change under 10% is noise on this emulator; look for 2-5x on the loop"
    ;;
--check) status ;;
--undo)
    need_root
    [ -f "$TUNE" ] || die "m5-tune.sh not found next to phase0.sh"
    sh "$TUNE" --undo
    ;;
--selftest) selftest ;;
-h | --help)
    sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'
    ;;
*) die "unknown option: $1 (try --help)" ;;
esac
