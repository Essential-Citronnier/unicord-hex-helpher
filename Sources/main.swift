import AppKit
import Carbon.HIToolbox

// 오버레이에 표시할 문자 목록. 필요하면 여기만 고치고 ./install.sh 다시 실행.
let symbolGroups: [(title: String, items: [String])] = [
    ("화살표", ["→", "←", "↑", "↓", "↔", "↕", "⇒", "⇐", "⇔", "↗", "↘", "↩"]),
    ("기호", ["·", "•", "…", "—", "–", "×", "÷", "±", "≈", "≠", "≤", "≥", "°", "✓", "★", "※"]),
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

final class OverlayPanel: NSPanel {
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

        let blur = DragView()
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = 12
        blur.layer?.masksToBounds = true

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 3
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 14, bottom: 12, right: 14)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let hint = NSTextField(labelWithString: "⌥ 누른 채 코드 입력")
        hint.font = .systemFont(ofSize: 11, weight: .medium)
        hint.textColor = .secondaryLabelColor
        stack.addArrangedSubview(hint)

        for group in symbolGroups {
            let header = NSTextField(labelWithString: group.title)
            header.font = .systemFont(ofSize: 10, weight: .semibold)
            header.textColor = .tertiaryLabelColor
            stack.setCustomSpacing(8, after: stack.arrangedSubviews.last!)
            stack.addArrangedSubview(header)
            for ch in group.items {
                stack.addArrangedSubview(Self.row(ch))
            }
        }

        blur.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: blur.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: blur.trailingAnchor),
            stack.topAnchor.constraint(equalTo: blur.topAnchor),
            stack.bottomAnchor.constraint(equalTo: blur.bottomAnchor),
        ])
        contentView = blur
        setContentSize(stack.fittingSize)
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

    static let originKey = "panelOrigin"

    /// 드래그로 저장한 위치가 있으면 그곳, 없으면 화면 오른쪽 가운데.
    func placeOnScreen() {
        if let saved = UserDefaults.standard.string(forKey: Self.originKey) {
            let origin = NSPointFromString(saved)
            let rect = NSRect(origin: origin, size: frame.size)
            if NSScreen.screens.contains(where: { $0.visibleFrame.intersects(rect) }) {
                setFrameOrigin(origin)
                return
            }
        }
        guard let screen = NSScreen.main else { return }
        let v = screen.visibleFrame
        let size = frame.size
        setFrameOrigin(NSPoint(x: v.maxX - size.width - 16, y: v.midY - size.height / 2))
    }

    func resetPosition() {
        UserDefaults.standard.removeObject(forKey: Self.originKey)
        placeOnScreen()
    }
}

/// 패널 전체를 잡고 끌 수 있고, 마우스를 올리면 반투명해지는 배경 뷰.
final class DragView: NSVisualEffectView {
    private let hoverAlpha: CGFloat = 0.15
    private var dragStart: NSPoint?

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
        fade(to: 0.85)  // 끄는 동안은 잘 보이게
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window, let start = dragStart else { return }
        let mouse = NSEvent.mouseLocation
        window.setFrameOrigin(NSPoint(x: mouse.x - start.x, y: mouse.y - start.y))
    }

    override func mouseUp(with event: NSEvent) {
        dragStart = nil
        if let window {
            UserDefaults.standard.set(NSStringFromPoint(window.frame.origin), forKey: OverlayPanel.originKey)
            fade(to: window.frame.contains(NSEvent.mouseLocation) ? hoverAlpha : 1)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var panel: OverlayPanel!
    private var alwaysShow = UserDefaults.standard.bool(forKey: "alwaysShow")
    private var alwaysItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        panel = OverlayPanel()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "U+"

        let menu = NSMenu()
        alwaysItem = NSMenuItem(title: "항상 표시", action: #selector(toggleAlways), keyEquivalent: "")
        alwaysItem.target = self
        alwaysItem.state = alwaysShow ? .on : .off
        menu.addItem(alwaysItem)
        let reset = NSMenuItem(title: "위치 초기화", action: #selector(resetPosition), keyEquivalent: "")
        reset.target = self
        menu.addItem(reset)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
        statusItem.menu = menu

        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(refresh),
            name: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil, suspensionBehavior: .deliverImmediately)
        NotificationCenter.default.addObserver(
            self, selector: #selector(refresh),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)

        refresh()
    }

    @objc private func toggleAlways() {
        alwaysShow.toggle()
        UserDefaults.standard.set(alwaysShow, forKey: "alwaysShow")
        alwaysItem.state = alwaysShow ? .on : .off
        refresh()
    }

    @objc private func resetPosition() {
        panel.resetPosition()
    }

    @objc private func refresh() {
        DispatchQueue.main.async { [self] in
            let isHex = currentInputSourceID() == unicodeHexSourceID
            statusItem.button?.appearsDisabled = !isHex
            if isHex || alwaysShow {
                panel.placeOnScreen()
                panel.orderFrontRegardless()
            } else {
                panel.orderOut(nil)
            }
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
