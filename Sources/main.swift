import AppKit
import Carbon.HIToolbox
import Combine
import ServiceManagement
import SwiftUI

// MARK: - 기호 목록

struct SymbolGroup {
    let title: String
    let items: [String]
}

/// 설정창에서 고를 수 있는 기호 후보.
let catalog: [SymbolGroup] = [
    SymbolGroup(title: "화살표", items: ["→", "←", "↑", "↓", "↔", "↕", "⇒", "⇐", "⇔", "⇑", "⇓",
                                       "↗", "↘", "↖", "↙", "↩", "↪", "⟶", "➜", "▶", "◀"]),
    SymbolGroup(title: "수학", items: ["×", "÷", "±", "≈", "≠", "≤", "≥", "∞", "√", "∑", "∆",
                                     "°", "‰", "µ", "π"]),
    SymbolGroup(title: "문장부호", items: ["·", "•", "…", "—", "–", "«", "»", "‘", "’", "“", "”",
                                       "※", "§", "¶", "†"]),
    SymbolGroup(title: "기타", items: ["✓", "✗", "★", "☆", "●", "○", "■", "□", "♥", "☺",
                                     "©", "®", "™", "€", "£", "¥", "₩"]),
]

let defaultSelection: Set<String> = [
    "→", "←", "↑", "↓", "↔", "↕", "⇒", "⇐", "⇔", "↗", "↘", "↩",
    "·", "•", "…", "—", "–", "×", "÷", "±", "≈", "≠", "≤", "≥", "°", "✓", "★", "※",
]

let unicodeHexSourceID = "com.apple.keylayout.UnicodeHexInput"

func currentInputSourceID() -> String? {
    guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
          let ptr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID)
    else { return nil }
    return Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
}

func hexCode(_ s: String) -> String {
    s.unicodeScalars.map { String(format: "%04X", $0.value) }.joined(separator: " ")
}

// MARK: - 입력 소스 상태

/// Unicode Hex Input이 입력 소스에 추가되어 있는지 추적하고, 추가/전환을 해준다.
final class InputSourceStatus: ObservableObject {
    static let shared = InputSourceStatus()
    @Published private(set) var isEnabled = false

    private init() {
        refresh()
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(refresh),
            name: NSNotification.Name(kTISNotifyEnabledKeyboardInputSourcesChanged as String),
            object: nil, suspensionBehavior: .deliverImmediately)
    }

    var isEnabledNow: Bool { Self.find(includeAllInstalled: false) != nil }

    @objc func refresh() {
        DispatchQueue.main.async { self.isEnabled = self.isEnabledNow }
    }

    /// includeAllInstalled가 false면 사용자가 추가해 둔 입력 소스만 찾는다.
    private static func find(includeAllInstalled: Bool) -> TISInputSource? {
        let filter = [kTISPropertyInputSourceID as String: unicodeHexSourceID] as CFDictionary
        let list = TISCreateInputSourceList(filter, includeAllInstalled)?.takeRetainedValue() as? [TISInputSource]
        return list?.first
    }

    @discardableResult
    func enable() -> Bool {
        guard let source = Self.find(includeAllInstalled: true) else { return false }
        let ok = TISEnableInputSource(source) == noErr
        refresh()
        return ok
    }

    func select() {
        if let source = Self.find(includeAllInstalled: false) { TISSelectInputSource(source) }
    }

    static func openKeyboardSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!)
    }
}

/// "2192", "U+2192" 같은 코드나 문자 하나를 받아 기호로 바꾼다.
func parseSymbol(_ input: String) -> String? {
    let s = input.trimmingCharacters(in: .whitespaces)
    let upper = s.uppercased()
    let hex = upper.hasPrefix("U+") ? String(upper.dropFirst(2)) : upper
    if hex.count >= 2, hex.allSatisfy(\.isHexDigit),
       let value = UInt32(hex, radix: 16), let scalar = Unicode.Scalar(value) {
        return String(Character(scalar))
    }
    return s.count == 1 ? s : nil
}

// MARK: - 설정

final class Settings: ObservableObject {
    static let shared = Settings()
    private let defaults = UserDefaults.standard

    @Published var selected: Set<String> { didSet { defaults.set(Array(selected), forKey: "selected") } }
    @Published var custom: [String] { didSet { defaults.set(custom, forKey: "custom") } }
    @Published var alwaysShow: Bool { didSet { defaults.set(alwaysShow, forKey: "alwaysShow") } }

    private init() {
        selected = defaults.stringArray(forKey: "selected").map(Set.init) ?? defaultSelection
        custom = defaults.stringArray(forKey: "custom") ?? []
        alwaysShow = defaults.bool(forKey: "alwaysShow")
    }

    /// 오버레이에 실제로 표시할 그룹 (카탈로그 순서 유지).
    var visibleGroups: [SymbolGroup] {
        var groups = catalog
            .map { group in SymbolGroup(title: group.title, items: group.items.filter { selected.contains($0) }) }
            .filter { !$0.items.isEmpty }
        if !custom.isEmpty { groups.append(SymbolGroup(title: "직접 추가", items: custom)) }
        return groups
    }

    func resetToDefault() {
        selected = defaultSelection
        custom = []
    }
}

// MARK: - 오버레이

final class OverlayPanel: NSPanel {
    static let topLeftKey = "panelTopLeft"
    private static let maxRowsPerColumn = 32

    private let background = DragView()
    private var content: NSView?

    var onClick: () -> Void {
        get { background.onClick }
        set { background.onClick = newValue }
    }

    init() {
        super.init(contentRect: .zero,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        background.material = .hudWindow
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 12
        background.layer?.masksToBounds = true
        contentView = background
    }

    /// 설정이 바뀌면 내용을 다시 그린다. 위쪽 모서리는 그대로 둔다.
    func rebuild(groups: [SymbolGroup]) {
        let topLeft = NSPoint(x: frame.minX, y: frame.maxY)
        content?.removeFromSuperview()

        let view = groups.isEmpty ? Self.emptyView() : Self.columns(for: groups)
        view.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 14),
            view.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -14),
            view.topAnchor.constraint(equalTo: background.topAnchor, constant: 12),
            view.bottomAnchor.constraint(equalTo: background.bottomAnchor, constant: -12),
        ])
        content = view
        setContentSize(background.fittingSize)
        if isVisible { setFrameTopLeftPoint(topLeft) }
    }

    /// 머리글과 행을 순서대로 늘어놓고, 너무 길면 여러 열로 나눈다.
    private static func columns(for groups: [SymbolGroup]) -> NSView {
        var entries: [NSView] = []
        for (index, group) in groups.enumerated() {
            entries.append(header(group.title, showOptionKey: index == 0))
            entries.append(contentsOf: group.items.map(row))
        }

        let columnCount = (entries.count + maxRowsPerColumn - 1) / maxRowsPerColumn
        let perColumn = (entries.count + columnCount - 1) / columnCount
        let columns = stride(from: 0, to: entries.count, by: perColumn).map { start -> NSView in
            let column = NSStackView(views: Array(entries[start..<min(start + perColumn, entries.count)]))
            column.orientation = .vertical
            column.alignment = .leading
            column.spacing = 3
            return column
        }
        let stack = NSStackView(views: columns)
        stack.alignment = .top
        stack.spacing = 18
        return stack
    }

    private static func header(_ title: String, showOptionKey: Bool) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 10, weight: .semibold)
        label.textColor = .tertiaryLabelColor
        guard showOptionKey else { return label }

        let key = NSTextField(labelWithString: "⌥")
        key.font = .systemFont(ofSize: 11, weight: .semibold)
        key.textColor = .secondaryLabelColor
        key.alignment = .center
        key.wantsLayer = true
        key.layer?.cornerRadius = 4
        key.layer?.borderWidth = 1
        key.layer?.borderColor = NSColor.secondaryLabelColor.cgColor
        key.widthAnchor.constraint(equalToConstant: 18).isActive = true

        let stack = NSStackView(views: [label, key])
        stack.spacing = 6
        return stack
    }

    private static func row(_ ch: String) -> NSView {
        let symbol = NSTextField(labelWithString: ch)
        symbol.font = .systemFont(ofSize: 16)
        symbol.alignment = .center
        symbol.widthAnchor.constraint(equalToConstant: 26).isActive = true

        let code = NSTextField(labelWithString: hexCode(ch))
        code.font = .monospacedSystemFont(ofSize: 14, weight: .semibold)

        let row = NSStackView(views: [symbol, code])
        row.spacing = 10
        return row
    }

    private static func emptyView() -> NSView {
        let label = NSTextField(labelWithString: "클릭해서 기호 선택")
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabelColor
        return label
    }

    /// 드래그로 저장한 위치가 있으면 그곳, 없으면 화면 오른쪽 가운데.
    func placeOnScreen() {
        if let saved = UserDefaults.standard.string(forKey: Self.topLeftKey) {
            let topLeft = NSPointFromString(saved)
            let rect = NSRect(x: topLeft.x, y: topLeft.y - frame.height, width: frame.width, height: frame.height)
            if NSScreen.screens.contains(where: { $0.visibleFrame.intersects(rect) }) {
                setFrameTopLeftPoint(topLeft)
                return
            }
        }
        guard let screen = NSScreen.main else { return }
        let v = screen.visibleFrame
        let size = frame.size
        setFrameOrigin(NSPoint(x: v.maxX - size.width - 16, y: v.midY - size.height / 2))
    }

    func resetPosition() {
        UserDefaults.standard.removeObject(forKey: Self.topLeftKey)
        placeOnScreen()
    }
}

/// 패널 전체를 잡고 끌 수 있고, 마우스를 올리면 반투명해지는 배경 뷰.
/// 움직이지 않고 떼면 클릭으로 본다.
final class DragView: NSVisualEffectView {
    var onClick: () -> Void = {}
    private let hoverAlpha: CGFloat = 0.15
    private var dragStart: NSPoint?
    private var mouseDownScreen: NSPoint = .zero

    override func hitTest(_ point: NSPoint) -> NSView? {
        frame.contains(point) ? self : nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self))
    }

    private func fade(to alpha: CGFloat) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            window?.animator().alphaValue = alpha
        }
    }

    override func mouseEntered(with event: NSEvent) { if dragStart == nil { fade(to: hoverAlpha) } }
    override func mouseExited(with event: NSEvent) { if dragStart == nil { fade(to: 1) } }

    override func mouseDown(with event: NSEvent) {
        dragStart = event.locationInWindow
        mouseDownScreen = NSEvent.mouseLocation
        fade(to: 0.85)  // 끄는 동안은 잘 보이게
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window, let start = dragStart else { return }
        let mouse = NSEvent.mouseLocation
        window.setFrameOrigin(NSPoint(x: mouse.x - start.x, y: mouse.y - start.y))
    }

    override func mouseUp(with event: NSEvent) {
        dragStart = nil
        guard let window else { return }
        let mouse = NSEvent.mouseLocation
        if hypot(mouse.x - mouseDownScreen.x, mouse.y - mouseDownScreen.y) < 3 {
            fade(to: 1)
            onClick()
            return
        }
        let topLeft = NSPoint(x: window.frame.minX, y: window.frame.maxY)
        UserDefaults.standard.set(NSStringFromPoint(topLeft), forKey: OverlayPanel.topLeftKey)
        fade(to: window.frame.contains(mouse) ? hoverAlpha : 1)
    }
}

// MARK: - 로그인 시 실행

enum LoginItem {
    static var status: SMAppService.Status { SMAppService.mainApp.status }

    static func set(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("로그인 항목 변경 실패: \(error.localizedDescription)")
        }
    }
}

/// DMG 안이나 격리된 임시 경로(App Translocation)에서 실행 중인지.
var isRunningFromTemporaryLocation: Bool {
    let path = Bundle.main.bundlePath
    return path.hasPrefix("/Volumes/") || path.contains("/AppTranslocation/")
}

// MARK: - 설정 가이드

struct SetupGuideView: View {
    @ObservedObject private var status = InputSourceStatus.shared
    @State private var autoFailed = false
    var onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Unicode Hex Input 추가").font(.title2.bold())

            if status.isEnabled {
                Label("Unicode Hex Input이 추가되어 있습니다.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("메뉴바 입력 메뉴나 ⌃Space(또는 🌐 키)로 **U+** 입력 소스로 바꾸면 기호 코드가 화면에 나타납니다. "
                     + "⌥를 누른 채 코드를 입력하면 기호가 입력됩니다.")
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("지금 U+로 전환해 보기") { status.select() }
                    Spacer()
                    Button("완료", action: onClose).keyboardShortcut(.defaultAction)
                }
            } else {
                Text("이 앱은 입력 소스가 **Unicode Hex Input**일 때 기호와 코드를 보여줍니다. "
                     + "아직 입력 소스에 추가되어 있지 않습니다.")
                    .fixedSize(horizontal: false, vertical: true)
                Button("자동으로 추가") { autoFailed = !status.enable() }
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.large)
                if autoFailed {
                    Text("자동으로 추가하지 못했습니다. 아래 방법으로 직접 추가해 주세요.")
                        .font(.caption).foregroundStyle(.red)
                }

                Divider()
                Text("직접 추가하기").font(.headline)
                VStack(alignment: .leading, spacing: 4) {
                    Text("1. 시스템 설정 → 키보드 → 텍스트 입력 → 입력 소스 **편집…**")
                    Text("2. 왼쪽 아래 **+** → 목록 맨 아래 **기타**")
                    Text("3. **Unicode Hex Input** 선택 → **추가**")
                }
                .font(.callout)
                HStack {
                    Button("키보드 설정 열기") { InputSourceStatus.openKeyboardSettings() }
                    Spacer()
                    Button("나중에", action: onClose)
                }
            }
        }
        .padding(24)
        .frame(width: 420)
    }
}

// MARK: - 설정창

struct SymbolTile: View {
    let symbol: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        VStack(spacing: 2) {
            Text(symbol).font(.system(size: 20))
            Text(hexCode(symbol))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 50)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isOn ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.08)))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isOn ? Color.accentColor : .clear, lineWidth: 1.5))
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
    }
}

struct SettingsView: View {
    @ObservedObject private var settings = Settings.shared
    @ObservedObject private var status = InputSourceStatus.shared
    var openGuide: () -> Void = {}
    @State private var loginStatus = LoginItem.status
    @State private var input = ""
    @State private var invalidInput = false

    private let grid = [GridItem(.adaptive(minimum: 58), spacing: 6)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    if status.isEnabled {
                        Label("Unicode Hex Input 추가됨", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Label("Unicode Hex Input이 입력 소스에 없음", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                    Spacer()
                    Button("설정 가이드", action: openGuide)
                }
                Toggle("입력 소스와 관계없이 항상 표시", isOn: $settings.alwaysShow)
                VStack(alignment: .leading, spacing: 2) {
                    Toggle("로그인 시 자동 실행", isOn: Binding(
                        get: { loginStatus == .enabled },
                        set: { LoginItem.set($0); loginStatus = LoginItem.status }))
                    if loginStatus == .requiresApproval {
                        Button("시스템 설정 → 로그인 항목에서 허용해 주세요") {
                            SMAppService.openSystemSettingsLoginItems()
                        }
                        .buttonStyle(.link)
                        .font(.caption)
                    }
                }

                ForEach(catalog, id: \.title) { group in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(group.title).font(.headline)
                            Spacer()
                            Button("모두 선택") { settings.selected.formUnion(group.items) }
                            Button("모두 해제") { settings.selected.subtract(group.items) }
                        }
                        .buttonStyle(.link)
                        LazyVGrid(columns: grid, spacing: 6) {
                            ForEach(group.items, id: \.self) { symbol in
                                SymbolTile(symbol: symbol, isOn: settings.selected.contains(symbol)) {
                                    if settings.selected.contains(symbol) {
                                        settings.selected.remove(symbol)
                                    } else {
                                        settings.selected.insert(symbol)
                                    }
                                }
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("직접 추가").font(.headline)
                    HStack {
                        TextField("코드(2192, U+2192) 또는 문자", text: $input)
                            .onSubmit(addCustom)
                        Button("추가", action: addCustom)
                    }
                    if invalidInput {
                        Text("인식할 수 없는 입력입니다.").font(.caption).foregroundStyle(.red)
                    }
                    if !settings.custom.isEmpty {
                        Text("눌러서 제거").font(.caption).foregroundStyle(.secondary)
                        LazyVGrid(columns: grid, spacing: 6) {
                            ForEach(settings.custom, id: \.self) { symbol in
                                SymbolTile(symbol: symbol, isOn: true) {
                                    settings.custom.removeAll { $0 == symbol }
                                }
                            }
                        }
                    }
                }

                HStack {
                    Spacer()
                    Button("기본값으로 되돌리기") { settings.resetToDefault() }
                }
            }
            .padding(20)
        }
        .frame(width: 460, height: 600)
    }

    private func addCustom() {
        guard let symbol = parseSymbol(input) else {
            invalidInput = true
            return
        }
        invalidInput = false
        input = ""
        if catalog.contains(where: { $0.items.contains(symbol) }) {
            settings.selected.insert(symbol)
        } else if !settings.custom.contains(symbol) {
            settings.custom.append(symbol)
        }
    }
}

// MARK: - 앱

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = Settings.shared
    private var statusItem: NSStatusItem!
    private var panel: OverlayPanel!
    private var alwaysItem: NSMenuItem!
    private var settingsWindow: NSWindow?
    private var guideWindow: NSWindow?
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 이미 실행 중이면 그쪽을 쓰고 종료.
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
        if others.contains(where: { $0 != .current }) {
            NSApp.terminate(nil)
            return
        }

        if isRunningFromTemporaryLocation {
            offerMoveToApplications()
            return
        }

        // 처음 실행할 때 한 번만 로그인 항목으로 등록한다. 이후에는 설정에서 끌 수 있다.
        if !UserDefaults.standard.bool(forKey: "didRegisterLoginItem") {
            LoginItem.set(true)
            UserDefaults.standard.set(true, forKey: "didRegisterLoginItem")
        }

        installEditMenu()

        panel = OverlayPanel()
        panel.onClick = { [weak self] in self?.openSettings() }
        panel.rebuild(groups: settings.visibleGroups)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "U+"

        let menu = NSMenu()
        let settingsItem = NSMenuItem(title: "설정…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        let guideItem = NSMenuItem(title: "설정 가이드…", action: #selector(openGuide), keyEquivalent: "")
        guideItem.target = self
        menu.addItem(guideItem)
        alwaysItem = NSMenuItem(title: "항상 표시", action: #selector(toggleAlways), keyEquivalent: "")
        alwaysItem.target = self
        menu.addItem(alwaysItem)
        let reset = NSMenuItem(title: "위치 초기화", action: #selector(resetPosition), keyEquivalent: "")
        reset.target = self
        menu.addItem(reset)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu

        // objectWillChange는 값이 바뀌기 직전에 오므로 다음 런루프에서 반영한다.
        settings.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                guard let self else { return }
                panel.rebuild(groups: settings.visibleGroups)
                refresh()
            }
            .store(in: &cancellables)

        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(refresh),
            name: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil, suspensionBehavior: .deliverImmediately)
        NotificationCenter.default.addObserver(
            self, selector: #selector(refresh),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)

        refresh()

        if !InputSourceStatus.shared.isEnabledNow {
            openGuide()
        }
    }

    /// DMG에서 바로 실행한 경우 응용 프로그램 폴더로 복사한 뒤 그쪽을 다시 실행한다.
    private func offerMoveToApplications() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "UnicodeHelper를 응용 프로그램 폴더로 옮길까요?"
        alert.informativeText = "디스크 이미지에서 바로 실행하면 로그인 시 자동 실행이 동작하지 않습니다."
        alert.addButton(withTitle: "옮기기")
        alert.addButton(withTitle: "종료")
        guard alert.runModal() == .alertFirstButtonReturn else {
            NSApp.terminate(nil)
            return
        }

        let destination = URL(fileURLWithPath: "/Applications/UnicodeHelper.app")
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: Bundle.main.bundleURL, to: destination)
        } catch {
            let failed = NSAlert()
            failed.messageText = "옮기지 못했습니다."
            failed.informativeText = "UnicodeHelper를 응용 프로그램 폴더로 직접 끌어다 놓은 뒤 실행해 주세요.\n\n\(error.localizedDescription)"
            failed.runModal()
            NSApp.terminate(nil)
            return
        }

        // 이 인스턴스가 종료된 뒤에 새 위치의 앱을 연다 (중복 실행 방지에 걸리지 않도록).
        let relaunch = Process()
        relaunch.executableURL = URL(fileURLWithPath: "/bin/sh")
        relaunch.arguments = ["-c", "sleep 1; open \"\(destination.path)\""]
        try? relaunch.run()
        NSApp.terminate(nil)
    }

    /// 메뉴가 없는 앱은 ⌘C/⌘V가 동작하지 않으므로 편집 메뉴를 숨겨서 둔다.
    private func installEditMenu() {
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let editItem = NSMenuItem()
        editItem.submenu = edit
        let main = NSMenu()
        main.addItem(editItem)
        NSApp.mainMenu = main
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            let view = SettingsView(openGuide: { [weak self] in self?.openGuide() })
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = "UnicodeHelper 설정"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func openGuide() {
        if guideWindow == nil {
            let view = SetupGuideView(onClose: { [weak self] in self?.guideWindow?.close() })
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = "UnicodeHelper 설정 가이드"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            guideWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        guideWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func toggleAlways() {
        settings.alwaysShow.toggle()
    }

    @objc private func resetPosition() {
        panel.resetPosition()
    }

    @objc private func refresh() {
        DispatchQueue.main.async { [self] in
            alwaysItem.state = settings.alwaysShow ? .on : .off
            let isHex = currentInputSourceID() == unicodeHexSourceID
            statusItem.button?.appearsDisabled = !isHex
            if isHex || settings.alwaysShow {
                if !panel.isVisible { panel.placeOnScreen() }
                panel.orderFrontRegardless()
            } else {
                panel.orderOut(nil)
            }
        }
    }
}

// uninstall.sh에서 호출: 로그인 항목만 해제하고 종료.
if CommandLine.arguments.contains("--unregister-login-item") {
    LoginItem.set(false)
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
