import Foundation

/// Guest-side tools that ship inside the app, so a fresh LinPad needs no terminal.
/// SetupService writes them into the guest on first launch; the marker file keeps that
/// idempotent, and bumping `version` re-applies them after an app update.
enum BundledScripts {
    static let version = "2026-11-15.1"
    // MARK: linpad-shelf
    static let linpadShelf = ##"""
#!/bin/sh
# linpad-shelf — Phase 2 core: a quarantine shelf for Debian applications.
#
# Every app lives in its own directory, runs against one shared glibc runtime, and writes
# nothing into the system. apk stays the owner of Alpine packages; this tool owns only
# what it created and can remove exactly that.
#
#   linpad-shelf install <debian-package>     from Debian's trixie repository
#   linpad-shelf install ./app_arm64.deb      a local file
#   linpad-shelf install https://…/app.deb    a URL
#   linpad-shelf remove <name>
#   linpad-shelf list
#   linpad-shelf verify [name]
#   linpad-shelf runtime                      what the shared runtime contains
#   linpad-shelf runtime add <debian-pkg>…    add more Debian libraries to it
#   linpad-shelf runtime rebuild              start the runtime over from the base list
#   linpad-shelf doctor
#
# Options: --name NAME, --x11, --system-data (copy the app's /usr/share data into the
# system; only for apps that ignore XDG_DATA_DIRS).
#
# Layout:
#   /usr/lib/linpad-shelf/runtime/        shared glibc runtime (grows, never touches /lib)
#   /opt/linpad-shelf/<name>/root/        the app payload (the only place it lives)
#   /opt/linpad-shelf/<name>/lib/         private libraries the payload brought itself
#   /usr/local/bin/<name>                 generated launcher
#   /usr/share/applications/<name>.desktop
#   /var/lib/linpad-shelf/<name>/         ledger: meta, files, dirs, extras
#
# Nothing is written to /usr/lib, /lib or /usr/bin. The runtime is the only library
# source, so one app's bad .deb cannot break another app or the system.
set -eu

RUNTIME=/usr/lib/linpad-shelf/runtime
APPS=/opt/linpad-shelf
STATE=/var/lib/linpad-shelf
CACHE=/var/cache/linpad-shelf
BIN_DIR=/usr/local/bin
DESKTOP_DIR=/usr/share/applications
ICON_ROOT=/usr/share/icons/hicolor
DEBFETCH=${DEBFETCH:-/usr/local/share/devtools/debfetch.mjs}
DEBIAN_SUITE=${DEBIAN_SUITE:-trixie}
DEBIAN_MIRROR=${DEBIAN_MIRROR:-https://deb.debian.org/debian}
MARKER="managed by linpad-shelf"

# Firefox is special: one canonical name (so ish-open and $BROWSER reach it), a dedicated
# fresh profile, and the 12 GB / no-seccomp prefs. The profile is user data and survives
# a shelf remove.
FIREFOX_NAME="firefox-esr"
FIREFOX_PROFILE=${LINPAD_FIREFOX_PROFILE:-$HOME/.mozilla-firefox-esr153}
SEC_BASE=${FIREFOX_SEC_BASE:-https://security.debian.org/debian-security}
SEC_INDEX=${FIREFOX_SEC_INDEX:-$SEC_BASE/dists/trixie-security/main/binary-arm64/Packages.xz}

# The shared runtime: glibc plus what a normal desktop app links. One copy for all apps.
BASE_LIBS="libc6 libgcc-s1 libstdc++6 libglib2.0-0t64 libgtk-3-0t64 libgtk-4-1
libgdk-pixbuf-2.0-0 libpango-1.0-0 libcairo2 libcairo-gobject2 libharfbuzz0b libepoxy0
libfontconfig1 libfreetype6 libx11-6 libx11-xcb1 libxcb1 libxcb-shm0 libxext6
libxrender1 libxi6 libxtst6 libxcursor1 libxrandr2 libxfixes3 libxcomposite1
libxdamage1 libxshmfence1 libxkbcommon0 libxkbcommon-x11-0 libwayland-client0
libwayland-cursor0 libwayland-egl1 libgbm1 libdrm2 libegl1 libgl1 libvulkan1
libdbus-1-3 libasound2t64 libpulse0 libnss3 libnspr4 libatk1.0-0t64 libatspi2.0-0t64
libatk-bridge2.0-0t64 libcups2t64 libexpat1 libudev1 libsecret-1-0 libavcodec61"

MODE=
NAME=
WANT_X11=0
WANT_SYSTEM_DATA=0
WANT_JSON=0
TARGET=
EXTRA=

log() { printf '==> %s\n' "$*" >&2; }
step() { printf '\n== %s\n' "$*" >&2; }
warn() { printf 'linpad-shelf: %s\n' "$*" >&2; }
die() { printf 'linpad-shelf: %s\n' "$*" >&2; exit 1; }

usage() {
    cat >&2 <<'EOF'
linpad-shelf — install Debian applications in a quarantine shelf.

  install <pkg|file|url>     Debian package name, a .deb file, or a URL
  remove <name>              delete everything the shelf created for the app
  list                       what is installed, its version, runtime and size
  verify [name]              check that every library of the app resolves
  runtime                    what the shared runtime contains
  runtime add <pkg>...       add more Debian libraries to the shared runtime
  runtime rebuild            rebuild the runtime from the base list
  migrate-firefox            move Firefox into the shelf and make it the default
  doctor                     environment, runtime and apps

Options: --name NAME, --x11, --system-data.

Only aarch64 .debs run. Flatpak/Snap/Docker, FUSE and x86_64 do not work on LinPad.
EOF
    exit 0
}

need_root() {
    [ "$(id -u)" = 0 ] || die "run this as root (the LinPad terminal is root by default)"
    [ -r /proc/meminfo ] || die "this does not look like the LinPad guest"
    [ "$(uname -m)" = aarch64 ] || die "this build expects aarch64"
}

valid_name() {
    case $1 in
    '' | . | ..) return 1 ;;
    *[!A-Za-z0-9._-]*) return 1 ;;
    esac
    return 0
}

slugify() {
    printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9._-' '-' |
        sed -e 's/-\{2,\}/-/g' -e 's/^-//' -e 's/-$//'
}

apk_owns() {
    apk info -W "$1" 2>/dev/null | grep -q 'is owned by'
}

is_firefox_name() {
    case $1 in
    *firefox*) return 0 ;;
    esac
    return 1
}

# The fresh profile and its tuning. Written once; an existing user.js is never touched.
firefox_profile() {
    mkdir -p "$FIREFOX_PROFILE"
    [ -s "$FIREFOX_PROFILE/user.js" ] && return 0
    cat > "$FIREFOX_PROFILE/user.js" <<'EOF'
// LinPad M5 / 12 GB: Firefox from Debian, under the iSH-ARM64 emulator.
// One content process: every extra process retranslates libxul.
user_pref("dom.ipc.processCount", 1);
user_pref("fission.autostart", false);
user_pref("dom.ipc.keepProcessesAlive.web", 1);
user_pref("dom.ipc.processPrelaunch.enabled", false);
// No seccomp and no user namespaces here, so the content sandbox cannot start.
user_pref("security.sandbox.content.level", 0);
user_pref("security.sandbox.gpu.level", 0);
// H.264 is the cheapest decoder under emulation.
user_pref("media.mediasource.webm.enabled", false);
user_pref("media.av1.enabled", false);
// Threads cost host memory and the emulator serialises a lot.
user_pref("layout.css.stylo-threads", 2);
user_pref("javascript.options.mem.gc_max_helper_threads", 2);
// Caches sized for 12 GB.
user_pref("browser.cache.memory.capacity", 65536);
user_pref("image.mem.surfacecache.max_size_kb", 262144);
user_pref("media.memory_caches_combined_limit_kb", 131072);
user_pref("browser.sessionhistory.max_total_viewers", 4);
// iPadOS ends a suspended app without warning; Firefox sees that as a crash.
user_pref("browser.sessionstore.interval", 15000);
user_pref("browser.sessionstore.resume_from_crash", true);
user_pref("browser.sessionstore.max_resumed_crashes", 10);
user_pref("browser.startup.page", 3);
user_pref("browser.low_commit_space_threshold_percent", 20);
user_pref("browser.tabs.unloadOnLowMemory", true);
user_pref("toolkit.cosmeticAnimations.enabled", false);
user_pref("ui.prefersReducedMotion", 1);
user_pref("toolkit.telemetry.enabled", false);
user_pref("datareporting.policy.dataSubmissionEnabled", false);
EOF
}

# Keeps the desktop-side scale rule Firefox already relies on (sharp text at rest,
# half the pixels in fullscreen). The line is shared with a restored stock Firefox,
# so it is never removed with the app.
firefox_scale() {
    scale=/etc/ishwl/app-scale
    mkdir -p /etc/ishwl
    touch "$scale"
    grep -q '^firefox-esr ' "$scale" 2>/dev/null || printf 'firefox-esr 2 1\n' >> "$scale"
}

ensure_tools() {
    missing=
    command -v curl >/dev/null 2>&1 || missing="$missing curl"
    command -v bsdtar >/dev/null 2>&1 || missing="$missing libarchive-tools"
    command -v node >/dev/null 2>&1 || missing="$missing nodejs"
    command -v xzcat >/dev/null 2>&1 || missing="$missing xz"
    command -v zstdcat >/dev/null 2>&1 || missing="$missing zstd"
    if [ -n "$missing" ]; then
        log "installing helper packages:$missing"
        # shellcheck disable=SC2086
        apk add -q --no-progress $missing >/dev/null || die "apk add failed:$missing"
    fi
}

# ------------------------------------------------------------------ runtime

runtime_ok() {
    [ -x "$RUNTIME/ld-linux-aarch64.so.1" ] && [ -e "$RUNTIME/libc.so.6" ]
}

# Downloads Debian packages and merges their multiarch libraries into the runtime.
runtime_fetch() {
    [ -f "$DEBFETCH" ] || die "$DEBFETCH is missing; this build has no glibc helper"
    stage=$CACHE/libstage
    rm -rf "$stage"
    mkdir -p "$stage" "$RUNTIME"
    # The package list is deliberately word-split into separate arguments.
    # shellcheck disable=SC2048,SC2086
    node "$DEBFETCH" --suite "$DEBIAN_SUITE" --mirror "$DEBIAN_MIRROR" \
        --cache "$CACHE/debs" --dest "$stage" $* >&2 || die "could not fetch the libraries"
    if [ -d "$stage/usr/lib/aarch64-linux-gnu" ]; then
        cp -a "$stage/usr/lib/aarch64-linux-gnu/." "$RUNTIME/" || die "could not merge libraries"
    fi
    if [ -d "$stage/lib/aarch64-linux-gnu" ]; then
        cp -a "$stage/lib/aarch64-linux-gnu/." "$RUNTIME/" || die "could not merge libraries"
    fi
    # Debian's absolute symlinks point at /lib/aarch64-linux-gnu, which must not exist
    # here; point them at their neighbour in the flat runtime directory instead.
    find "$RUNTIME" -type l -print > "$CACHE/links"
    while IFS= read -r link; do
        target=$(readlink "$link" 2>/dev/null || true)
        case $target in
        /*) ln -sfn "$(basename "$target")" "$link" ;;
        esac
    done < "$CACHE/links"
    rm -f "$CACHE/links"
    rm -rf "$stage"
}

runtime_ensure() {
    runtime_ok && return 0
    ensure_tools
    step "building the shared runtime (one-time, a few hundred MB)"
    mkdir -p "$RUNTIME"
    # shellcheck disable=SC2086
    runtime_fetch $BASE_LIBS
    runtime_ok || die "the runtime does not resolve after building it"
    log "runtime ready: $RUNTIME ($(du -sh "$RUNTIME" 2>/dev/null | cut -f1))"
}

cmd_runtime() {
    if [ $# -eq 0 ]; then
        if runtime_ok; then
            printf 'path: %s\nsize: %s\nlibs: %s files\n' "$RUNTIME" \
                "$(du -sh "$RUNTIME" 2>/dev/null | cut -f1)" \
                "$(find "$RUNTIME" -type f 2>/dev/null | wc -l)"
        else
            printf 'no runtime yet (it is built on the first install)\n'
        fi
        return 0
    fi
    case $1 in
    add)
        shift
        [ $# -gt 0 ] || die "runtime add needs at least one Debian package name"
        runtime_ensure
        step "adding to the shared runtime: $*"
        # shellcheck disable=SC2086
        runtime_fetch "$@"
        log "runtime updated: $(du -sh "$RUNTIME" 2>/dev/null | cut -f1)"
        ;;
    rebuild)
        rm -rf "$RUNTIME"
        runtime_ensure
        ;;
    *) die "usage: linpad-shelf runtime [add <pkg>...|rebuild]" ;;
    esac
}

# ------------------------------------------------------------------ Firefox (phase 3)

# Reads the newest firefox-esr arm64 build out of Debian's security index and prints
# "<url> <size>". Empty output means the index could not be read.
resolve_security_deb() {
    idx=$CACHE/Packages-trixie-security
    if [ ! -s "$idx" ]; then
        mkdir -p "$CACHE"
        rm -f "$CACHE/Packages.xz"
        curl -fsL --retry 3 -o "$CACHE/Packages.xz" "$SEC_INDEX" || return 0
        xzcat "$CACHE/Packages.xz" > "$idx" || { rm -f "$idx"; return 0; }
        rm -f "$CACHE/Packages.xz"
    fi
    fields=$(awk '
        BEGIN { RS = ""; FS = "\n" }
        {
            pkg = 0; fn = ""; size = ""
            for (i = 1; i <= NF; i++) {
                if ($i == "Package: firefox-esr") pkg = 1
                else if ($i ~ /^Filename: /) fn = substr($i, 11)
                else if ($i ~ /^Size: /) size = substr($i, 7)
            }
            if (pkg) { print fn; print size; exit }
        }' "$idx")
    fn=$(printf '%s\n' "$fields" | sed -n '1p')
    size=$(printf '%s\n' "$fields" | sed -n '2p')
    [ -n "$fn" ] || return 0
    printf '%s %s\n' "${SEC_BASE%/}/$fn" "$size"
}

# The host's link handler is chosen by a UserDefaults key that has no UI, so on a build
# without it every ish-open URL would go to the native Quick Preview. Replacing the guest
# helper is the one lever available without a Mac, and it is fully reversible.
ISH_OPEN=$BIN_DIR/ish-open
ISH_BACKUP=$STATE/ish-open.orig

default_browser_override() {
    [ -f "$ISH_OPEN" ] || return 0
    if grep -q "$MARKER" "$ISH_OPEN" 2>/dev/null; then
        return 0
    fi
    if apk_owns "$ISH_OPEN"; then
        warn "$ISH_OPEN belongs to an apk package; leaving it alone"
        return 0
    fi
    mkdir -p "$STATE"
    if [ ! -f "$ISH_BACKUP" ]; then
        cp -p "$ISH_OPEN" "$ISH_BACKUP" || die "could not back up $ISH_OPEN"
    fi
    {
        printf '#!/bin/sh\n'
        printf '# %s: http(s) URLs go to the shelf Firefox, not the host preview.\n' "$MARKER"
        printf 'exec "%s/%s" "$@"\n' "$BIN_DIR" "$FIREFOX_NAME"
    } > "$ISH_OPEN"
    chmod 755 "$ISH_OPEN"
    log "ish-open now sends links to $FIREFOX_NAME (original backed up)"
}

default_browser_restore() {
    [ -f "$ISH_BACKUP" ] || return 0
    cp -p "$ISH_BACKUP" "$ISH_OPEN" || warn "could not restore $ISH_OPEN from $ISH_BACKUP"
    rm -f "$ISH_BACKUP"
    log "restored the original ish-open"
}

# Removes the stock Alpine firefox-esr (128.14) and anything it left behind.
stock_firefox_gone() {
    if apk info -e firefox-esr >/dev/null 2>&1; then
        step "removing the stock firefox-esr (out of support)"
        apk del -q firefox-esr || warn "apk del firefox-esr failed"
    fi
    rm -rf /usr/lib/firefox-esr
    if [ -f "$DESKTOP_DIR/firefox-esr.desktop" ] &&
        ! grep -q "$MARKER" "$DESKTOP_DIR/firefox-esr.desktop" 2>/dev/null; then
        rm -f "$DESKTOP_DIR/firefox-esr.desktop"
    fi
    if [ -d /root/.mozilla ]; then
        log "old profile kept at /root/.mozilla (the new Firefox uses $FIREFOX_PROFILE)"
    fi
}

# Turns the phase-1 install under /opt/firefox-esr into a shelf app, without downloading.
absorb_phase1() {
    step "taking over the phase-1 Firefox install (no download needed)"
    if [ -s /var/lib/linpad-phase1/icon ]; then
        rm -f "$(cat /var/lib/linpad-phase1/icon)"
    fi
    rm -f "$BIN_DIR/$FIREFOX_NAME" "$DESKTOP_DIR/$FIREFOX_NAME.desktop"
    rm -rf /var/lib/linpad-phase1
    mkdir -p "$APPS/$FIREFOX_NAME/root" "$APPS/$FIREFOX_NAME/lib"
    mv /opt/firefox-esr/. "$APPS/$FIREFOX_NAME/root/" || die "could not move the payload"
    rmdir /opt/firefox-esr 2>/dev/null || rm -rf /opt/firefox-esr

    state_init "$FIREFOX_NAME"
    printf '%s\n' "$(sed -n 's/^Version=//p' "$APPS/$FIREFOX_NAME/root/usr/lib/firefox-esr/application.ini" 2>/dev/null | head -n1)" \
        > "$STATE/$FIREFOX_NAME/version"
    printf '%s\n' firefox-esr > "$STATE/$FIREFOX_NAME/package"
    printf '%s\n' "phase1:absorbed" > "$STATE/$FIREFOX_NAME/source"
    printf '%s\n' "$FIREFOX_PROFILE" > "$STATE/$FIREFOX_NAME/profile"
    (
        cd "$APPS/$FIREFOX_NAME/root" &&
            find . \( -type f -o -type l \) -print | sed 's|^\./||' > "$STATE/$FIREFOX_NAME/files"
    )
    : > "$STATE/$FIREFOX_NAME/dirs"
    # The phase-1 island lived in /usr/lib/aarch64-linux-gnu; the shelf runtime is
    # separate, so bring in the libraries Firefox links against.
    step "adding Firefox's libraries to the shelf runtime"
    # shellcheck disable=SC2086
    runtime_fetch libevent-2.1-7t64 libvpx9 libx11-xcb1 libxcb-shm0 libcairo-gobject2 \
        libffi8 libavcodec61 || warn "some libraries could not be added; verify will say which"
    finish_install "$FIREFOX_NAME" "$(cat "$STATE/$FIREFOX_NAME/version")"
}

cmd_migrate_firefox() {
    need_root
    runtime_ensure
    if [ -d "$APPS/$FIREFOX_NAME" ]; then
        log "$FIREFOX_NAME is already a shelf app"
        cmd_list
        return 0
    fi
    stock_firefox_gone
    if [ -d /opt/firefox-esr/usr ]; then
        absorb_phase1
    else
        step "resolving the newest firefox-esr from Debian security"
        resolved=$(resolve_security_deb)
        [ -n "$resolved" ] || die "could not read Debian's security index (network?)"
        url=${resolved% *}
        size=${resolved#* }
        step "downloading $(basename "$url") ($((size / 1048576)) MB)"
        mkdir -p "$CACHE/debs"
        deb=$CACHE/debs/$(basename "$url")
        if [ ! -s "$deb" ]; then
            curl -fL --retry 3 -o "$deb.part" "$url" || die "download failed"
            bytes=$(wc -c < "$deb.part")
            [ -z "$size" ] || [ "$bytes" = "$size" ] || die "size mismatch: got $bytes, expected $size"
            mv -f "$deb.part" "$deb"
        fi
        install_from_file "$deb" "$FIREFOX_NAME"
    fi
    default_browser_override
    step "Firefox is now a shelf app"
    printf '  launcher: %s\n' "$BIN_DIR/$FIREFOX_NAME"
    printf '  profile:  %s\n' "$FIREFOX_PROFILE"
    printf '  links from Linux apps open it (ish-open -> %s)\n' "$FIREFOX_NAME"
    printf '  remove:   linpad-shelf remove %s\n' "$FIREFOX_NAME"
    printf '  restore the stock build: apk add firefox-esr\n'
}

# ------------------------------------------------------------------ trees

# Where a payload path belongs: the shared runtime (multiarch libraries) or the app.
classify_path() {
    case $1 in
    usr/lib/aarch64-linux-gnu/* | lib/aarch64-linux-gnu/*) printf 'runtime\n' ;;
    *) printf 'app\n' ;;
    esac
}

# Copies a staged tree into an app root, replacing symlinks instead of writing through
# them, and records files and created directories for a clean removal.
copy_app_tree() {
    ctree=$1
    cdest=$2
    clist=$3
    cdirmap=$4
    find "$ctree" \( -type f -o -type l \) -print > "$CACHE/payload.list"
    while IFS= read -r csrc; do
        crel=${csrc#"$ctree"/}
        case $crel in
        .packages | ./*) continue ;;
        esac
        case $(classify_path "$crel") in
        runtime) continue ;;
        esac
        cdst=$cdest/$crel
        cdir=$(dirname "$cdst")
        if [ ! -d "$cdir" ]; then
            if mkdir -p "$cdir"; then
                printf '%s\n' "${cdir#"$cdest"/}" >> "$cdirmap"
            else
                warn "could not create $cdir"
                continue
            fi
        fi
        if [ -L "$cdst" ]; then rm -f "$cdst"; fi
        if cp -a "$csrc" "$cdst"; then
            printf '%s\n' "$crel" >> "$clist"
        else
            warn "could not copy $crel"
        fi
    done < "$CACHE/payload.list"
    rm -f "$CACHE/payload.list"
}

# Moves the multiarch part of a staged tree into the runtime and returns what is left.
merge_libs_into_runtime() {
    mtree=$1
    mfound=0
    find "$mtree" \( -type f -o -type l \) -print > "$CACHE/libs.list"
    while IFS= read -r msrc; do
        mrel=${msrc#"$mtree"/}
        case $mrel in
        usr/lib/aarch64-linux-gnu/*) mflat=${mrel#usr/lib/aarch64-linux-gnu/} ;;
        lib/aarch64-linux-gnu/*) mflat=${mrel#lib/aarch64-linux-gnu/} ;;
        *) continue ;;
        esac
        mfound=1
        mkdir -p "$(dirname "$RUNTIME/$mflat")"
        cp -a "$msrc" "$RUNTIME/$mflat" || warn "could not add $mrel"
        rm -f "$msrc"
    done < "$CACHE/libs.list"
    rm -f "$CACHE/libs.list"
    printf '%s\n' "$mfound"
}

app_binary() {
    aroot=$1
    adesktop=
    for candidate in "$aroot"/usr/share/applications/*.desktop; do
        if [ -f "$candidate" ]; then adesktop=$candidate; break; fi
    done
    if [ -n "$adesktop" ]; then
        aexec=$(sed -n 's/^Exec=//p' "$adesktop" 2>/dev/null | head -n1 | awk '{ print $1 }')
        case $aexec in
        /*)
            if [ -x "$aroot$aexec" ]; then printf '%s\n' "${aexec#/}"; return 0; fi
            ;;
        '')
            ;;
        *)
            for dir in usr/bin usr/local/bin usr/games usr/lib; do
                if [ -x "$aroot/$dir/$aexec" ]; then printf '%s\n' "$dir/$aexec"; return 0; fi
            done
            ;;
        esac
    fi
    for dir in usr/bin usr/local/bin opt usr/lib; do
        [ -d "$aroot/$dir" ] || continue
        found=$(find "$aroot/$dir" -maxdepth 3 -type f -perm -u+x 2>/dev/null | head -n1)
        if [ -n "$found" ]; then printf '%s\n' "${found#"$aroot"/}"; return 0; fi
    done
    return 1
}

is_electron() {
    [ -n "$(find "$1" -maxdepth 6 -name app.asar -print -quit 2>/dev/null)" ] ||
        [ -n "$(find "$1" -maxdepth 6 -name chrome-sandbox -print -quit 2>/dev/null)" ]
}

is_qt() {
    [ -n "$(find "$1" -maxdepth 5 -name 'libQt6Core.so*' -print -quit 2>/dev/null)" ] ||
        [ -x "$RUNTIME/libQt6Core.so.6" ]
}

write_launcher() {
    # The single-quoted printf strings below are the launcher's own text, expanded later.
    # shellcheck disable=SC2016
    lname=$1
    lroot=$2
    lmain=$3
    lelectron=$4
    lqt=$5
    lwrapper=$BIN_DIR/$lname
    if [ -e "$lwrapper" ] && ! grep -q "$MARKER" "$lwrapper" 2>/dev/null; then
        die "$lwrapper exists and is not managed by the shelf; refusing to replace it"
    fi
    mkdir -p "$BIN_DIR"
    # The single-quoted strings are the launcher text; nothing expands here.
    # shellcheck disable=SC2016
    {
        printf '#!/bin/sh\n'
        printf '# %s\n' "$MARKER"
        printf 'unset LD_PRELOAD LD_LIBRARY_PATH LD_AUDIT\n'
        printf 'ROOT="%s"\n' "$lroot"
        printf 'RT="%s"\n' "$RUNTIME"
        printf 'XDG_DATA_DIRS="$ROOT/usr/share:/usr/local/share:/usr/share"\n'
        printf 'export XDG_DATA_DIRS\n'
        if [ "$lqt" = 1 ]; then
            printf 'QT_QPA_PLATFORM="${QT_QPA_PLATFORM:-wayland}"\n'
            printf 'export QT_QPA_PLATFORM\n'
        fi
        if [ "$lelectron" = 1 ]; then
            printf 'ELECTRON_OZONE_PLATFORM_HINT="${ELECTRON_OZONE_PLATFORM_HINT:-wayland}"\n'
            printf 'export ELECTRON_OZONE_PLATFORM_HINT\n'
        fi
        if [ "$lfirefox" = 1 ]; then
            printf 'export MOZ_ENABLE_WAYLAND=1\n'
            printf 'export MOZ_DISABLE_CONTENT_SANDBOX=1\n'
        fi
        printf 'if [ -z "${WAYLAND_DISPLAY:-}" ]; then\n'
        printf '    XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp/xdg-runtime}"\n'
        printf '    export XDG_RUNTIME_DIR\n'
        printf '    [ -S "$XDG_RUNTIME_DIR/wayland-0" ] && export WAYLAND_DISPLAY=wayland-0\n'
        printf 'fi\n'
        if [ "$lelectron" = 1 ]; then
            # No seccomp and no user namespaces on LinPad, so Chromium's sandbox cannot start.
            printf 'exec "$RT/ld-linux-aarch64.so.1" --library-path "$RT:$ROOT/lib" \\\n'
            printf '    "$ROOT/%s" --no-sandbox "$@"\n' "$lmain"
        elif [ "$lfirefox" = 1 ]; then
            printf 'exec "$RT/ld-linux-aarch64.so.1" --library-path "$RT:$ROOT/lib" \\\n'
            printf '    "$ROOT/%s" --profile "%s" "$@"\n' "$lmain" "$FIREFOX_PROFILE"
        else
            printf 'exec "$RT/ld-linux-aarch64.so.1" --library-path "$RT:$ROOT/lib" "$ROOT/%s" "$@"\n' "$lmain"
        fi
    } > "$lwrapper"
    chmod 755 "$lwrapper"
}

# $1 = base name for the .desktop file, $2 = launcher name, $3 = display name.
# The file name may get a suffix to avoid clobbering an unrelated entry, but Exec always
# points at the launcher that exists.
write_desktop() {
    dbase=$1
    dexec=$2
    dtitle=$3
    dfile=$DESKTOP_DIR/$dbase.desktop
    if [ -e "$dfile" ] && ! grep -q "$MARKER" "$dfile" 2>/dev/null; then
        dfile=$DESKTOP_DIR/$dbase-linpad.desktop
    fi
    mkdir -p "$DESKTOP_DIR"
    {
        printf '[Desktop Entry]\n'
        printf 'Type=Application\n'
        printf 'Name=%s\n' "$dtitle"
        printf 'Comment=%s\n' "$MARKER"
        printf 'Exec=%s %%U\n' "$BIN_DIR/$dexec"
        printf 'TryExec=%s\n' "$BIN_DIR/$dexec"
        printf 'Icon=%s\n' "$dexec"
        printf 'Terminal=false\n'
        printf 'Categories=Utility;\n'
        printf 'MimeType=text/html;x-scheme-handler/http;x-scheme-handler/https;\n'
    } > "$dfile"
    printf '%s\n' "$dfile"
}

copy_icon() {
    iname=$1
    iroot=$2
    for size in 256 128 64 48 32; do
        candidate="$iroot/usr/share/icons/hicolor/${size}x${size}/apps/$iname.png"
        if [ -f "$candidate" ]; then
            dir=$ICON_ROOT/${size}x${size}/apps
            mkdir -p "$dir"
            cp "$candidate" "$dir/$iname.png"
            printf '%s\n' "$dir/$iname.png"
            return 0
        fi
    done
    if [ -f "$iroot/usr/share/pixmaps/$iname.png" ]; then
        dir=$ICON_ROOT/48x48/apps
        mkdir -p "$dir"
        cp "$iroot/usr/share/pixmaps/$iname.png" "$dir/$iname.png"
        printf '%s\n' "$dir/$iname.png"
    fi
    return 0
}

x11_rule() {
    rules=/etc/ishwl/apps
    mkdir -p "$(dirname "$rules")"
    grep -q "^$1 x11\$" "$rules" 2>/dev/null || printf '%s x11\n' "$1" >> "$rules"
    printf '%s\n' "$rules"
}

refresh_icons() {
    if command -v ish-apply-style >/dev/null 2>&1; then
        ish-apply-style --cache-only >/dev/null 2>&1 || true
    fi
}

# ------------------------------------------------------------------ state

state_init() {
    mkdir -p "$STATE/$1"
    : > "$STATE/$1/files"
    : > "$STATE/$1/dirs"
    : > "$STATE/$1/extras"
    : > "$STATE/$1/binary"
}

record_extra() {
    printf '%s\n' "$1" >> "$STATE/$NAME_APP/extras"
}

installed_names() {
    [ -d "$STATE" ] || return 0
    for dir in "$STATE"/*/; do
        [ -d "$dir" ] || continue
        basename "$dir"
    done
}

# ------------------------------------------------------------------ install

stage_deb() {
    sfile=$1
    stree=$CACHE/work/tree
    rm -rf "$CACHE/work"
    mkdir -p "$stree"
    bsdtar -xf "$sfile" -C "$CACHE/work" || die "cannot read $sfile as a .deb"
    sdata=
    for candidate in "$CACHE/work"/data.tar.*; do
        if [ -f "$candidate" ]; then sdata=$candidate; fi
    done
    [ -n "$sdata" ] || die "$sfile has no data.tar payload"
    bsdtar -xf "$sdata" -C "$stree" || die "cannot unpack $sdata"
    printf '%s\n' "$stree"
}

control_field() {
    cname=$1
    tmp=$CACHE/control
    rm -rf "$tmp"
    mkdir -p "$tmp"
    for member in "$CACHE/work"/control.tar.*; do
        if [ -f "$member" ]; then
            bsdtar -xf "$member" -C "$tmp" 2>/dev/null || true
        fi
    done
    if [ -f "$tmp/control" ]; then
        sed -n "s/^$cname: //p" "$tmp/control" | head -n1
    fi
    rm -rf "$tmp"
}

finish_install() {
    fname=$1
    fver=$2
    NAME_APP=$fname
    froot=$APPS/$fname/root
    freal=$(app_binary "$froot") || die "no executable found in the payload"
    printf '%s\n' "$froot/$freal" > "$STATE/$fname/binary"
    electron=0
    qt=0
    firefox=0
    if is_electron "$froot"; then electron=1; fi
    if is_qt "$froot"; then qt=1; fi
    if is_firefox_name "$fname" || is_firefox_name "$(basename "$freal")"; then
        firefox=1
        firefox_profile
        firefox_scale
    fi
    write_launcher "$fname" "$froot" "$freal" "$electron" "$qt" "$firefox"
    record_extra "$BIN_DIR/$fname"

    dfile=$(write_desktop "$fname" "$fname" "$fname")
    record_extra "$dfile"
    ifile=$(copy_icon "$fname" "$froot")
    if [ -n "$ifile" ]; then record_extra "$ifile"; fi
    if [ "$WANT_X11" = 1 ]; then
        xfile=$(x11_rule "$fname")
        record_extra "$xfile"
    fi
    if [ "$WANT_SYSTEM_DATA" = 1 ] && [ -d "$froot/usr/share" ]; then
        step "copying the app's /usr/share data into the system (as asked)"
        find "$froot/usr/share" \( -type f -o -type l \) -print > "$CACHE/share.list"
        while IFS= read -r ssrc; do
            srel=${ssrc#"$froot"/}
            sdst=/$srel
            if [ -e "$sdst" ] || [ -L "$sdst" ]; then
                if apk_owns "$sdst"; then
                    warn "kept the Alpine file $sdst"
                    continue
                fi
                if [ -L "$sdst" ]; then rm -f "$sdst"; fi
            fi
            mkdir -p "$(dirname "$sdst")"
            if cp -a "$ssrc" "$sdst"; then record_extra "$sdst"; fi
        done < "$CACHE/share.list"
        rm -f "$CACHE/share.list"
    fi
    refresh_icons
    verify_one "$fname" || warn "verify reported gaps; the app may still start"
    step "installed $fname $fver"
    printf '  run:     %s\n' "$fname"
    printf '  payload: %s (%s)\n' "$froot" "$(du -sh "$froot" 2>/dev/null | cut -f1)"
    printf '  remove:  linpad-shelf remove %s\n' "$fname"
}

install_from_file() {
    ifile=$1
    fslug=$2
    tree=$(stage_deb "$ifile")
    ipkg=$(control_field Package)
    iver=$(control_field Version)
    idep=$(control_field Depends)
    if [ -z "$fslug" ]; then
        fslug=$(slugify "${ipkg:-$(basename "$ifile" .deb)}")
    fi
    fslug=$(slugify "$fslug")
    valid_name "$fslug" || die "bad app name: $fslug (pass --name)"
    [ ! -e "$APPS/$fslug" ] || die "$fslug is already installed (remove it first)"

    # The libraries this package depends on are Debian packages: fetch them once into the
    # shared runtime so the app finds its sonames.
    libdeps=$(printf '%s' "$idep" | tr ',' '\n' |
        sed -n 's/^ *\(lib[A-Za-z0-9.+-]*\).*/\1/p' | tr '\n' ' ')
    if [ -n "$libdeps" ] && ! runtime_ok; then
        runtime_ensure
    fi
    if [ -n "$libdeps" ]; then
        step "adding the app's Debian library dependencies"
        # shellcheck disable=SC2086
        runtime_fetch $libdeps || warn "some libraries could not be added; verify will say which"
    fi
    runtime_ensure

    state_init "$fslug"
    printf '%s\n' "${iver:-}" > "$STATE/$fslug/version"
    printf '%s\n' "${ipkg:-}" > "$STATE/$fslug/package"
    printf '%s\n' "$ifile" > "$STATE/$fslug/source"
    mkdir -p "$APPS/$fslug/root" "$APPS/$fslug/lib"
    copy_app_tree "$tree" "$APPS/$fslug/root" "$STATE/$fslug/files" "$STATE/$fslug/dirs"
    finish_install "$fslug" "${iver:-$ipkg}"
}

install_from_name() {
    npkg=$1
    valid_name "$(slugify "$npkg")" || die "bad package name: $npkg"
    ensure_tools
    runtime_ensure
    step "resolving $npkg from Debian $DEBIAN_SUITE"
    stage=$CACHE/work/tree
    rm -rf "$CACHE/work"
    mkdir -p "$stage"
    node "$DEBFETCH" --suite "$DEBIAN_SUITE" --mirror "$DEBIAN_MIRROR" \
        --cache "$CACHE/debs" --dest "$stage" "$npkg" >&2 ||
        die "Debian has no package called $npkg (or the network failed)"
    nslug=$(slugify "${NAME:-$npkg}")
    valid_name "$nslug" || die "bad app name: $nslug"
    [ ! -e "$APPS/$nslug" ] || die "$nslug is already installed (remove it first)"

    # debfetch writes "<package> <version>" lines next to the unpacked tree.
    nver=
    if [ -f "$stage/.packages" ]; then
        nver=$(awk -v p="$npkg" '$1 == p { print $2; exit }' "$stage/.packages")
    fi
    merge_libs_into_runtime "$stage" >/dev/null

    state_init "$nslug"
    printf '%s\n' "${nver:-}" > "$STATE/$nslug/version"
    printf '%s\n' "$npkg" > "$STATE/$nslug/package"
    printf '%s\n' "debian:$npkg" > "$STATE/$nslug/source"
    mkdir -p "$APPS/$nslug/root" "$APPS/$nslug/lib"
    copy_app_tree "$stage" "$APPS/$nslug/root" "$STATE/$nslug/files" "$STATE/$nslug/dirs"
    finish_install "$nslug" "${nver:-$npkg}"
}

install() {
    case $TARGET in
    http://* | https://*)
        ensure_tools
        mkdir -p "$CACHE/debs"
        file=$CACHE/debs/$(basename "$TARGET")
        if [ ! -s "$file" ]; then
            step "downloading $(basename "$TARGET")"
            curl -fL --retry 3 -o "$file.part" "$TARGET" || die "download failed"
            mv -f "$file.part" "$file"
        fi
        install_from_file "$file" "$NAME"
        ;;
    *.deb) install_from_file "$TARGET" "$NAME" ;;
    *://*) die "only .deb files can be installed from a URL" ;;
    *) install_from_name "$TARGET" ;;
    esac
}

# ------------------------------------------------------------------ verify/remove

verify_one() {
    name=$1
    [ -d "$STATE/$name" ] || return 1
    main=$(sed -n '1p' "$STATE/$name/binary" 2>/dev/null || true)
    if [ -z "$main" ] || [ ! -x "$main" ]; then
        warn "$name: no executable recorded"
        return 1
    fi
    missing=$(env -u LD_PRELOAD -u LD_LIBRARY_PATH -u LD_AUDIT \
        "$RUNTIME/ld-linux-aarch64.so.1" --library-path "$RUNTIME:$APPS/$name/lib" \
        --list "$main" 2>&1 | awk '/not found/ { print $1 }')
    if [ -n "$missing" ]; then
        warn "$name: missing $(printf '%s' "$missing" | tr '\n' ' ')"
        return 1
    fi
    printf '%s: every library resolves\n' "$name"
    return 0
}

cmd_verify() {
    if [ $# -gt 0 ]; then
        verify_one "$1"
        return
    fi
    for name in $(installed_names); do
        verify_one "$name" || true
    done
}

cmd_remove() {
    RemoveName=$1
    valid_name "$RemoveName" || die "invalid name: $RemoveName"
    [ -d "$STATE/$RemoveName" ] || die "nothing installed as $RemoveName"
    step "removing $RemoveName"
    if [ -f "$STATE/$RemoveName/extras" ]; then
        while IFS= read -r extra; do
            [ -n "$extra" ] || continue
            rm -f "$extra"
        done < "$STATE/$RemoveName/extras"
    fi
    rm -rf "${APPS:?}/$RemoveName"
    rm -rf "${STATE:?}/$RemoveName"
    if [ "$RemoveName" = "$FIREFOX_NAME" ]; then
        default_browser_restore
    fi
    refresh_icons
    printf 'removed %s (the shared runtime is kept)\n' "$RemoveName"
}

json_escape() {
    printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}

# Machine-readable inventory for the desktop UI (Apps/Shelf/ShelfApp.swift).
cmd_list_json() {
    printf '{"apps":['
    first=1
    for name in $(installed_names); do
        jver=$(cat "$STATE/$name/version" 2>/dev/null || printf '')
        jsize=$(du -sh "$APPS/$name" 2>/dev/null | cut -f1)
        jsrc=$(cat "$STATE/$name/source" 2>/dev/null || printf '')
        [ "$first" = 1 ] || printf ','
        first=0
        printf '{"name":"%s","version":"%s","size":"%s","source":"%s"}' \
            "$(json_escape "$name")" "$(json_escape "$jver")" "$(json_escape "$jsize")" "$(json_escape "$jsrc")"
    done
    printf ']}\n'
}

cmd_list() {
    found=0
    for name in $(installed_names); do
        found=1
        size=$(du -sh "$APPS/$name" 2>/dev/null | cut -f1)
        ver=$(cat "$STATE/$name/version" 2>/dev/null || printf '?')
        printf '%-24s %-20s %s\n' "$name" "${ver:-?}" "${size:-?}"
    done
    [ "$found" = 1 ] || printf 'nothing installed by linpad-shelf\n'
}

cmd_doctor() {
    printf 'linpad-shelf on %s, Alpine %s\n' "$(uname -m)" "$(cat /etc/alpine-release 2>/dev/null || echo '?')"
    for tool in curl bsdtar node xzcat apk ish-apply-style; do
        printf '%-16s %s\n' "$tool:" "$(command -v "$tool" || echo missing)"
    done
    printf 'debfetch:        %s\n' "$([ -f "$DEBFETCH" ] && echo "$DEBFETCH" || echo missing)"
    if runtime_ok; then
        printf 'runtime:         %s (%s)\n' "$RUNTIME" "$(du -sh "$RUNTIME" 2>/dev/null | cut -f1)"
    else
        printf 'runtime:         not built yet\n'
    fi
    printf '\napps:\n'
    cmd_list
    printf '\npaths: %s  %s  %s\n' "$APPS" "$STATE" "$CACHE"
}

selftest() {
    printf 'classify usr/lib/aarch64-linux-gnu/libc.so.6 -> %s\n' "$(classify_path usr/lib/aarch64-linux-gnu/libc.so.6)"
    printf 'classify usr/bin/app                      -> %s\n' "$(classify_path usr/bin/app)"
    printf 'classify lib/aarch64-linux-gnu/x.so       -> %s\n' "$(classify_path lib/aarch64-linux-gnu/x.so)"
    for n in "My App 2.0" "KeePassXC" ".." "a/b" "-weird"; do
        s=$(slugify "$n")
        if valid_name "$s"; then v=ok; else v=REJECT; fi
        printf 'slug(%-14s) = %-20s %s\n' "$n" "$s" "$v"
    done
}

# ------------------------------------------------------------------ main

if [ $# -eq 0 ]; then usage; fi
case $1 in
help | --help | -h) usage ;;
--selftest) MODE=selftest; shift ;;
migrate-firefox | migrate_firefox) MODE=migrate-firefox; shift ;;
install | remove | list | verify | runtime | doctor | selftest)
    MODE=$1
    shift
    ;;
*) MODE=install ;;
esac

while [ $# -gt 0 ]; do
    case $1 in
    --name)
        [ $# -ge 2 ] || die "--name needs a value"
        NAME=$2
        shift 2
        ;;
    --x11)
        WANT_X11=1
        shift
        ;;
    --system-data)
        WANT_SYSTEM_DATA=1
        shift
        ;;
    --json)
        WANT_JSON=1
        shift
        ;;
    -h | --help) usage ;;
    -*) die "unknown option: $1" ;;
    *)
        if [ -z "$TARGET" ]; then
            TARGET=$1
        else
            EXTRA="$EXTRA $1"
        fi
        shift
        ;;
    esac
done

case $MODE in
selftest) selftest; exit 0 ;;
esac

need_root
mkdir -p "$CACHE"

# shellcheck disable=SC2086  # $EXTRA is a deliberate word list of sub-arguments
case $MODE in
list)
    if [ "$WANT_JSON" = 1 ]; then cmd_list_json; else cmd_list; fi
    ;;
verify) cmd_verify ${TARGET:+"$TARGET"} ;;
runtime) cmd_runtime ${TARGET:+"$TARGET"} ${EXTRA:-} ;;
doctor) cmd_doctor ;;
migrate-firefox) cmd_migrate_firefox ;;
remove)
    [ -n "$TARGET" ] || die "remove needs a name"
    cmd_remove "$TARGET"
    ;;
install)
    [ -n "$TARGET" ] || die "install needs a Debian package name, a .deb file or a URL"
    install
    ;;
esac
"""##
    // MARK: linpad-get
    static let linpadGet = ##"""
#!/bin/sh
# linpad-get — install Linux software that is not an Alpine package.
#
# LinPad's Store and Packages app cover what apk can install (Alpine main + community).
# Everything else — a .deb from a project's GitHub release, an AppImage, a binary tarball,
# an .rpm — has no install path on the iPad. This script adds one, on the device, with no
# app rebuild:
#
#   linpad-get install gimp                     # any apk package (delegates to apk)
#   linpad-get install ./app.deb                # Debian package (aarch64, glibc)
#   linpad-get install https://host/app.deb     # downloaded first
#   linpad-get install ./App.AppImage           # unpacked, no FUSE needed
#   linpad-get install ./tool.tar.xz            # unpacked into /opt/linpad-get
#   linpad-get install ./pkg.rpm                # RPM payload via libarchive
#   linpad-get remove <name>                    # undo what it installed
#   linpad-get list                             # what it installed
#   linpad-get island                           # build/repair the glibc island
#   linpad-get doctor                           # check the environment
#
# Options: --name NAME, --x11 (launch through Xwayland), --desktop / --no-desktop.
#
# How it works: Alpine is musl and almost every published aarch64 Linux binary is glibc.
# The glibc libraries live in the "island" (/usr/lib/aarch64-linux-gnu plus the loader
# /lib/ld-linux-aarch64.so.1) that VS Code and Wine already use, and Debian's loader
# searches its multiarch directory by default, so a glibc program finds them with no
# LD_LIBRARY_PATH. What a glibc program must not inherit is the desktop session's musl
# LD_PRELOAD (or an LD_LIBRARY_PATH pointing at musl libraries), so every glibc program
# gets a small wrapper in /usr/local/bin. Files that apk owns are never overwritten.
#
# Limits this script cannot lift: x86_64-only Linux builds (the emulator executes aarch64
# ELF only), FUSE (AppImages run unpacked), user namespaces and systemd (so no Flatpak or
# Snap), and WebKitGTK apps (blocked in the emulator's socket layer).
set -eu

CACHE=/var/cache/linpad-get
STATE=/var/lib/linpad-get
OPT=/opt/linpad-get
BIN=/usr/local/bin
DESKTOP_DIR=/usr/share/applications
ICON_DIR=/usr/share/icons/hicolor/256x256/apps
MULTIARCH=/usr/lib/aarch64-linux-gnu
LOADER=/lib/ld-linux-aarch64.so.1
DEBFETCH=${DEBFETCH:-/usr/local/share/devtools/debfetch.mjs}
DEBIAN_SUITE=${DEBIAN_SUITE:-trixie}
MARKER="installed by linpad-get"

# Debian trixie arm64 library packages that between them cover a normal desktop app:
# glibc, the C++ runtime, GTK 3 and 4, the X11 and Wayland libraries a GUI links,
# audio, secrets and tray. debfetch follows their own NEEDED closure from there. Every
# name here was checked against trixie's Packages index for arm64.
BASE_LIBS="libc6 libgcc-s1 libstdc++6 libglib2.0-0t64 libgtk-3-0t64 libgtk-4-1
libgdk-pixbuf-2.0-0 libpango-1.0-0 libcairo2 libharfbuzz0b libepoxy0 libfontconfig1
libfreetype6 libx11-6 libxcb1 libxext6 libxrender1 libxi6 libxtst6 libxcursor1
libxrandr2 libxfixes3 libxcomposite1 libxdamage1 libxshmfence1 libxkbcommon0
libxkbcommon-x11-0 libwayland-client0 libwayland-cursor0 libwayland-egl1 libgbm1
libdrm2 libegl1 libgl1 libvulkan1 libdbus-1-3 libasound2t64 libpulse0 libnss3
libnspr4 libatk1.0-0t64 libatspi2.0-0t64 libatk-bridge2.0-0t64 libcups2t64
libexpat1 libudev1 libsecret-1-0"

MODE=
NAME=
WANT_DESKTOP=auto
WANT_X11=0
TARGET=
EXTRAS=

log() { printf '==> %s\n' "$*" >&2; }
warn() { printf 'linpad-get: %s\n' "$*" >&2; }
die() { printf 'linpad-get: %s\n' "$*" >&2; exit 1; }

usage() {
    cat >&2 <<'EOF'
linpad-get — install Linux software that is not an Alpine package.

  linpad-get install <apk-name>          any package in Alpine's repositories
  linpad-get install <file|url>.deb      Debian package (aarch64, glibc)
  linpad-get install <file|url>.AppImage
  linpad-get install <file|url>.tar.{gz,xz,bz2,zst}
  linpad-get install <file|url>.rpm
  linpad-get remove <name>               undo an install
  linpad-get list                        what this tool installed
  linpad-get island                      build or repair the glibc library island
  linpad-get doctor                      environment check

Options: --name NAME, --x11, --desktop, --no-desktop.

Cannot work on LinPad (kernel limits, not packaging): Flatpak, Snap, Docker,
FUSE mounts, x86_64 Linux binaries, WebKitGTK apps.
EOF
    exit 0
}

need_root() {
    [ "$(id -u)" = 0 ] || die "run this as root (the LinPad terminal is root by default)"
}

# A name that is safe to use as a path component and as an rm -rf target.
valid_name() {
    case $1 in
    '' | . | ..) return 1 ;;
    *[!A-Za-z0-9._-]*) return 1 ;;
    esac
    return 0
}

slugify() {
    printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9._-' '-' |
        sed -e 's/-\{2,\}/-/g' -e 's/^-//' -e 's/-$//'
}

apk_owns() {
    apk info -W "$1" 2>/dev/null | grep -q 'is owned by'
}

ensure_tools() {
    missing=
    command -v curl >/dev/null 2>&1 || missing="$missing curl"
    command -v bsdtar >/dev/null 2>&1 || missing="$missing libarchive-tools"
    command -v node >/dev/null 2>&1 || missing="$missing nodejs"
    # debfetch.mjs pipes payloads through these.
    command -v xzcat >/dev/null 2>&1 || missing="$missing xz"
    command -v zstdcat >/dev/null 2>&1 || missing="$missing zstd"
    if [ -n "$missing" ]; then
        log "installing helper packages:$missing"
        # shellcheck disable=SC2086  # deliberate: the list is a word list
        apk add -q --no-progress $missing >/dev/null || die "apk add failed:$missing"
    fi
}

# --------------------------------------------------------------------- ELF classification

is_elf() {
    [ -f "$1" ] && [ "$(dd if="$1" bs=1 count=4 2>/dev/null | od -An -t x1 | tr -d ' \n')" = 7f454c46 ]
}

# e_machine at offset 18 is 0xB7 for aarch64 (little endian: b7 00).
is_aarch64_elf() {
    is_elf "$1" || return 1
    [ "$(dd if="$1" bs=1 skip=18 count=1 2>/dev/null | od -An -t x1 | tr -d ' \n')" = b7 ]
}

# Debian's loader can only execute a glibc aarch64 binary; a musl or static binary fails
# here even though it may contain the string "ld-linux-aarch64" somewhere.
loads_as_glibc() {
    is_aarch64_elf "$1" || return 1
    [ -x "$LOADER" ] || return 1
    env -u LD_PRELOAD -u LD_LIBRARY_PATH -u LD_AUDIT "$LOADER" --list "$1" >/dev/null 2>&1
}

missing_libs() {
    env -u LD_PRELOAD -u LD_LIBRARY_PATH -u LD_AUDIT "$LOADER" --list "$1" 2>&1 |
        awk '/not found/ { print $1 }'
}

report_missing() {
    mmiss=$(missing_libs "$2" || true)
    if [ -n "$mmiss" ]; then
        warn "$1 still needs: $(printf '%s' "$mmiss" | tr '\n' ' ')"
        warn "those come from more Debian packages; devtools/install-vscode.sh lists the"
        warn "ones VS Code needs, and a missing one can be added to BASE_LIBS in this script."
    fi
}

# --------------------------------------------------------------------- glibc island

island_ok() {
    [ -x "$LOADER" ] && [ -e "$MULTIARCH/libc.so.6" ] && [ -e "$MULTIARCH/ld-linux-aarch64.so.1" ]
}

island_ensure() {
    if island_ok; then
        return 0
    fi
    [ -f "$DEBFETCH" ] || die "$DEBFETCH is missing; this build has no glibc island helper"
    ensure_tools
    log "building the glibc island from Debian $DEBIAN_SUITE (one-time, a few hundred MB)"
    stage=$CACHE/island
    rm -rf "$stage" "$MULTIARCH.new"
    mkdir -p "$stage" "$MULTIARCH.new"
    # shellcheck disable=SC2086  # deliberate: the package list
    node "$DEBFETCH" --suite "$DEBIAN_SUITE" --cache "$CACHE/debs" --dest "$stage" $BASE_LIBS ||
        die "could not fetch the glibc libraries (offline?)"
    if [ -d "$stage/usr/lib/aarch64-linux-gnu" ]; then
        cp -a "$stage/usr/lib/aarch64-linux-gnu/." "$MULTIARCH.new/" || die "could not stage the island"
    fi
    if [ -d "$stage/lib/aarch64-linux-gnu" ]; then
        cp -a "$stage/lib/aarch64-linux-gnu/." "$MULTIARCH.new/" || die "could not stage the island"
    fi
    # Debian's own symlinks are absolute ("/lib/aarch64-linux-gnu/..."), which dangles
    # here because every library lands in this one directory. Point them at their
    # neighbour instead.
    find "$MULTIARCH.new" -type l -print > "$CACHE/island.links"
    while IFS= read -r link; do
        ltarget=$(readlink "$link" 2>/dev/null || true)
        case $ltarget in
        /*) ln -sfn "$(basename "$ltarget")" "$link" ;;
        esac
    done < "$CACHE/island.links"
    rm -f "$CACHE/island.links"
    [ -e "$MULTIARCH.new/libc.so.6" ] || die "the fetched libraries have no libc.so.6"
    [ -e "$MULTIARCH.new/ld-linux-aarch64.so.1" ] || die "the fetched libraries have no loader"
    # Swap the directory instead of overwriting mapped libraries in place: a running
    # VS Code or Wine keeps its old inodes and the new island appears atomically.
    if [ -d "$MULTIARCH" ]; then
        mv "$MULTIARCH" "$MULTIARCH.old" || die "could not move the old island aside"
    fi
    mv "$MULTIARCH.new" "$MULTIARCH" || die "could not install the new island"
    rm -rf "$MULTIARCH.old"
    ln -sfn "$MULTIARCH/ld-linux-aarch64.so.1" "$LOADER"
    rm -rf "$stage"
    island_ok || die "the island still does not resolve after building it"
    log "glibc island ready: $MULTIARCH"
}

# --------------------------------------------------------------------- state helpers

state_init() {
    sname=$1
    mkdir -p "$STATE/$sname"
    : > "$STATE/$sname/files"
    : > "$STATE/$sname/dirs"
    : > "$STATE/$sname/extras"
    EXTRAS=$STATE/$sname/extras
}

record_extra() {
    [ -n "${EXTRAS:-}" ] || return 0
    printf '%s\n' "$1" >> "$EXTRAS"
}

# A glibc program must not inherit the session's musl preloads or library path.
write_glibc_launcher() {
    lname=$1
    lreal=$2
    case $lreal in
    *'"'* | *'$'* | *'`'* | *\\*)
        warn "$lreal has a character a launcher cannot carry safely; not wrapping it"
        return 0
        ;;
    esac
    lwrapper=$BIN/$lname
    if [ -e "$lwrapper" ]; then
        if ! grep -q "$MARKER" "$lwrapper" 2>/dev/null; then
            warn "$lwrapper exists and is not ours; not replacing it"
            return 0
        fi
        if ! grep -qF "exec \"$lreal\"" "$lwrapper" 2>/dev/null; then
            warn "$lwrapper belongs to another app and is being repointed at $lreal"
        fi
    fi
    mkdir -p "$BIN"
    {
        printf '#!/bin/sh\n'
        printf '# %s: %s\n' "$MARKER" "$lreal"
        printf 'unset LD_PRELOAD LD_LIBRARY_PATH LD_AUDIT\n'
        printf 'exec "%s" "$@"\n' "$lreal"
    } > "$lwrapper"
    chmod 755 "$lwrapper"
    record_extra "$lwrapper"
    log "launcher: $lwrapper -> $lreal"
}

write_desktop() {
    dname=$1
    dexec=$2
    dtitle=$3
    dfinal=$DESKTOP_DIR/$dname.desktop
    if [ -e "$dfinal" ]; then
        return 0
    fi
    mkdir -p "$DESKTOP_DIR"
    {
        printf '[Desktop Entry]\n'
        printf 'Type=Application\n'
        printf 'Name=%s\n' "$dtitle"
        printf 'Comment=%s\n' "$MARKER"
        printf 'Exec=%s\n' "$dexec"
        printf 'Icon=%s\n' "$dname"
        printf 'Terminal=false\n'
        printf 'Categories=Utility;\n'
    } > "$dfinal"
    record_extra "$dfinal"
    log "launcher entry: $dfinal"
}

refresh_icons() {
    if command -v ish-apply-style >/dev/null 2>&1; then
        ish-apply-style --cache-only >/dev/null 2>&1 || true
    fi
}

x11_rule() {
    xrules=/etc/ishwl/apps
    mkdir -p "$(dirname "$xrules")"
    grep -q "^$1 x11\$" "$xrules" 2>/dev/null || printf '%s x11\n' "$1" >> "$xrules"
    log "X11 launch rule added for $1"
}

# Copies an unpacked payload tree into /, never overwriting an apk-owned file or the
# glibc island, and records what it installed so `remove` can undo exactly that.
copy_payload() {
    ctree=$1
    clist=$2
    cdirs=$3
    find "$ctree" \( -type f -o -type l \) -print > "$CACHE/payload.list"
    while IFS= read -r csrc; do
        crel=${csrc#"$ctree"/}
        case $crel in
        usr/lib/aarch64-linux-gnu/* | lib/aarch64-linux-gnu/* | lib/ld-linux-aarch64.so.1)
            warn "kept the island file /$crel (a package must not replace glibc)"
            continue
            ;;
        esac
        cdst=/$crel
        if [ -e "$cdst" ] || [ -L "$cdst" ]; then
            if apk_owns "$cdst"; then
                warn "kept the Alpine file $cdst (the package's copy is not used)"
                continue
            fi
            # Never write through an existing symlink: replace the link itself.
            if [ -L "$cdst" ]; then
                rm -f "$cdst"
            fi
        fi
        cdir=$(dirname "$cdst")
        if [ ! -d "$cdir" ]; then
            if mkdir -p "$cdir"; then
                printf '%s\n' "${cdir#/}" >> "$cdirs"
            else
                warn "could not create $cdir"
                continue
            fi
        fi
        if cp -a "$csrc" "$cdst"; then
            printf '%s\n' "$crel" >> "$clist"
        else
            warn "could not copy $crel"
        fi
    done < "$CACHE/payload.list"
    rm -f "$CACHE/payload.list"
}

fetch() {
    fsrc=$1
    case $fsrc in
    http://* | https://* | ftp://*)
        ensure_tools
        mkdir -p "$CACHE"
        # A hash keeps two releases with the same file name apart.
        fhash=$(printf '%s' "$fsrc" | cksum | cut -d' ' -f1)
        fout=$CACHE/$fhash-$(basename "$fsrc")
        if [ ! -s "$fout" ]; then
            log "downloading $fsrc"
            rm -f "$fout.part"
            curl -fL --retry 3 -o "$fout.part" "$fsrc" || die "download failed: $fsrc"
            mv -f "$fout.part" "$fout" || die "could not keep the download"
        fi
        printf '%s\n' "$fout"
        ;;
    *)
        [ -f "$fsrc" ] || die "no such file: $fsrc"
        printf '%s\n' "$(cd "$(dirname "$fsrc")" && pwd)/$(basename "$fsrc")"
        ;;
    esac
}

# --------------------------------------------------------------------- apk

install_apk() {
    apkg=${TARGET#apk:}
    valid_name "$apkg" || die "not a package name: $apkg"
    log "apk add $apkg"
    apk add --no-progress "$apkg" || die "apk could not install $apkg"
    refresh_icons
}

# --------------------------------------------------------------------- .deb

deb_package_name() {
    for cfile in "$1"/control.tar.*; do
        [ -f "$cfile" ] || continue
        cout=$(bsdtar -xOf "$cfile" ./control 2>/dev/null || true)
        if [ -z "$cout" ]; then
            cout=$(bsdtar -xOf "$cfile" control 2>/dev/null || true)
        fi
        [ -n "$cout" ] || continue
        printf '%s' "$cout" | sed -n 's/^Package: //p' | head -n1
        return 0
    done
    return 0
}

install_deb() {
    dfile=$1
    ensure_tools
    dtmp=$CACHE/deb-work
    rm -rf "$dtmp"
    mkdir -p "$dtmp/tree"
    bsdtar -xf "$dfile" -C "$dtmp" || die "cannot unpack $dfile (is it a .deb?)"
    ddata=
    for dcand in "$dtmp"/data.tar.*; do
        if [ -f "$dcand" ]; then ddata=$dcand; fi
    done
    [ -n "$ddata" ] || die "$dfile has no data.tar payload"
    bsdtar -xf "$ddata" -C "$dtmp/tree" || die "cannot unpack $ddata"

    dpkgname=$(deb_package_name "$dtmp")
    dname=${NAME:-${dpkgname:-$(basename "$dfile" .deb)}}
    dname=$(slugify "$dname")
    valid_name "$dname" || die "the package name resolves to nothing usable; pass --name"
    state_init "$dname"
    printf '%s\n' deb > "$STATE/$dname/kind"
    printf '%s\n' "$dfile" > "$STATE/$dname/source"
    copy_payload "$dtmp/tree" "$STATE/$dname/files" "$STATE/$dname/dirs"

    # Every program the payload put in a bin directory is a candidate for a wrapper.
    island_ensure
    dprogs=$(grep -E '^(usr/bin/|usr/local/bin/|usr/sbin/|sbin/|opt/[^/]+/bin/)[^/]+$' \
        "$STATE/$dname/files" 2>/dev/null || true)
    # shellcheck disable=SC2086  # deliberate: one path per line
    for drel in $dprogs; do
        dpath=/$drel
        loads_as_glibc "$dpath" || continue
        dprog=$(basename "$drel")
        write_glibc_launcher "$dprog" "$dpath"
        report_missing "$dprog" "$dpath"
        if [ "$WANT_DESKTOP" != 0 ]; then
            write_desktop "$dprog" "$dprog" "$dprog"
        fi
        if [ "$WANT_X11" = 1 ]; then x11_rule "$dprog"; fi
    done
    rm -rf "$dtmp"
    refresh_icons
    log "installed $dname (files in $STATE/$dname/files)"
}

# --------------------------------------------------------------------- AppImage

install_appimage() {
    afile=$1
    ensure_tools
    atmp=$CACHE/appimage-work
    rm -rf "$atmp"
    mkdir -p "$atmp"
    # Run a copy, so the user's file is not chmod'ed behind their back.
    acopy=$CACHE/appimage-run
    cp "$afile" "$acopy"
    chmod 755 "$acopy"
    log "unpacking the AppImage (no FUSE needed)"
    if ! (cd "$atmp" && "$acopy" --appimage-extract >/dev/null 2>&1); then
        rm -f "$acopy"
        die "could not unpack $afile; a type-1 AppImage needs squashfs-tools"
    fi
    rm -f "$acopy"
    [ -d "$atmp/squashfs-root" ] || die "the AppImage produced no squashfs-root"
    aname=${NAME:-$(sed -n 's/^Name=//p' "$atmp"/squashfs-root/*.desktop 2>/dev/null | head -n1)}
    [ -n "$aname" ] || aname=$(basename "$afile" .AppImage)
    aslug=$(slugify "$aname")
    valid_name "$aslug" || die "the AppImage name resolves to nothing usable; pass --name"
    [ -x "$atmp/squashfs-root/AppRun" ] || die "this AppImage has no executable AppRun"
    adest=$OPT/$aslug
    rm -rf "$adest"
    mkdir -p "$OPT"
    mv "$atmp/squashfs-root" "$adest"
    state_init "$aslug"
    printf '%s\n' appimage > "$STATE/$aslug/kind"
    printf '%s\n' "$afile" > "$STATE/$aslug/source"

    mkdir -p "$BIN"
    # shellcheck disable=SC2016  # the single-quoted strings are the launcher's own text
    {
        printf '#!/bin/sh\n'
        printf '# %s: AppImage, unpacked into %s (the iPad has no FUSE).\n' "$MARKER" "$adest"
        printf 'unset LD_PRELOAD LD_LIBRARY_PATH LD_AUDIT\n'
        printf 'if [ -z "${WAYLAND_DISPLAY:-}" ]; then\n'
        printf '    XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp/xdg-runtime}"\n'
        printf '    export XDG_RUNTIME_DIR\n'
        printf '    [ -S "$XDG_RUNTIME_DIR/wayland-0" ] && export WAYLAND_DISPLAY=wayland-0\n'
        printf 'fi\n'
        printf 'exec "%s/AppRun" "$@"\n' "$adest"
    } > "$BIN/$aslug"
    chmod 755 "$BIN/$aslug"
    record_extra "$BIN/$aslug"

    mkdir -p "$DESKTOP_DIR" "$ICON_DIR"
    aentry=
    for acand in "$adest"/*.desktop; do
        if [ -f "$acand" ]; then aentry=$acand; fi
    done
    aicon=$(sed -n 's/^Icon=//p' "${aentry:-/dev/null}" 2>/dev/null | head -n1)
    if [ "$WANT_DESKTOP" != 0 ]; then
        if [ -n "$aentry" ]; then
            # Keep the app's own field code (%U/%F) and point Exec at the wrapper, so the
            # desktop can still pass file arguments.
            sed -e "s|^Exec=.*|Exec=$BIN/$aslug %U|" \
                -e "s|^TryExec=.*|TryExec=$BIN/$aslug|" \
                -e "s|^Icon=.*|Icon=$aslug|" \
                "$aentry" > "$DESKTOP_DIR/$aslug.desktop"
            record_extra "$DESKTOP_DIR/$aslug.desktop"
            log "launcher entry: $DESKTOP_DIR/$aslug.desktop"
        else
            write_desktop "$aslug" "$aslug" "$aname"
        fi
    fi
    aiconfile=
    if [ -n "${aicon:-}" ]; then
        for acand in "$adest/$aicon".png "$adest/$aicon".svg "$adest/$aicon".xpm; do
            if [ -f "$acand" ]; then aiconfile=$acand; break; fi
        done
    fi
    if [ -z "$aiconfile" ] && [ -e "$adest/.DirIcon" ]; then
        aiconfile=$adest/.DirIcon
    fi
    if [ -n "$aiconfile" ] && [ -f "$aiconfile" ]; then
        aext=${aiconfile##*.}
        cp -L "$aiconfile" "$ICON_DIR/$aslug.$aext" 2>/dev/null || true
    fi
    if [ "$WANT_X11" = 1 ]; then x11_rule "$aslug"; fi
    rm -rf "$atmp"
    refresh_icons
    log "installed $aname at $adest (run it as '$aslug')"
}

# --------------------------------------------------------------------- tarball / rpm

install_tree() {
    tfile=$1
    tkind=$2
    ensure_tools
    ttmp=$CACHE/tree-work
    rm -rf "$ttmp"
    mkdir -p "$ttmp"
    bsdtar -xf "$tfile" -C "$ttmp" || die "cannot unpack $tfile"
    tname=${NAME:-$(basename "$tfile" | sed -e 's/\.tar\..*$//' -e 's/\.tgz$//' -e 's/\.rpm$//')}
    tslug=$(slugify "$tname")
    valid_name "$tslug" || die "the archive name resolves to nothing usable; pass --name"
    state_init "$tslug"
    printf '%s\n' "$tkind" > "$STATE/$tslug/kind"
    printf '%s\n' "$tfile" > "$STATE/$tslug/source"
    tdest=

    if [ "$tkind" = rpm ]; then
        copy_payload "$ttmp" "$STATE/$tslug/files" "$STATE/$tslug/dirs"
        tdest=/
        tprogram=$(grep -E '^(usr/bin/|usr/local/bin/|opt/[^/]+/bin/)[^/]+$' \
            "$STATE/$tslug/files" 2>/dev/null | sed -n '1p' || true)
        if [ -n "$tprogram" ]; then tprogram=/$tprogram; fi
    else
        tdest=$OPT/$tslug
        rm -rf "$tdest"
        mkdir -p "$OPT"
        tentries=$(find "$ttmp" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l)
        if [ "$tentries" = 1 ]; then
            tfirst=$(find "$ttmp" -mindepth 1 -maxdepth 1 | head -n1)
            if [ -d "$tfirst" ]; then
                mv "$tfirst" "$tdest"
            else
                mkdir -p "$tdest"
                mv "$tfirst" "$tdest/"
            fi
        else
            mkdir -p "$tdest"
            cp -a "$ttmp/." "$tdest/"
        fi
        tprogram=
        for tcand in "$tdest/bin/$tslug" "$tdest/$tslug" "$tdest/AppRun"; do
            if [ -f "$tcand" ] && [ -x "$tcand" ]; then tprogram=$tcand; break; fi
        done
        if [ -z "$tprogram" ] && [ -d "$tdest/bin" ]; then
            tprogram=$(find "$tdest/bin" -maxdepth 1 -type f -perm -u+x 2>/dev/null | head -n1)
        fi
    fi

    if [ -z "${tprogram:-}" ] || [ ! -f "$tprogram" ]; then
        warn "no obvious program under $tdest; run it from there by hand"
        log "installed $tname at $tdest"
        return 0
    fi
    if loads_as_glibc "$tprogram"; then
        island_ensure
        write_glibc_launcher "$tslug" "$tprogram"
        report_missing "$tslug" "$tprogram"
    else
        mkdir -p "$BIN"
        {
            printf '#!/bin/sh\n'
            printf '# %s\n' "$MARKER"
            printf 'exec "%s" "$@"\n' "$tprogram"
        } > "$BIN/$tslug"
        chmod 755 "$BIN/$tslug"
        record_extra "$BIN/$tslug"
    fi
    if [ "$WANT_DESKTOP" != 0 ]; then
        write_desktop "$tslug" "$tslug" "$tname"
    fi
    if [ "$WANT_X11" = 1 ]; then x11_rule "$tslug"; fi
    refresh_icons
    log "installed $tname at $tdest (run it as '$tslug')"
}

# --------------------------------------------------------------------- remove / list

remove() {
    rname=$1
    valid_name "$rname" || die "invalid name: $rname"
    if [ ! -d "$STATE/$rname" ]; then
        die "nothing installed as '$rname' by linpad-get (an apk package is removed with: apk del $rname)"
    fi
    rkind=$(cat "$STATE/$rname/kind" 2>/dev/null || true)
    if [ -f "$STATE/$rname/files" ]; then
        while IFS= read -r rrel; do
            [ -n "$rrel" ] || continue
            rpath=/$rrel
            [ -e "$rpath" ] || [ -L "$rpath" ] || continue
            if apk_owns "$rpath"; then
                warn "kept $rpath: an apk package owns it now"
                continue
            fi
            rm -f "$rpath"
        done < "$STATE/$rname/files"
    fi
    if [ -f "$STATE/$rname/dirs" ]; then
        while IFS= read -r rdir; do
            [ -n "$rdir" ] || continue
            rmdir "/$rdir" 2>/dev/null || true
        done < "$STATE/$rname/dirs"
    fi
    if [ -f "$STATE/$rname/extras" ]; then
        while IFS= read -r rext; do
            [ -n "$rext" ] || continue
            rm -f "$rext"
        done < "$STATE/$rname/extras"
    fi
    case $rkind in
    appimage | tar) rm -rf "${OPT:?}/$rname" ;;
    esac
    rm -rf "${STATE:?}/$rname"
    refresh_icons
    log "removed $rname"
}

list_installed() {
    if [ ! -d "$STATE" ]; then
        echo "nothing installed by linpad-get"
        return 0
    fi
    lfound=0
    for ldir in "$STATE"/*/; do
        [ -d "$ldir" ] || continue
        lfound=1
        lbase=$(basename "$ldir")
        printf '%-24s %-9s %s\n' "$lbase" "$(cat "$ldir/kind" 2>/dev/null || echo '?')" \
            "$(cat "$ldir/source" 2>/dev/null || echo '-')"
    done
    [ "$lfound" = 1 ] || echo "nothing installed by linpad-get"
}

doctor() {
    printf 'linpad-get on %s, Alpine %s\n' "$(uname -m)" "$(cat /etc/alpine-release 2>/dev/null || echo '?')"
    printf 'memory allowance: %s MB\n' "$(awk '/^MemTotal:/ { print int($2 / 1024) }' /proc/meminfo)"
    for dtool in curl bsdtar node apk ish-apply-style; do
        printf '%-18s %s\n' "$dtool:" "$(command -v "$dtool" || echo missing)"
    done
    if island_ok; then
        printf 'glibc island:      present (%s)\n' "$(du -sh "$MULTIARCH" 2>/dev/null | cut -f1)"
    else
        printf 'glibc island:      absent (run: linpad-get island)\n'
    fi
    if [ -f "$DEBFETCH" ]; then printf 'debfetch:          %s\n' "$DEBFETCH"; else printf 'debfetch:          missing\n'; fi
    printf '\ninstalled by linpad-get:\n'
    list_installed
    printf '\nNot possible on LinPad (kernel limits, not packaging):\n'
    printf '  Flatpak, Snap, Docker, FUSE mounts, x86_64 Linux binaries, WebKitGTK apps\n'
}

# --------------------------------------------------------------------- main

if [ $# -eq 0 ]; then usage; fi
case $1 in
help | --help | -h) usage ;;
install | remove | list | doctor | island)
    MODE=$1
    shift
    ;;
*) MODE=install ;;
esac

while [ $# -gt 0 ]; do
    case $1 in
    --name)
        [ $# -ge 2 ] || die "--name needs a value"
        NAME=$2
        shift 2
        ;;
    --desktop)
        WANT_DESKTOP=1
        shift
        ;;
    --no-desktop)
        WANT_DESKTOP=0
        shift
        ;;
    --x11)
        WANT_X11=1
        shift
        ;;
    -h | --help) usage ;;
    -*) die "unknown option: $1" ;;
    *)
        [ -z "$TARGET" ] || die "only one target at a time (got '$TARGET' and '$1')"
        TARGET=$1
        shift
        ;;
    esac
done

need_root
mkdir -p "$CACHE" "$STATE"

case $MODE in
list) list_installed ;;
doctor) doctor ;;
island) island_ensure ;;
remove)
    [ -n "$TARGET" ] || die "remove needs a name (see: linpad-get list)"
    remove "$TARGET"
    ;;
install)
    [ -n "$TARGET" ] || die "install needs a package, a URL or a file"
    case $TARGET in
    apk:*) install_apk ;;
    *://* | /* | ./* | ../* | *.deb | *.rpm | *.AppImage)
        case $TARGET in
        *.AppImage | *.appimage) install_appimage "$(fetch "$TARGET")" ;;
        *)
            lfile=$(fetch "$TARGET")
            case $lfile in
            *.deb) install_deb "$lfile" ;;
            *.rpm) install_tree "$lfile" rpm ;;
            *.tar.gz | *.tgz | *.tar.xz | *.tar.bz2 | *.tar.zst | *.tar) install_tree "$lfile" tar ;;
            *) die "unsupported file type: $(basename "$lfile")" ;;
            esac
            ;;
        esac
        ;;
    *) install_apk ;;
    esac
    ;;
esac
"""##
    // MARK: m5-tune.sh
    static let m5TuneSh = ##"""
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
"""##
    /// Written in this order; every file is chmod'ed after writing.
    static var all: [(name: String, body: String, mode: Int)] {
        [
            ("linpad-shelf", linpadShelf, 0o755),
            ("linpad-get", linpadGet, 0o755),
            ("m5-tune.sh", m5TuneSh, 0o755),
        ]
    }
}
