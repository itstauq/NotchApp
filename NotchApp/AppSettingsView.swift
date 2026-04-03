import AppKit
import SwiftUI
import Carbon.HIToolbox

private let appSettingsBackgroundColor = NSColor(
    calibratedRed: 0.02,
    green: 0.02,
    blue: 0.025,
    alpha: 1.0
)

enum AppSettingsWindow {
    @MainActor
    static func open() {
        AppSettingsWindowController.shared.show()
    }
}

@MainActor
private final class AppSettingsWindowController: NSWindowController, NSWindowDelegate {
    static let shared = AppSettingsWindowController()

    private let titleLabel: NSTextField = {
        let label = NSTextField(labelWithString: "NotchApp Settings")
        label.translatesAutoresizingMaskIntoConstraints = false
        label.alignment = .center
        label.font = .systemFont(ofSize: 11.5, weight: .semibold)
        label.textColor = NSColor.white.withAlphaComponent(0.72)
        label.backgroundColor = .clear
        label.isBezeled = false
        label.isBordered = false
        label.isEditable = false
        label.isSelectable = false
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        return label
    }()

    private init() {
        let hostingController = NSHostingController(rootView: AppSettingsView())
        let window = NSWindow(contentViewController: hostingController)
        window.title = "NotchApp Settings"
        window.setContentSize(NSSize(width: 900, height: 620))
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.center()
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.fullScreenNone]
        window.isOpaque = true
        window.backgroundColor = appSettingsBackgroundColor
        window.appearance = NSAppearance(named: .darkAqua)
        window.hasShadow = true
        window.standardWindowButton(.miniaturizeButton)?.isEnabled = false
        window.standardWindowButton(.zoomButton)?.isEnabled = false
        super.init(window: window)
        window.delegate = self
        installCenteredTitle()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        guard let window else { return }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    private func installCenteredTitle() {
        guard let titlebarView = window?.standardWindowButton(.closeButton)?.superview else { return }
        titlebarView.addSubview(titleLabel)
        NSLayoutConstraint.activate([
            titleLabel.centerXAnchor.constraint(equalTo: titlebarView.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: titlebarView.centerYAnchor, constant: -1),
            titleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: titlebarView.leadingAnchor, constant: 96),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: titlebarView.trailingAnchor, constant: -96)
        ])
    }
}

private enum AppSettingsTab: String, CaseIterable, Identifiable {
    case general
    case widgets
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general:
            return "General"
        case .widgets:
            return "Widgets"
        case .about:
            return "About"
        }
    }

    var symbolName: String {
        switch self {
        case .general:
            return "gearshape"
        case .widgets:
            return "square.grid.2x2"
        case .about:
            return "info.circle"
        }
    }
}

struct AppSettingsView: View {
    @State private var selection: AppSettingsTab = .general
    @State private var accentColor = Preferences.accentColor

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
                .overlay(Color.white.opacity(0.06))

            Group {
                switch selection {
                case .general:
                    GeneralSettingsPage(accentColor: $accentColor)
                case .widgets:
                    SettingsPlaceholderPage(
                        title: "Widgets",
                        description: "Widget-specific settings and management will live here."
                    )
                case .about:
                    SettingsPlaceholderPage(
                        title: "About",
                        description: "App information, credits, and links will live here."
                    )
                }
            }
        }
        .frame(minWidth: 900, minHeight: 620)
        .background(Color(nsColor: appSettingsBackgroundColor))
        .overlay {
            RoundedRectangle(cornerRadius: 0, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        }
        .ignoresSafeArea(edges: .top)
        .preferredColorScheme(.dark)
        .onReceive(NotificationCenter.default.publisher(for: .accentColorPreferenceDidChange)) { _ in
            accentColor = Preferences.accentColor
        }
    }

    private var topBar: some View {
        HStack(spacing: 8) {
            ForEach(AppSettingsTab.allCases) { tab in
                SettingsTabButton(
                    tab: tab,
                    isSelected: selection == tab,
                    tint: accentColor.color
                ) {
                    selection = tab
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 28)
        .padding(.top, 32)
        .padding(.bottom, 6)
    }
}

private struct GeneralSettingsPage: View {
    @Binding var accentColor: AppAccentColor
    @State private var launchAtLogin = Preferences.isLaunchAtLoginEnabled
    @State private var showMenuBarIcon = Preferences.isMenuBarIconEnabled
    @State private var openNotchOnHover = Preferences.openNotchMode == .hover
    @State private var hoverDelay = Preferences.hoverDelay
    @State private var rememberLastView = Preferences.rememberLastView
    @State private var keyboardShortcutsEnabled = Preferences.keyboardShortcutsEnabled
    @State private var toggleNotchShortcut = Preferences.toggleNotchShortcut ?? .toggleNotchDefault
    @State private var hasToggleNotchShortcut = Preferences.toggleNotchShortcut != nil
    @State private var isRecordingShortcut = false

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                SettingsSection(
                    title: "System",
                    symbolName: "switch.2"
                ) {
                    SettingsToggleRow(
                        title: "Launch at login",
                        isOn: Binding(
                            get: { launchAtLogin },
                            set: {
                                if Preferences.setLaunchAtLoginEnabled($0) {
                                    launchAtLogin = Preferences.isLaunchAtLoginEnabled
                                } else {
                                    launchAtLogin = Preferences.isLaunchAtLoginEnabled
                                }
                            }
                        )
                    )

                    SettingsToggleRow(
                        title: "Show menu bar icon",
                        isOn: Binding(
                            get: { showMenuBarIcon },
                            set: {
                                showMenuBarIcon = $0
                                Preferences.isMenuBarIconEnabled = $0
                            }
                        )
                    )
                }

                SettingsSection(
                    title: "Interaction",
                    symbolName: "cursorarrow.motionlines"
                ) {
                    SettingsSegmentedRow(
                        title: "Open notch",
                        selection: Binding(
                            get: { openNotchOnHover },
                            set: {
                                openNotchOnHover = $0
                                Preferences.openNotchMode = $0 ? .hover : .click
                            }
                        ),
                        options: [
                            SettingsSegmentedOption(title: "Click", value: false),
                            SettingsSegmentedOption(title: "Hover", value: true),
                        ]
                    )

                    if openNotchOnHover {
                        SettingsSliderRow(
                            title: "Hover delay",
                            valueLabel: String(format: "%.1fs", hoverDelay),
                            value: Binding(
                                get: { hoverDelay },
                                set: {
                                    hoverDelay = $0
                                    Preferences.hoverDelay = $0
                                }
                            ),
                            range: 0.1...1.0,
                            step: 0.1
                        )
                    }

                    SettingsToggleRow(
                        title: "Remember last view",
                        isOn: Binding(
                            get: { rememberLastView },
                            set: {
                                rememberLastView = $0
                                Preferences.rememberLastView = $0
                            }
                        )
                    )
                }

                SettingsSection(
                    title: "Appearance",
                    symbolName: "paintpalette"
                ) {
                    SettingsSwatchRow(
                        title: "Accent color",
                        selection: $accentColor,
                        options: AppAccentColor.allCases
                    )
                }

                SettingsSection(
                    title: "Shortcuts",
                    symbolName: "command"
                ) {
                    SettingsToggleRow(
                        title: "Keyboard shortcuts",
                        subtitle: "Enable global app shortcuts.",
                        isOn: Binding(
                            get: { keyboardShortcutsEnabled },
                            set: {
                                keyboardShortcutsEnabled = $0
                                Preferences.keyboardShortcutsEnabled = $0
                            }
                        )
                    )

                    if keyboardShortcutsEnabled {
                        SettingsShortcutRecorderRow(
                            title: "Toggle notch",
                            subtitle: "Opens or closes the notch window from anywhere.",
                            value: hasToggleNotchShortcut ? toggleNotchShortcut.displayString : "Record Hotkey",
                            shortcut: $toggleNotchShortcut,
                            hasShortcut: $hasToggleNotchShortcut,
                            isRecording: $isRecordingShortcut
                        )
                    }
                }
            }
            .frame(maxWidth: 560)
            .padding(.horizontal, 24)
            .padding(.top, 48)
            .padding(.bottom, 40)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.never)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .tint(accentColor.color)
        .onReceive(NotificationCenter.default.publisher(for: .keyboardShortcutPreferenceDidChange)) { _ in
            if let shortcut = Preferences.toggleNotchShortcut {
                toggleNotchShortcut = shortcut
                hasToggleNotchShortcut = true
            } else {
                hasToggleNotchShortcut = false
            }
        }
    }
}

private struct SettingsPlaceholderPage: View {
    var title: String
    var description: String

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 56)
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 10) {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                        .frame(width: 30, height: 30)
                        .overlay {
                            Image(systemName: symbolName)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.72))
                        }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.92))

                        Text(description)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.42))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                VStack(spacing: 10) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.54))

                    Text("Settings controls will appear here soon.")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))

                    Text("This shell is ready for the real app-wide and widget preference forms.")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.42))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 260)
                }
                .padding(.vertical, 26)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(.white.opacity(0.08), lineWidth: 1)
                )
            }
            .frame(maxWidth: 460)
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.black.opacity(0.74))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(.white.opacity(0.1), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.24), radius: 16, y: 10)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var symbolName: String {
        switch title {
        case "General":
            return "gearshape"
        case "Widgets":
            return "square.grid.2x2"
        case "About":
            return "info.circle"
        default:
            return "slider.horizontal.3"
        }
    }
}

private struct SettingsSection<Content: View>: View {
    var title: String
    var symbolName: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: symbolName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.62))

                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
            }

            VStack(spacing: 0) {
                content
            }
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            )
        }
    }
}

private struct SettingsToggleRow: View {
    var title: String
    var subtitle: String? = nil
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))

                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.42))
                }
            }

            Spacer(minLength: 16)

            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .labelsHidden()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

private struct SettingsSegmentedOption<Value: Hashable>: Identifiable {
    var title: String
    var value: Value

    var id: String { title }
}

private struct SettingsSegmentedRow<Value: Hashable>: View {
    var title: String
    @Binding var selection: Value
    var options: [SettingsSegmentedOption<Value>]
    var bottomPadding: CGFloat = 14

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Text(title)
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))

            Spacer(minLength: 16)

            Picker(title, selection: $selection) {
                ForEach(options) { option in
                    Text(option.title).tag(option.value)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, bottomPadding)
    }
}

private struct SettingsSliderRow: View {
    var title: String
    var valueLabel: String
    @Binding var value: Double
    var range: ClosedRange<Double>
    var step: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Text(title)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))

                Spacer(minLength: 12)

                Text(valueLabel)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.64))
            }

            Slider(value: $value, in: range, step: step)
                .tint(.white.opacity(0.75))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

private struct SettingsSwatchRow: View {
    var title: String
    @Binding var selection: AppAccentColor
    var options: [AppAccentColor]

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Text(title)
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))

            Spacer(minLength: 16)

            HStack(spacing: 10) {
                ForEach(options) { option in
                    Button {
                        selection = option
                        Preferences.accentColor = option
                    } label: {
                        Circle()
                            .fill(option.color)
                            .frame(width: 20, height: 20)
                            .overlay {
                                Circle()
                                    .strokeBorder(Color.white.opacity(selection == option ? 0.96 : 0.18), lineWidth: selection == option ? 2 : 1)
                                    .padding(selection == option ? -4 : 0)
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

private struct SettingsDescriptionRow: View {
    var text: String
    var topPadding: CGFloat = 14
    var bottomPadding: CGFloat = 14

    var body: some View {
        Text(text)
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(.white.opacity(0.42))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, topPadding)
            .padding(.bottom, bottomPadding)
    }
}

private struct SettingsValueRow: View {
    var title: String
    var subtitle: String? = nil
    var value: String
    var isDimmed = false

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(isDimmed ? 0.45 : 0.92))

                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.42))
                }
            }

            Spacer(minLength: 16)

            Text(value)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(isDimmed ? 0.34 : 0.64))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

private struct SettingsShortcutRecorderRow: View {
    var title: String
    var subtitle: String
    var value: String
    @Binding var shortcut: Preferences.KeyboardShortcut
    @Binding var hasShortcut: Bool
    @Binding var isRecording: Bool
    @State private var recordedShortcut = ShortcutRecordingState()

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))

                Text(subtitle)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.42))
            }

            Spacer(minLength: 16)

            Button {
                isRecording.toggle()
            } label: {
                Text(value)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.82))
                    .padding(.horizontal, 16)
                    .frame(height: 36)
                    .background(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(.white.opacity(isRecording ? 0.12 : 0.06))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .strokeBorder(.white.opacity(isRecording ? 0.18 : 0.08), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .popover(isPresented: $isRecording, attachmentAnchor: .rect(.bounds), arrowEdge: .top) {
                ShortcutRecorderPopover(
                    recording: $recordedShortcut,
                    onSave: { newShortcut in
                        shortcut = newShortcut
                        hasShortcut = true
                        Preferences.toggleNotchShortcut = newShortcut
                    },
                    onClear: {
                        hasShortcut = false
                        Preferences.toggleNotchShortcut = nil
                    }
                ) {
                    isRecording = false
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .onChange(of: isRecording) { _, newValue in
            if newValue {
                recordedShortcut = ShortcutRecordingState()
            }
        }
    }
}

private struct ShortcutRecorderPopover: View {
    @Binding var recording: ShortcutRecordingState
    var onSave: (Preferences.KeyboardShortcut) -> Void
    var onClear: () -> Void
    var onClose: () -> Void
    @State private var keyMonitor: Any?
    @State private var flagsMonitor: Any?
    @State private var resetTask: Task<Void, Never>?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 12) {
                HStack(spacing: 6) {
                    Text(recording.hasInput ? "Now" : "e.g.")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.18))

                    ForEach(recording.tokens, id: \.self) { token in
                        ShortcutKeyChip(token, isDimmed: recording.isShowingExample)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 2)

                Text(recording.statusTitle)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(recording.statusColor)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.bottom, 2)

                Text("Press Delete to clear")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(.white.opacity(0.34))
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .padding(.bottom, 8)
            .frame(width: 250, height: 92)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white.opacity(0.38))
                    .frame(width: 14, height: 14)
            }
            .buttonStyle(.plain)
            .padding(.top, 10)
            .padding(.trailing, 10)
        }
        .background(.clear)
        .preferredColorScheme(.dark)
        .onAppear {
            installKeyMonitors()
        }
        .onDisappear {
            resetTask?.cancel()
            removeKeyMonitors()
        }
    }

    private func installKeyMonitors() {
        removeKeyMonitors()
        resetTask?.cancel()

        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            guard recording.status == .idle || recording.status == .recording else {
                return nil
            }
            recording.modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            return nil
        }

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard recording.status == .idle || recording.status == .recording else {
                return nil
            }
            resetTask?.cancel()
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

            if event.keyCode == 53 {
                onClose()
                return nil
            }

            if event.keyCode == UInt16(kVK_Delete) || event.keyCode == UInt16(kVK_ForwardDelete) {
                recording = ShortcutRecordingState()
                onClear()
                onClose()
                return nil
            }

            recording.modifiers = modifiers
            recording.key = shortcutDisplayString(for: event)
            recording.lastCommittedKeyCode = UInt32(event.keyCode)
            recording.lastCommittedModifiers = modifiers
            recording.didReceiveInput = true
            recording.status = .recording
            finalizeIfNeeded()
            return nil
        }
    }

    private func removeKeyMonitors() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        if let flagsMonitor {
            NSEvent.removeMonitor(flagsMonitor)
            self.flagsMonitor = nil
        }
    }

    private func finalizeIfNeeded() {
        guard recording.hasInput, recording.key != nil else { return }

        if recording.isValid {
            recording.status = .success
            removeKeyMonitors()
            onSave(
                Preferences.KeyboardShortcut(
                    keyCode: recording.lastCommittedKeyCode,
                    modifiers: recording.lastCommittedModifiers
                )
            )
            let snapshot = recording
            resetTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled, recording.matches(identityOf: snapshot) else { return }
                onClose()
            }
        } else {
            recording.status = .invalid
            let snapshot = recording
            resetTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(800))
                guard !Task.isCancelled, recording.matches(identityOf: snapshot) else { return }
                recording = ShortcutRecordingState()
            }
        }
    }

    private func shortcutDisplayString(for event: NSEvent) -> String {
        switch event.keyCode {
        case 36:
            return "Return"
        case 48:
            return "Tab"
        case 49:
            return "Space"
        case 51:
            return "Delete"
        case 53:
            return "Esc"
        case 123:
            return "←"
        case 124:
            return "→"
        case 125:
            return "↓"
        case 126:
            return "↑"
        default:
            let raw = event.charactersIgnoringModifiers?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if raw.isEmpty {
                return "Key"
            }
            return raw.uppercased()
        }
    }
}

private struct ShortcutKeyChip: View {
    var title: String
    var isDimmed: Bool = false

    init(_ title: String) {
        self.title = title
    }

    init(_ title: String, isDimmed: Bool) {
        self.title = title
        self.isDimmed = isDimmed
    }

    var body: some View {
        Text(title)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.white.opacity(isDimmed ? 0.42 : 0.84))
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.white.opacity(isDimmed ? 0.04 : 0.07))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(.white.opacity(isDimmed ? 0.05 : 0.08), lineWidth: 1)
            )
    }
}

private struct ShortcutRecordingState {
    enum Status: Equatable {
        case idle
        case recording
        case success
        case invalid
    }

    var modifiers: NSEvent.ModifierFlags = []
    var lastCommittedKeyCode: UInt32 = UInt32(kVK_Space)
    var lastCommittedModifiers: NSEvent.ModifierFlags = []
    var key: String? = nil
    var didReceiveInput = false
    var status: Status = .idle

    var hasInput: Bool {
        didReceiveInput
    }

    var isShowingExample: Bool {
        !didReceiveInput && key == nil && modifiers.isEmpty && lastCommittedModifiers.isEmpty
    }

    var tokens: [String] {
        var result: [String] = []

        let displayModifiers = modifiers.isEmpty && key != nil ? lastCommittedModifiers : modifiers

        if displayModifiers.contains(.shift) {
            result.append("⇧")
        }
        if displayModifiers.contains(.control) {
            result.append("⌃")
        }
        if displayModifiers.contains(.option) {
            result.append("⌥")
        }
        if displayModifiers.contains(.command) {
            result.append("⌘")
        }
        if let key {
            result.append(key)
        }

        if result.isEmpty {
            return ["⇧", "⌘", "Space"]
        }

        return result
    }

    var isValid: Bool {
        key != nil && !lastCommittedModifiers.isEmpty
    }

    var statusTitle: String {
        switch status {
        case .idle, .recording:
            return "Recording..."
        case .success:
            return "Your new hotkey is set!"
        case .invalid:
            return "Invalid hotkey"
        }
    }

    var statusColor: Color {
        switch status {
        case .success:
            return Color(red: 0.42, green: 0.88, blue: 0.58)
        case .idle, .recording:
            return .white.opacity(0.9)
        case .invalid:
            return Color(red: 1.0, green: 0.58, blue: 0.58)
        }
    }

    func matches(identityOf other: ShortcutRecordingState) -> Bool {
        key == other.key
            && modifiers == other.modifiers
            && lastCommittedKeyCode == other.lastCommittedKeyCode
            && lastCommittedModifiers == other.lastCommittedModifiers
            && didReceiveInput == other.didReceiveInput
            && status == other.status
    }
}


private struct SettingsTabButton: View {
    var tab: AppSettingsTab
    var isSelected: Bool
    var tint: Color
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 1) {
                Image(systemName: tab.symbolName)
                    .font(.system(size: 13, weight: .semibold))

                Text(tab.title)
                    .font(.system(size: 10.5, weight: .semibold))
            }
            .frame(width: 68, height: 34)
            .foregroundStyle(.white.opacity(isSelected ? 0.95 : 0.72))
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? tint.opacity(0.2) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isSelected ? tint.opacity(0.34) : .white.opacity(0.0), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
