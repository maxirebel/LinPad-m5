import Foundation

/// Puts the bundled guest tools and the 12 GB profile into the Linux system, from the app.
///
/// Everything here used to need a terminal: copying `linpad-shelf` into the guest, the
/// session hook, and the Firefox prefs. This runs once per app version on the first
/// launch of the Debian Shelf, and is safe to run again at any time.
enum SetupService {
    static let versionMarker = "/var/lib/linpad-setup/version"
    static let binDirectory = "/usr/local/bin"
    static let sessionHook = "/etc/ishwl/session.d/25-m5.sh"
    static let firefoxPrefs = "/usr/lib/firefox-esr/browser/defaults/preferences/ish-tune.js"
    static let appScale = "/etc/ishwl/app-scale"

    enum Outcome: Equatable {
        case upToDate
        case installed
        case failed(String)
    }

    /// Writes the tools, the session hook and the Firefox tuning when the marker is stale.
    @MainActor
    static func ensureInstalled(on host: any LinuxHost) async -> Outcome {
        let current = await host.run("cat \(versionMarker) 2>/dev/null")
        if current.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == BundledScripts.version {
            return .upToDate
        }

        // The scripts first: the shell step below expects them to exist.
        for item in BundledScripts.all {
            var body = item.body
            if body.hasPrefix("\n") { body.removeFirst() }
            let path = "\(binDirectory)/\(item.name)"
            do {
                try await host.writeFile(path, data: Data(body.utf8))
            } catch {
                return .failed("could not write \(path): \(error.localizedDescription)")
            }
        }

        let script = """
        set -e
        chmod 755 \(binDirectory)/linpad-shelf \(binDirectory)/linpad-get \(binDirectory)/m5-tune.sh

        # Session hook: 15-lowmem.sh already set MALLOC_ARENA_MAX=2 for an 8 GB iPad, so
        # this has to assign unconditionally to win.
        mkdir -p /etc/ishwl/session.d /etc/profile.d
        cat > \(sessionHook) <<'HOOK'
        # LinPad setup (written by the app; safe to delete).
        export MALLOC_ARENA_MAX=6
        if [ -z "${NODE_OPTIONS:-}" ]; then
            export NODE_OPTIONS="--max-old-space-size=4096"
        fi
        HOOK
        chmod 644 \(sessionHook)
        cat > /etc/profile.d/99-linpad-m5.sh <<'PROFILE'
        if [ -z "${NODE_OPTIONS:-}" ]; then
            export NODE_OPTIONS="--max-old-space-size=4096"
        fi
        PROFILE
        chmod 644 /etc/profile.d/99-linpad-m5.sh

        # Firefox: one content process, no content sandbox (the emulator has no seccomp)
        # and caches sized for 12 GB. Appended once; the marker keeps it idempotent.
        if [ -f \(firefoxPrefs) ]; then
            if ! grep -q 'LinPad setup' \(firefoxPrefs) 2>/dev/null; then
                cat >> \(firefoxPrefs) <<'PREFS'

        // --- LinPad setup (written by the app) -------------------------------------
        pref("dom.ipc.processCount", 1);
        pref("fission.autostart", false);
        pref("security.sandbox.content.level", 0);
        pref("media.mediasource.webm.enabled", false);
        pref("media.av1.enabled", false);
        pref("layout.css.stylo-threads", 2);
        pref("javascript.options.mem.gc_max_helper_threads", 2);
        pref("browser.cache.memory.capacity", 65536);
        pref("image.mem.surfacecache.max_size_kb", 262144);
        pref("browser.tabs.unloadOnLowMemory", true);
        pref("toolkit.cosmeticAnimations.enabled", false);
        PREFS
            fi
        fi

        mkdir -p /etc/ishwl
        touch \(appScale)
        grep -q '^firefox-esr ' \(appScale) 2>/dev/null || echo 'firefox-esr 2 1' >> \(appScale)

        mkdir -p /var/lib/linpad-setup
        printf '%s\\n' '\(BundledScripts.version)' > \(versionMarker)
        echo "setup done"
        """

        let result = await host.run(script)
        guard result.succeeded else {
            let reason = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return .failed(reason.isEmpty ? "setup script failed (\(result.exitCode))" : reason)
        }
        return .installed
    }

    /// The Firefox 153 migration, streamed so the caller can show the log.
    @MainActor
    static func installFirefox(on host: any LinuxHost,
                               onOutput: @escaping @MainActor (String) -> Void) async -> Int32 {
        await host.stream("linpad-shelf migrate-firefox 2>&1", cwd: nil, onOutput: onOutput)
    }
}
