import Perception
import SwiftUI

/// Phase 4: the Debian shelf in the desktop.
///
/// Two jobs, both on top of the guest CLI (`personalize/linpad-shelf`):
///   - install a Debian application from a link or a guest path,
///   - list, open and remove what the shelf installed.
///
/// The app is deliberately thin: the guest tool owns the payload, the runtime and the
/// ledger, so this window never has to know where a package puts its files.
enum ShelfApp {
    static func descriptor() -> DesktopAppDescriptor {
        DesktopAppDescriptor(
            id: AppID.shelf, name: "Debian Shelf", symbol: "tray.full", category: .system,
            defaultSize: CGSize(width: 860, height: 620)
        ) { context in
            AnyView(ShelfAppView(context: context))
        }
    }
}

// MARK: - Wire format

/// One entry of `linpad-shelf list --json`.
struct ShelfEntry: Decodable, Identifiable, Hashable {
    var name: String
    var version: String?
    var size: String?
    var source: String?

    var id: String { name }

    var displayVersion: String {
        guard let version, !version.isEmpty else { return "unknown version" }
        return version
    }
}

private struct ShelfInventory: Decodable {
    var apps: [ShelfEntry]
}

// MARK: - Model

@MainActor
@Perceptible
final class ShelfModel {
    private static let logLimit = 64_000

    @PerceptionIgnored private let host: any LinuxHost
    @PerceptionIgnored private let desktop: any DesktopActions
    @PerceptionIgnored private var didStart = false
    @PerceptionIgnored private var job: Task<Void, Never>?

    private(set) var entries: [ShelfEntry] = []
    private(set) var isLoading = false
    private(set) var isInstalling = false
    private(set) var installLabel = ""
    private(set) var log = ""
    private(set) var errorMessage: String?
    private(set) var lastInstalled: String?

    /// The link field. Accepts an https .deb, a guest path, or a Debian package name.
    var link = ""
    var isLogVisible = false

    init(context: AppLaunchContext) {
        host = context.host
        desktop = context.desktop
    }

    func start() async {
        guard !didStart else { return }
        didStart = true
        await reload()
    }

    func reload() async {
        isLoading = true
        defer { isLoading = false }
        let result = await host.run("linpad-shelf list --json 2>/dev/null")
        guard result.succeeded, let data = result.stdout.data(using: .utf8) else {
            return
        }
        guard let inventory = try? JSONDecoder().decode(ShelfInventory.self, from: data) else {
            errorMessage = "The shelf returned something unexpected. Run `linpad-shelf doctor` in a terminal."
            return
        }
        entries = inventory.apps.sorted { $0.name < $1.name }
    }

    func install() async {
        let target = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty else { return }
        guard !isInstalling else { return }
        errorMessage = nil
        lastInstalled = nil
        isInstalling = true
        log = ""
        installLabel = target
        let device = guestName(for: target)
        let code = await host.stream(
            "linpad-shelf install \(ShellQuote.quote(target)) 2>&1", cwd: nil
        ) { [weak self] chunk in
            self?.append(chunk)
        }
        isInstalling = false
        installLabel = ""
        if code == 0 {
            link = ""
            lastInstalled = device
            await reload()
        } else {
            errorMessage = "Install failed (exit \(code)). The log below says which step."
            isLogVisible = true
        }
    }

    func remove(_ entry: ShelfEntry) async {
        guard !isInstalling else { return }
        errorMessage = nil
        isInstalling = true
        installLabel = "removing \(entry.name)"
        log = ""
        let code = await host.stream(
            "linpad-shelf remove \(ShellQuote.quote(entry.name)) 2>&1", cwd: nil
        ) { [weak self] chunk in
            self?.append(chunk)
        }
        isInstalling = false
        installLabel = ""
        if code == 0 {
            await reload()
        } else {
            errorMessage = "Remove failed (exit \(code))."
            isLogVisible = true
        }
    }

    func open(_ entry: ShelfEntry) {
        // The shelf writes a .desktop entry, so the app is a Linux app like any other.
        desktop.open(appID: LinuxAppID.prefix + entry.name, arguments: [:])
    }

    func clearLog() {
        log = ""
    }

    func dismissError() {
        errorMessage = nil
    }

    /// "https://host/app_arm64.deb" -> "app"; "keepassxc" -> "keepassxc".
    private func guestName(for target: String) -> String {
        let base = target.split(separator: "/").last.map(String.init) ?? target
        let trimmed = base.hasSuffix(".deb") ? String(base.dropLast(4)) : base
        return trimmed.replacingOccurrences(of: "_", with: " ")
    }

    private func append(_ chunk: String) {
        log += chunk
        if log.count > Self.logLimit {
            log = String(log.suffix(Self.logLimit / 2))
        }
    }
}

// MARK: - View

struct ShelfAppView: View {
    @Environment(\.desktopTheme) private var theme
    @State private var model: ShelfModel
    @State private var pendingRemoval: ShelfEntry?

    init(context: AppLaunchContext) {
        _model = State(initialValue: ShelfModel(context: context))
    }

    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: 0) {
                toolbar
                if let message = model.errorMessage {
                    InlineBanner(kind: .error, message: message, onDismiss: { model.dismissError() })
                }
                if model.isInstalling {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(model.installLabel.isEmpty ? "Working…" : model.installLabel)
                            .font(.callout).lineLimit(1)
                        Spacer()
                        Button("Log") { model.isLogVisible.toggle() }
                            .buttonStyle(.plain)
                            .font(.caption)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(theme.accent.opacity(0.12))
                }
                content
                if model.isLogVisible { logPane }
            }
            .background(theme.windowBackground)
            .foregroundStyle(theme.primaryText)
            .task { await model.start() }
            .confirmationDialog(
                pendingRemoval.map { "Remove \($0.name)?" } ?? "Remove?",
                isPresented: Binding(
                    get: { pendingRemoval != nil },
                    set: { if !$0 { pendingRemoval = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Remove", role: .destructive) {
                    if let entry = pendingRemoval {
                        pendingRemoval = nil
                        Task { await model.remove(entry) }
                    }
                }
                Button("Cancel", role: .cancel) { pendingRemoval = nil }
            } message: {
                Text("Its files and launcher are deleted. The shared runtime and Firefox profiles stay.")
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Label("Debian Shelf", systemImage: "tray.full")
                .font(.headline)
            Spacer()
            if model.isLoading {
                ProgressView().controlSize(.small)
            }
            Button {
                Task { await model.reload() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Reload")
            Button {
                model.isLogVisible.toggle()
            } label: {
                Image(systemName: "text.alignleft")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Log")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(theme.panelBackground)
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                installCard
                if model.entries.isEmpty {
                    emptyState
                } else {
                    VStack(spacing: 0) {
                        ForEach(model.entries) { entry in
                            row(entry)
                            if entry.id != model.entries.last?.id {
                                Divider().opacity(0.4)
                            }
                        }
                    }
                    .background(theme.panelBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                footnote
            }
            .padding(14)
        }
    }

    private var installCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Install from a link").font(.subheadline.weight(.semibold))
            HStack(spacing: 8) {
                TextField("https://…/app_arm64.deb  ·  /root/app.deb  ·  keepassxc", text: $model.link)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(theme.primaryText.opacity(0.06)))
                    .onSubmit { Task { await model.install() } }
                Button {
                    Task { await model.install() }
                } label: {
                    if model.isInstalling {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Install")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(theme.accent)
                .disabled(model.isInstalling || model.link.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            Text("Only aarch64 .debs run here. Packages installed this way live in their own folder and can be removed completely.")
                .font(.caption)
                .foregroundStyle(theme.secondaryText)
        }
        .padding(12)
        .background(theme.panelBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "shippingbox").font(.system(size: 26, weight: .light))
            Text("Nothing installed from Debian yet").font(.callout)
            Text("Apps from Alpine stay in Packages and the Store; this window is only for .deb software.")
                .font(.caption).foregroundStyle(theme.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
    }

    private func row(_ entry: ShelfEntry) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "shippingbox.fill")
                .foregroundStyle(theme.accent)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name).font(.callout.weight(.medium))
                HStack(spacing: 6) {
                    Text(entry.displayVersion)
                    if let size = entry.size, !size.isEmpty {
                        Text("·"); Text(size)
                    }
                }
                .font(.caption)
                .foregroundStyle(theme.secondaryText)
                .lineLimit(1)
            }
            Spacer()
            Button("Open") { model.open(entry) }
                .buttonStyle(.plain)
                .font(.callout)
            Button("Remove") { pendingRemoval = entry }
                .buttonStyle(.plain)
                .font(.callout)
                .foregroundStyle(.red)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    private var footnote: some View {
        Text("Installs go through `linpad-shelf`, which keeps each app in its own folder and shares one glibc runtime. Nothing is written to /usr/lib or /usr/bin.")
            .font(.caption2)
            .foregroundStyle(theme.secondaryText)
    }

    private var logPane: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Log").font(.caption.weight(.semibold))
                Spacer()
                Button("Clear") { model.clearLog() }
                    .buttonStyle(.plain).font(.caption)
                Button("Hide") { model.isLogVisible = false }
                    .buttonStyle(.plain).font(.caption)
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            ScrollView {
                Text(model.log.isEmpty ? "Nothing yet." : model.log)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(10)
            }
        }
        .frame(height: 180)
        .background(theme.primaryText.opacity(0.04))
    }
}
