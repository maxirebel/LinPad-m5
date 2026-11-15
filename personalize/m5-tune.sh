#!/bin/sh
# LinPad M5 / 12 GB profile — guest-side tuning, no app rebuild needed.
#
# LinPad ships tuned for the iPad Air M3 (8 GB): one Firefox content process, small
# caches, two glibc malloc arenas. On an M5 iPad Pro with 12 GB the same settings throw
# away most of the hardware. This script relaxes them, reversibly:
#
#   sh m5-tune.sh            apply the profile (idempotent; backs up on first run)
#   sh m5-tune.sh --status   show what is applied right now
#   sh m5-tune.sh --undo     restore what was there before
#
# It touches only these two files:
#   /etc/ishwl/session.d/25-m5.sh                  malloc arenas + V8 heap floor
#   /usr/lib/firefox-esr/browser/defaults/preferences/ish-tune.js
#                                                  appended block of Firefox prefs
#
# The Firefox block goes into ish-tune.js itself rather than a new file: the order in
# which Firefox reads the files of defaults/preferences is not guaranteed, so a separate
# "zzz-*.js" could lose to LinPad's own prefs. The file is backed up and the block is
# marked, so --undo and repeated runs are safe.
set -eu

STATE=/var/lib/linpad/m5-profile
SESSION_HOOK=/etc/ishwl/session.d/25-m5.sh
PROFILE_HOOK=/etc/profile.d/99-linpad-m5.sh
GECKO=/usr/lib/firefox-esr/browser/defaults/preferences/ish-tune.js
MARKER="LinPad M5 profile"

die() { printf 'm5-tune: %s\n' "$*" >&2; exit 1; }
say() { printf 'm5-tune: %s\n' "$*"; }

FORCE=0
MODE=apply
while [ $# -gt 0 ]; do
    case $1 in
    --status) MODE=status ;;
    --undo) MODE=undo ;;
    --force) FORCE=1 ;;
    -h | --help)
        cat >&2 <<'USAGE'
m5-tune.sh — tune a LinPad guest for an M5 iPad Pro with 12 GB.

  sh m5-tune.sh            apply the profile
  sh m5-tune.sh --status   show what is applied
  sh m5-tune.sh --undo     restore LinPad's defaults
  sh m5-tune.sh --force    apply even when the allowance looks small

Files: /etc/ishwl/session.d/25-m5.sh, /etc/profile.d/99-linpad-m5.sh and a
marked block appended to Firefox's ish-tune.js. Backups live in
/var/lib/linpad/m5-profile.
USAGE
        exit 0
        ;;
    *) die "unknown argument: $1 (try --help)" ;;
    esac
    shift
done

[ "$(id -u)" = 0 ] || die "run this as root (the LinPad terminal is root by default)"

# Under the emulator /proc/meminfo reports what iPadOS allows this app as MemTotal
# (platform/darwin.c), not the device's 12 GB.
mem_kb=$(awk '/^MemTotal:/ { print $2 }' /proc/meminfo 2>/dev/null || true)
[ -n "$mem_kb" ] || die "cannot read /proc/meminfo"
mem_mb=$((mem_kb / 1024))
cores=$(grep -c '^processor' /proc/cpuinfo 2>/dev/null || true)
case ${cores:-0} in
'' | 0) cores=1 ;;
esac

backup_once() {
    [ -e "$1" ] || return 0
    mkdir -p "$STATE"
    bname=$(printf '%s' "$1" | tr '/' '_')
    [ -e "$STATE/$bname" ] || cp -p "$1" "$STATE/$bname"
}

# Restores one file from its backup, atomically (write a temp file, then rename).
restore_one() {
    rpath=$1
    rname=$(printf '%s' "$rpath" | tr '/' '_')
    if [ -e "$STATE/$rname" ]; then
        if ! cp -p "$STATE/$rname" "$rpath.m5-tmp"; then
            warn "could not write $rpath.m5-tmp"
            return 1
        fi
        if ! mv -f "$rpath.m5-tmp" "$rpath"; then
            warn "could not restore $rpath"
            return 1
        fi
    else
        rm -f "$rpath"
    fi
    return 0
}

warn() { printf 'm5-tune: %s\n' "$*" >&2; }

status() {
    say "allowance ${mem_mb} MB, ${cores} CPUs, kernel $(uname -r)"
    for f in "$SESSION_HOOK" "$PROFILE_HOOK"; do
        if [ -f "$f" ] && grep -q "$MARKER" "$f" 2>/dev/null; then
            say "applied: $f"
        else
            say "absent:  $f"
        fi
    done
    if [ -f "$GECKO" ] && grep -q "$MARKER" "$GECKO" 2>/dev/null; then
        say "applied: $GECKO (appended block)"
    else
        say "absent:  $GECKO block"
    fi
    if [ -e /lib/ld-linux-aarch64.so.1 ] && [ -e /usr/lib/aarch64-linux-gnu/libc.so.6 ]; then
        say "glibc island: present"
    else
        say "glibc island: absent (glibc software cannot run yet)"
    fi
}

undo() {
    failed=0
    restore_one "$SESSION_HOOK" || failed=1
    restore_one "$PROFILE_HOOK" || failed=1
    if [ -f "$GECKO" ] && grep -q "$MARKER" "$GECKO" 2>/dev/null; then
        restore_one "$GECKO" || failed=1
    fi
    if [ "$failed" = 0 ]; then
        rm -rf "$STATE"
        say "stock LinPad tuning restored; restart the desktop session to apply it"
    else
        say "some files could not be restored; their backups are kept in $STATE"
        exit 1
    fi
}

apply() {
    # 1. Session hook. MALLOC_ARENA_MAX is set unconditionally: 15-lowmem.sh runs first
    #    and sets ${MALLOC_ARENA_MAX:-2}, so after it the variable is already "2" and a
    #    :- default here would never take effect. NODE_OPTIONS is a floor, not an
    #    override, because VS Code's own launcher and npm scripts may set it.
    backup_once "$SESSION_HOOK"
    mkdir -p /etc/ishwl/session.d
    cat > "$SESSION_HOOK" <<'EOF'
# LinPad M5 profile (added by m5-tune.sh; remove this file to go back).
# 15-lowmem.sh set 2 arenas for an 8 GB device; glibc programs (VS Code, Wine) can keep
# more per-thread arenas with 12 GB, which is faster with many threads.
export MALLOC_ARENA_MAX=6
# V8 sizes its heap from MemTotal, which here is the app's allowance; a floor keeps big
# vite/tsc builds from dying while Firefox is also open.
if [ -z "${NODE_OPTIONS:-}" ]; then
    export NODE_OPTIONS="--max-old-space-size=4096"
fi
EOF
    say "wrote $SESSION_HOOK"

    # 2. Login-shell copy of NODE_OPTIONS, for programs started from a plain terminal
    #    rather than from the desktop session.
    backup_once "$PROFILE_HOOK"
    cat > "$PROFILE_HOOK" <<'EOF'
# LinPad M5 profile: a V8 heap sized for a 12 GB iPad.
if [ -z "${NODE_OPTIONS:-}" ]; then
    export NODE_OPTIONS="--max-old-space-size=4096"
fi
EOF
    say "wrote $PROFILE_HOOK"

    # 3. Firefox. Appended to LinPad's own file so it always wins; the media prefs
    #    (H.264-only MSE) stay exactly as gecko-tune.sh set them.
    if [ -x /usr/lib/firefox-esr/firefox-esr ] && [ -f "$GECKO" ]; then
        if grep -q "$MARKER" "$GECKO" 2>/dev/null; then
            say "Firefox block already present"
        else
            backup_once "$GECKO"
            cat >> "$GECKO" <<'EOF'

// --- LinPad M5 profile (m5-tune.sh) -------------------------------------------------
// A 12 GB iPad Pro, not an 8 GB iPad Air. Delete this block (or run m5-tune.sh --undo)
// to go back to LinPad's defaults.
// Two content processes instead of one: each costs another translated copy of libxul,
// so raise this only together with Settings > Fast Mode > Code cache (512 MB).
pref("dom.ipc.processCount", 2);
pref("dom.ipc.processCount.webIsolated", 2);
pref("dom.ipc.keepProcessesAlive.web", 2);
pref("browser.cache.memory.capacity", 65536);
pref("image.mem.surfacecache.max_size_kb", 262144);
pref("media.memory_caches_combined_limit_kb", 131072);
pref("media.mediasource.eviction_threshold.video", 134217728);
pref("media.mediasource.eviction_threshold.audio", 20971520);
pref("browser.sessionhistory.max_total_viewers", 4);
pref("layout.css.stylo-threads", 4);
pref("javascript.options.mem.gc_max_helper_threads", 3);
pref("browser.tabs.min_inactive_duration_before_unload", 300000);
EOF
            say "appended the Firefox block to $GECKO"
        fi
    else
        say "firefox-esr or its prefs file is missing; skipped Firefox"
    fi

    say "done: ${mem_mb} MB allowance, ${cores} CPUs."
    say "Restart the desktop session (Lock Screen > Restart Desktop Session, or relaunch"
    say "LinPad) so the session hook runs, then set Settings > Fast Mode > Code cache to"
    say "512 MB."
}

# The profile is for a machine that can hold several GB of guest memory. Below that the
# stock LinPad tuning is the right one.
if [ "$MODE" = apply ] && [ "$mem_mb" -lt 3584 ] && [ "$FORCE" = 0 ]; then
    die "iPadOS allows this app only ${mem_mb} MB; the stock tuning fits that better. Use --force to apply anyway."
fi

case $MODE in
apply) apply ;;
status) status ;;
undo) undo ;;
esac
