#!/bin/sh
# Phase 1 — replace LinPad's Firefox ESR 128.14 with Debian's Firefox ESR 153.7,
# with a brand-new profile. Everything runs on the iPad; no Mac and no rebuild.
#
#   sh phase1-firefox.sh --check    what would happen, no changes
#   sh phase1-firefox.sh            do it
#   sh phase1-firefox.sh --undo     remove it and go back to the stock Firefox
#
# What it does:
#   1. keeps the old profile untouched and starts a fresh one in ~/.mozilla-firefox-esr153
#   2. removes the stock firefox-esr package (128.14, out of support)
#   3. builds the glibc library island (shared with VS Code/Wine if already built)
#   4. downloads and unpacks Debian's firefox-esr 153.7.0esr (arm64) under /opt/firefox-esr
#   5. writes a launcher /usr/local/bin/firefox-esr, a desktop entry and the icon
#   6. writes the "12 GB, no seccomp" pref profile into the fresh profile's user.js
#   7. verifies every library resolves, then prints what to test
#
# It writes only: /opt/firefox-esr, /usr/local/bin/firefox-esr,
# /usr/share/applications/firefox-esr.desktop, one icon, and files inside the profile.
# Nothing in /usr/lib is touched except the shared glibc island (same one VS Code uses).
set -eu

SEC_BASE=${FIREFOX_SEC_BASE:-https://security.debian.org/debian-security}
SEC_INDEX=${FIREFOX_SEC_INDEX:-$SEC_BASE/dists/trixie-security/main/binary-arm64/Packages.xz}
# Filled by resolve_latest() from Debian's index, unless FIREFOX_DEB overrides the file.
URL=${FIREFOX_DEB:-}
EXPECTED_BYTES=${FIREFOX_BYTES:-}
EXPECTED_SHA=${FIREFOX_SHA:-}
PREFIX=/opt/firefox-esr
BIN=/usr/local/bin/firefox-esr
DESKTOP=/usr/share/applications/firefox-esr.desktop
ICON_NAME=firefox-esr
MULTIARCH=/usr/lib/aarch64-linux-gnu
LOADER=/lib/ld-linux-aarch64.so.1
DEBFETCH=${DEBFETCH:-/usr/local/share/devtools/debfetch.mjs}
DEBIAN_SUITE=${DEBIAN_SUITE:-trixie}
CACHE=/var/cache/phase1-firefox
PROFILE=$HOME/.mozilla-firefox-esr153
STATE=/var/lib/linpad-phase1

# What Debian's firefox-esr links against, plus the decoder that makes H.264 playable.
# debfetch follows their own dependency closure from here.
LIBS="libc6 libgcc-s1 libstdc++6 libgtk-3-0t64 libglib2.0-0t64 libgdk-pixbuf-2.0-0
libpango-1.0-0 libcairo2 libcairo-gobject2 libfontconfig1 libfreetype6 libharfbuzz0b
libepoxy0 libffi8 libevent-2.1-7t64 libvpx9 libx11-6 libx11-xcb1 libxcb1 libxcb-shm0
libxcomposite1 libxdamage1 libxext6 libxfixes3 libxrandr2 libxkbcommon0
libwayland-client0 libwayland-cursor0 libwayland-egl1 libgbm1 libdrm2 libegl1 libgl1
libdbus-1-3 libasound2t64 libpulse0 libnspr4 libatk1.0-0t64 libatspi2.0-0t64
libatk-bridge2.0-0t64 libcups2t64 libexpat1 libudev1 libsecret-1-0 libavcodec61 zlib1g"

say() { printf '%s\n' "$*"; }
step() { printf '\n== %s\n' "$*" >&2; }
warn() { printf 'phase1: %s\n' "$*" >&2; }
die() { printf 'phase1: %s\n' "$*" >&2; exit 1; }

need_root() {
    [ "$(id -u)" = 0 ] || die "run this as root (the LinPad terminal is root by default)"
    [ -r /proc/meminfo ] || die "this does not look like the LinPad guest"
    [ "$(uname -m)" = aarch64 ] || die "this build expects aarch64"
}

ensure_tools() {
    missing=
    command -v curl >/dev/null 2>&1 || missing="$missing curl"
    command -v bsdtar >/dev/null 2>&1 || missing="$missing libarchive-tools"
    command -v node >/dev/null 2>&1 || missing="$missing nodejs"
    command -v xzcat >/dev/null 2>&1 || missing="$missing xz"
    command -v zstdcat >/dev/null 2>&1 || missing="$missing zstd"
    if [ -n "$missing" ]; then
        say "installing helper packages:$missing"
        # shellcheck disable=SC2086
        apk add -q --no-progress $missing >/dev/null || die "apk add failed:$missing"
    fi
}

island_ok() {
    [ -x "$LOADER" ] && [ -e "$MULTIARCH/libc.so.6" ]
}

island_ensure() {
    if island_ok; then
        say "glibc island already present: $MULTIARCH"
        return 0
    fi
    [ -f "$DEBFETCH" ] || die "$DEBFETCH is missing in this build"
    ensure_tools
    step "building the glibc island (one-time, a few hundred MB)"
    stage=$CACHE/island
    rm -rf "$stage" "$MULTIARCH.new"
    mkdir -p "$stage" "$MULTIARCH.new"
    # shellcheck disable=SC2086
    node "$DEBFETCH" --suite "$DEBIAN_SUITE" --cache "$CACHE/debs" --dest "$stage" $LIBS ||
        die "could not fetch the glibc libraries (network?)"
    if [ -d "$stage/usr/lib/aarch64-linux-gnu" ]; then
        cp -a "$stage/usr/lib/aarch64-linux-gnu/." "$MULTIARCH.new/" || die "copy failed"
    fi
    if [ -d "$stage/lib/aarch64-linux-gnu" ]; then
        cp -a "$stage/lib/aarch64-linux-gnu/." "$MULTIARCH.new/" || die "copy failed"
    fi
    find "$MULTIARCH.new" -type l -print > "$CACHE/links"
    while IFS= read -r link; do
        target=$(readlink "$link" 2>/dev/null || true)
        case $target in
        /*) ln -sfn "$(basename "$target")" "$link" ;;
        esac
    done < "$CACHE/links"
    rm -f "$CACHE/links"
    [ -e "$MULTIARCH.new/libc.so.6" ] || die "the fetched set has no libc.so.6"
    [ -e "$MULTIARCH.new/ld-linux-aarch64.so.1" ] || die "the fetched set has no loader"
    if [ -d "$MULTIARCH" ]; then
        mv "$MULTIARCH" "$MULTIARCH.old" || die "could not move the old island aside"
    fi
    mv "$MULTIARCH.new" "$MULTIARCH" || die "could not install the new island"
    rm -rf "$MULTIARCH.old"
    ln -sfn "$MULTIARCH/ld-linux-aarch64.so.1" "$LOADER"
    rm -rf "$stage"
    island_ok || die "the island still does not resolve"
    say "island ready"
}

# Finds the newest firefox-esr arm64 build in Debian's security archive and sets
# URL, EXPECTED_BYTES and EXPECTED_SHA. Falls back to a pinned version when the index
# cannot be read, so the script still works on a bad day.
resolve_latest() {
    if [ -n "$URL" ]; then
        say "using the file from FIREFOX_DEB: $(basename "$URL")"
        return 0
    fi
    mkdir -p "$CACHE"
    idx=$CACHE/Packages-trixie-security
    if [ ! -s "$idx" ]; then
        step "reading Debian's trixie-security package index"
        rm -f "$CACHE/Packages.xz"
        if curl -fsL --retry 3 -o "$CACHE/Packages.xz" "$SEC_INDEX"; then
            xzcat "$CACHE/Packages.xz" > "$idx" || rm -f "$idx"
            rm -f "$CACHE/Packages.xz"
        fi
    fi
    if [ -s "$idx" ]; then
        fields=$(awk '
            BEGIN { RS = ""; FS = "\n" }
            {
                pkg = 0; fn = ""; size = ""; sha = ""; ver = ""
                for (i = 1; i <= NF; i++) {
                    if ($i == "Package: firefox-esr") pkg = 1
                    else if ($i ~ /^Filename: /) fn = substr($i, 11)
                    else if ($i ~ /^Size: /) size = substr($i, 7)
                    else if ($i ~ /^SHA256: /) sha = substr($i, 9)
                    else if ($i ~ /^Version: /) ver = substr($i, 10)
                }
                if (pkg) { print fn; print size; print sha; print ver; exit }
            }' "$idx")
        fn=$(printf '%s\n' "$fields" | sed -n '1p')
        size=$(printf '%s\n' "$fields" | sed -n '2p')
        sha=$(printf '%s\n' "$fields" | sed -n '3p')
        ver=$(printf '%s\n' "$fields" | sed -n '4p')
        if [ -n "$fn" ]; then
            URL="${SEC_BASE%/}/$fn"
            EXPECTED_BYTES=$size
            EXPECTED_SHA=$sha
            say "newest in trixie-security: firefox-esr $ver ($((size / 1048576)) MB)"
            return 0
        fi
        warn "the index has no firefox-esr entry; using the pinned build"
    else
        warn "could not read $SEC_INDEX; using the pinned build"
    fi
    URL=https://security.debian.org/debian-security/pool/updates/main/f/firefox-esr/firefox-esr_153.7.0esr-1~deb13u1_arm64.deb
    EXPECTED_BYTES=71765024
    EXPECTED_SHA=
}

download() {
    mkdir -p "$CACHE"
    deb=$CACHE/$(basename "$URL")
    if [ -s "$deb" ]; then
        size=$(wc -c < "$deb")
        if [ -z "$EXPECTED_BYTES" ] || [ "$size" = "$EXPECTED_BYTES" ]; then
            warn "using the cached download ($size bytes)"
            printf '%s\n' "$deb"
            return 0
        fi
        warn "cached file has the wrong size ($size), downloading again"
        rm -f "$deb"
    fi
    step "downloading $(basename "$URL")"
    rm -f "$deb.part"
    curl -fL --retry 3 -o "$deb.part" "$URL" || die "download failed"
    size=$(wc -c < "$deb.part")
    [ -z "$EXPECTED_BYTES" ] || [ "$size" = "$EXPECTED_BYTES" ] ||
        die "size mismatch: got $size, expected $EXPECTED_BYTES"
    if [ -n "$EXPECTED_SHA" ]; then
        got=$(sha256sum "$deb.part" | cut -d' ' -f1)
        [ "$got" = "$EXPECTED_SHA" ] || die "checksum mismatch for $(basename "$deb")"
    fi
    mv -f "$deb.part" "$deb"
    printf '%s\n' "$deb"
}

# Unpacks next to the target, without touching the current install: a failed
# download or unpack must never leave the iPad without a browser.
unpack_stage() {
    deb=$1
    step "unpacking beside $PREFIX"
    tmp=$CACHE/unpack
    rm -rf "$tmp" "$PREFIX.new"
    mkdir -p "$tmp" "$PREFIX.new"
    bsdtar -xf "$deb" -C "$tmp" || die "cannot read $deb as a .deb"
    data=
    for candidate in "$tmp"/data.tar.*; do
        if [ -f "$candidate" ]; then data=$candidate; fi
    done
    [ -n "$data" ] || die "$deb has no data.tar payload"
    bsdtar -xf "$data" -C "$PREFIX.new" || die "cannot unpack $data"
    rm -rf "$tmp"
}

install_stage() {
    [ -d "$PREFIX.new" ] || die "nothing staged to install"
    rm -rf "$PREFIX"
    mv "$PREFIX.new" "$PREFIX" || die "could not move the payload into place"
}

app_binary() {
    for candidate in \
        "$PREFIX/usr/lib/firefox-esr/firefox-esr" \
        "$PREFIX/usr/lib/firefox/firefox" \
        "$PREFIX/usr/bin/firefox-esr"; do
        [ -x "$candidate" ] && printf '%s\n' "$candidate" && return 0
    done
    return 1
}

write_profile() {
    step "fresh profile: $PROFILE"
    mkdir -p "$PROFILE"
    cat > "$PROFILE/user.js" <<'EOF'
// LinPad M5 / 12 GB: Firefox ESR 153 on the iSH-ARM64 emulator.
// A fresh profile on purpose; the old ESR 128 profile is in ~/.mozilla, untouched.

// One content process. Every extra process retranslates libxul, and the JIT code
// cache is shared, so more processes is slower here, not faster.
user_pref("dom.ipc.processCount", 1);
user_pref("fission.autostart", false);
user_pref("dom.ipc.keepProcessesAlive.web", 1);
user_pref("dom.ipc.processPrelaunch.enabled", false);

// The emulator has no seccomp and no user namespaces (kernel/misc.c handles only two
// prctl options), so Firefox's content sandbox cannot start. Without this, tabs crash.
user_pref("security.sandbox.content.level", 0);
user_pref("security.sandbox.gpu.level", 0);

// Video: H.264 is by far the cheapest decoder here; VP9/AV1 under emulation drop frames.
user_pref("media.mediasource.webm.enabled", false);
user_pref("media.av1.enabled", false);

// Threads cost about 1.3 MB of host memory each and the emulator serialises a lot.
user_pref("layout.css.stylo-threads", 2);
user_pref("javascript.options.mem.gc_max_helper_threads", 2);
user_pref("gfx.webrender.enable-low-priority-pool", false);

// Caches sized for 12 GB instead of the 8 GB LinPad tuned for.
user_pref("browser.cache.memory.capacity", 65536);
user_pref("image.mem.surfacecache.max_size_kb", 262144);
user_pref("media.memory_caches_combined_limit_kb", 131072);
user_pref("browser.sessionhistory.max_total_viewers", 4);

// iPadOS ends a suspended app without warning; Firefox sees that as a crash.
user_pref("browser.sessionstore.interval", 15000);
user_pref("browser.sessionstore.resume_from_crash", true);
user_pref("browser.sessionstore.max_resumed_crashes", 10);
user_pref("browser.startup.page", 3);

// Memory pressure handling and the cheap wins.
user_pref("browser.low_commit_space_threshold_percent", 20);
user_pref("browser.tabs.unloadOnLowMemory", true);
user_pref("browser.tabs.min_inactive_duration_before_unload", 120000);
user_pref("toolkit.cosmeticAnimations.enabled", false);
user_pref("ui.prefersReducedMotion", 1);
user_pref("browser.newtab.preload", false);
user_pref("browser.newtabpage.activity-stream.feeds.telemetry", false);
user_pref("browser.newtabpage.activity-stream.telemetry", false);
user_pref("app.normandy.enabled", false);
user_pref("toolkit.telemetry.enabled", false);
user_pref("datareporting.policy.dataSubmissionEnabled", false);
user_pref("browser.urlbar.speculativeConnect.enabled", false);
user_pref("network.prefetch-next", false);
user_pref("network.predictor.enabled", false);
EOF
    say "wrote $PROFILE/user.js"
}

write_launcher() {
    binary=$1
    step "launcher: $BIN"
    mkdir -p "$(dirname "$BIN")"
    # shellcheck disable=SC2016  # the single-quoted parts are the launcher's own text
    {
        printf '#!/bin/sh\n'
        printf '# Phase 1: Debian Firefox ESR 153.7 under LinPad (glibc island).\n'
        printf '# The session preloads musl helpers (scm-compat), which a glibc program cannot\n'
        printf '# load, so the inherited preload and library path are cleared first.\n'
        printf 'unset LD_PRELOAD LD_LIBRARY_PATH LD_AUDIT\n'
        printf 'export MOZ_ENABLE_WAYLAND=1\n'
        printf 'export MOZ_DISABLE_CONTENT_SANDBOX=1\n'
        printf 'if [ -z "${WAYLAND_DISPLAY:-}" ]; then\n'
        printf '    XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp/xdg-runtime}"\n'
        printf '    export XDG_RUNTIME_DIR\n'
        printf '    [ -S "$XDG_RUNTIME_DIR/wayland-0" ] && export WAYLAND_DISPLAY=wayland-0\n'
        printf 'fi\n'
        printf 'exec "%s" --library-path "%s" "%s" --profile "%s" "$@"\n' \
            "$LOADER" "$MULTIARCH" "$binary" "$PROFILE"
    } > "$BIN"
    chmod 755 "$BIN"
}

write_desktop() {
    step "desktop entry and icon"
    mkdir -p "$(dirname "$DESKTOP")"
    {
        printf '[Desktop Entry]\n'
        printf 'Type=Application\n'
        printf 'Name=Firefox\n'
        printf 'Comment=Debian Firefox ESR 153.7 on LinPad (fresh profile)\n'
        printf 'Exec=%s %%u\n' "$BIN"
        printf 'TryExec=%s\n' "$BIN"
        printf 'Icon=%s\n' "$ICON_NAME"
        printf 'Terminal=false\n'
        printf 'Categories=Network;WebBrowser;\n'
        printf 'MimeType=text/html;text/xml;application/xhtml+xml;x-scheme-handler/http;x-scheme-handler/https;\n'
        printf 'StartupNotify=true\n'
    } > "$DESKTOP"

    icon=
    iconsize=
    for size in 256 128 64 48 32 16; do
        candidate="$PREFIX/usr/share/icons/hicolor/${size}x${size}/apps/$ICON_NAME.png"
        if [ -f "$candidate" ]; then icon=$candidate; iconsize=$size; break; fi
    done
    if [ -z "$icon" ] && [ -f "$PREFIX/usr/share/pixmaps/$ICON_NAME.png" ]; then
        icon=$PREFIX/usr/share/pixmaps/$ICON_NAME.png
        iconsize=48
    fi
    if [ -n "$icon" ]; then
        # Keep Debian's own size directory: a 128px icon in 256x256 looks blurry.
        icondir=/usr/share/icons/hicolor/${iconsize}x${iconsize}/apps
        mkdir -p "$icondir"
        cp "$icon" "$icondir/$ICON_NAME.png"
        mkdir -p "$STATE"
        printf '%s\n' "$icondir/$ICON_NAME.png" > "$STATE/icon"
        say "icon: $icon"
    else
        warn "no icon in the package; the launcher will use a generic one"
    fi
    if command -v ish-apply-style >/dev/null 2>&1; then
        ish-apply-style --cache-only >/dev/null 2>&1 || true
    fi
}

write_app_scale() {
    # Firefox keeps scale 2 normally and drops to 1 in fullscreen: a quarter of the
    # pixels for video. The name matters: /etc/ishwl/app-scale is keyed by program.
    scale=/etc/ishwl/app-scale
    mkdir -p /etc/ishwl
    touch "$scale"
    if ! grep -q '^firefox-esr ' "$scale"; then
        printf 'firefox-esr 2 1\n' >> "$scale"
        say "added firefox-esr 2 1 to $scale"
    fi
}

verify() {
    binary=$1
    step "checking that every library resolves"
    missing=$(env -u LD_PRELOAD -u LD_LIBRARY_PATH -u LD_AUDIT "$LOADER" --list "$binary" 2>&1 |
        awk '/not found/ { print $1 }' || true)
    if [ -n "$missing" ]; then
        warn "still missing: $(printf '%s' "$missing" | tr '\n' ' ')"
        warn "add the Debian package that ships them to LIBS in this script and run again"
        return 1
    fi
    say "all libraries resolve"
    return 0
}

remove_old_firefox() {
    if apk info -e firefox-esr >/dev/null 2>&1; then
        step "removing the stock firefox-esr (128.14)"
        apk del -q firefox-esr || die "apk del firefox-esr failed"
    else
        say "stock firefox-esr is not installed; nothing to remove"
    fi
    # The profile is deliberately left alone: it is the user's data, and the new
    # Firefox uses a different directory.
    if [ -d /root/.mozilla ]; then
        say "old profile kept at /root/.mozilla (not used by the new Firefox)"
    fi
}

status() {
    say "phase 1 status"
    if apk info -e firefox-esr >/dev/null 2>&1; then
        say "  stock package: installed ($(apk info -v firefox-esr 2>/dev/null | head -n1))"
    else
        say "  stock package: removed"
    fi
    if [ -x "$BIN" ]; then
        say "  launcher: $BIN"
    else
        say "  launcher: absent"
    fi
    if [ -d "$PREFIX" ]; then
        say "  payload:  $PREFIX ($(du -sh "$PREFIX" 2>/dev/null | cut -f1))"
    else
        say "  payload:  absent"
    fi
    if [ -f "$PROFILE/user.js" ]; then
        say "  profile:  $PROFILE (user.js present)"
    else
        say "  profile:  absent"
    fi
    if island_ok; then
        say "  island:   present ($(du -sh "$MULTIARCH" 2>/dev/null | cut -f1))"
    else
        say "  island:   absent"
    fi
}

preflight() {
    need_root
    ok=0
    say "preflight"
    if [ "$(uname -m)" = aarch64 ]; then say "  arch:     aarch64 ok"; else warn "  arch: not aarch64"; ok=1; fi
    free_kb=$(df -k / 2>/dev/null | awk 'NR==2 { print $4 }' || true)
    if [ -n "${free_kb:-}" ]; then
        free_mb=$((free_kb / 1024))
        say "  free:     ${free_mb} MB"
        [ "$free_mb" -ge 900 ] || { warn "  need about 900 MB free (payload + island + cache)"; ok=1; }
    else
        warn "  could not read free space; continuing"
    fi
    check_url=${URL:-$SEC_INDEX}
    if ! command -v curl >/dev/null 2>&1; then
        warn "  download: curl is not installed yet (it will be added); skipped the check"
    elif curl -fs -o /dev/null -r 0-0 --max-time 25 "$check_url" 2>/dev/null; then
        say "  download: reachable"
    else
        warn "  download: cannot reach $check_url (network or TLS problem)"
        ok=1
    fi
    if [ -f "$DEBFETCH" ]; then say "  debfetch: present"; else warn "  debfetch: missing at $DEBFETCH"; ok=1; fi
    status
    return $ok
}

undo() {
    step "removing the Phase 1 install"
    rm -f "$BIN" "$DESKTOP"
    if [ -s "$STATE/icon" ]; then
        rm -f "$(cat "$STATE/icon")"
    fi
    rm -rf "$PREFIX" "$CACHE"
    rm -rf "$STATE"
    say "kept: $PROFILE (your bookmarks/settings in the new profile)"
    say "the stock Firefox is not reinstalled automatically. To get it back:"
    say "  apk add firefox-esr"
    if command -v ish-apply-style >/dev/null 2>&1; then
        ish-apply-style --cache-only >/dev/null 2>&1 || true
    fi
}

apply() {
    if ! preflight; then
        warn "preflight found problems (above); nothing was changed."
        exit 1
    fi
    ensure_tools
    resolve_latest
    # Download and unpack first: only remove the old browser once everything else is ready.
    deb=$(download)
    island_ensure
    unpack_stage "$deb"
    remove_old_firefox
    install_stage
    binary=$(app_binary) || die "the payload has no firefox binary (unexpected layout)"
    say "binary: $binary"
    # The payload knows its own version; prefer it over the index string.
    appver=$(sed -n 's/^Version=//p' "$PREFIX/usr/lib/firefox-esr/application.ini" 2>/dev/null | head -n1 || true)
    if [ -n "${appver:-}" ]; then ver=$appver; fi
    write_profile
    write_launcher "$binary"
    write_desktop
    write_app_scale
    mkdir -p "$STATE"
    printf '%s\n' "$URL" > "$STATE/source"
    printf '%s\n' "$binary" > "$STATE/binary"
    printf '%s\n' "${ver:-unknown}" > "$STATE/version"
    verify "$binary" || warn "the app may still start; check the missing list above"

    step "done"
    say "run it:      firefox-esr https://example.com"
    say "first start takes 20-60 s under the emulator."
    say "version:     open about:support → Application Basics → Version (expect ${ver:-the new build})"
    say "profile:     $PROFILE"
    say "restart the desktop session to see the Firefox icon in Applications."
    say ""
    say "what to test, in order:"
    say "  1. five tabs open together for ten minutes (no tab crashes)"
    say "  2. a YouTube video (H.264) with sound"
    say "  3. a Persian site (font shaping)"
    say "  4. a download, then drag the file from Firefox to the desktop"
    say ""
    say "if something is wrong:  sh phase1-firefox.sh --undo"
}

case ${1:-} in
'' | --apply | --start) apply ;;
--check | --preflight) preflight ;;
--status) status ;;
--undo) need_root && undo ;;
-h | --help) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//' ;;
*) die "unknown option: $1 (try --help)" ;;
esac
