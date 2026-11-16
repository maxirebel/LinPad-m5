import Foundation

/// The three performance profiles.
///
/// A profile is a named bundle of settings the app **already has**, so it never introduces
/// an unmeasured memory knob: it only picks values that are visible in Settings and can be
/// changed back from there. Anything a profile does not mention is left untouched, which is
/// why returning to Balanced does not undo a manual choice.
///
/// Deliberately absent until the S3 benchmark proves it: `ISH_JIT_PCACHE_MB`. A larger
/// persistent translation cache is plausible but unmeasured, and a smaller one makes the CPU
/// work harder, so neither belongs in a profile yet.
public enum PerformanceProfile: String, CaseIterable, Identifiable, Sendable {
    case balanced
    case performance
    case batterySaver

    public static let storageKey = "desktop.performanceProfile"
    public static let defaultProfile = PerformanceProfile.balanced

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .balanced:
            return "Balanced"
        case .performance:
            return "Performance"
        case .batterySaver:
            return "Battery Saver"
        }
    }

    public var summary: String {
        switch self {
        case .balanced:
            return "The defaults: the JIT picks its own code cache and the overlay follows your setting."
        case .performance:
            return "Fixes the code cache at 512 MB and turns the performance overlay on. More memory, more speed; applies at the next launch."
        case .batterySaver:
            return "Puts the code cache back on automatic and turns the overlay off. A smaller cache would make the CPU work harder, not less."
        }
    }

    /// Written into `fastMode.codeCacheMB`. Nil leaves whatever you picked.
    public var codeCacheMB: Int? {
        switch self {
        case .balanced:
            return nil
        case .performance:
            return 512
        case .batterySaver:
            return 0
        }
    }

    /// Written into `desktop.performanceOverlay`. Nil leaves your choice.
    public var showsPerformanceOverlay: Bool? {
        switch self {
        case .balanced:
            return nil
        case .performance:
            return true
        case .batterySaver:
            return false
        }
    }

    /// True when the profile writes a value the JIT reads at launch.
    public var requiresRelaunch: Bool { codeCacheMB != nil }

    /// Applies the profile to the shared defaults.
    public func apply(to defaults: UserDefaults = .standard) {
        if let mb = codeCacheMB {
            defaults.set(mb, forKey: FastModeModel.codeCacheKey)
        }
        if let overlay = showsPerformanceOverlay {
            defaults.set(overlay, forKey: DesktopSettings.performanceOverlayKey)
        }
        defaults.set(rawValue, forKey: Self.storageKey)
    }

    public static func stored(in defaults: UserDefaults = .standard) -> PerformanceProfile {
        guard let raw = defaults.string(forKey: storageKey),
              let profile = PerformanceProfile(rawValue: raw) else {
            return .defaultProfile
        }
        return profile
    }
}
