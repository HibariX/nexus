import AppKit

/// 可滚动、可选择但不可编辑的剪贴板文本贴窗。
final class PinTextPanel: NSPanel {
    var onClose: ((PinTextPanel) -> Void)?

    private let pinTextView: PinTextView

    init(text: NSAttributedString, near location: NSPoint) {
        let screen = NSScreen.screens.first { NSMouseInRect(location, $0.frame, false) } ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 900, height: 700)
        let size = Self.initialSize(for: text, visibleFrame: visibleFrame)
        let frame = Self.frame(around: location, size: size, constrainedTo: visibleFrame)

        pinTextView = PinTextView()
        super.init(
            contentRect: frame,
            styleMask: [.titled, .fullSizeContentView, .resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isFloatingPanel = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = CyberpunkTheme.windowNSColor
        appearance = NSAppearance(named: .darkAqua)
        hasShadow = true
        isMovableByWindowBackground = true
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        styleMask.insert(.fullSizeContentView)
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
        minSize = NSSize(width: 280, height: 160)
        maxSize = NSSize(width: visibleFrame.width * 0.8, height: visibleFrame.height * 0.8)

        let container = PinTextContainerView()
        container.onRequestClose = { [weak self] in self?.closePin() }
        contentView = container

        pinTextView.isEditable = false
        pinTextView.isSelectable = true
        pinTextView.isRichText = true
        pinTextView.drawsBackground = false
        pinTextView.textContainerInset = NSSize(width: 10, height: 10)
        pinTextView.isAutomaticLinkDetectionEnabled = true
        pinTextView.linkTextAttributes = [
            .foregroundColor: CyberpunkTheme.matrixNSColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
        ]
        pinTextView.usesFindBar = true
        pinTextView.frame = NSRect(x: 0, y: 0, width: size.width - 20, height: size.height - 38)
        pinTextView.minSize = NSSize(width: 0, height: size.height - 38)
        pinTextView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        pinTextView.textStorage?.setAttributedString(text)
        pinTextView.onRequestClose = { [weak self] in self?.closePin() }
        pinTextView.setAccessibilityLabel("剪贴板文本")

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.documentView = pinTextView
        container.addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 10),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -10),
            scrollView.topAnchor.constraint(equalTo: container.topAnchor, constant: 28),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -10),
        ])
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func makeKeyAndOrderFront(_ sender: Any?) {
        super.makeKeyAndOrderFront(sender)
        makeFirstResponder(pinTextView)
    }

    private func closePin() {
        onClose?(self)
        close()
    }

    private static func initialSize(for text: NSAttributedString, visibleFrame: NSRect) -> NSSize {
        let maxWidth = min(560, visibleFrame.width * 0.8)
        let maxHeight = visibleFrame.height * 0.8
        let singleLine = text.boundingRect(
            with: NSSize(width: 10_000, height: 10_000),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        let width = min(max(280, ceil(singleLine.width) + 48), maxWidth)
        let wrapped = text.boundingRect(
            with: NSSize(width: width - 40, height: 100_000),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        let height = min(max(160, ceil(wrapped.height) + 66), maxHeight)
        return NSSize(width: width, height: height)
    }

    private static func frame(around location: NSPoint, size: NSSize, constrainedTo bounds: NSRect) -> NSRect {
        let proposed = NSPoint(x: location.x - size.width / 2, y: location.y - size.height / 2)
        let origin = NSPoint(
            x: min(max(proposed.x, bounds.minX), bounds.maxX - size.width),
            y: min(max(proposed.y, bounds.minY), bounds.maxY - size.height)
        )
        return NSRect(origin: origin, size: size)
    }
}

private final class PinTextView: NSTextView {
    var onRequestClose: (() -> Void)?

    init() {
        let storage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        let container = NSTextContainer(
            containerSize: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        )
        storage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(container)
        super.init(frame: .zero, textContainer: container)

        autoresizingMask = [.width]
        textContainer?.widthTracksTextView = true
        isVerticallyResizable = true
        isHorizontallyResizable = false
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if event.keyCode == 53 || (modifiers == .command && event.charactersIgnoringModifiers == "w") {
            onRequestClose?()
            return
        }
        super.keyDown(with: event)
    }
}

private final class PinTextContainerView: NSView {
    var onRequestClose: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        updateAppearance()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var mouseDownCanMoveWindow: Bool { true }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            onRequestClose?()
            return
        }
        super.mouseDown(with: event)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let handle = NSRect(x: bounds.midX - 18, y: bounds.maxY - 15, width: 36, height: 4)
        CyberpunkTheme.matrixNSColor.withAlphaComponent(0.7).setFill()
        NSBezierPath(roundedRect: handle, xRadius: 2, yRadius: 2).fill()
    }

    private func updateAppearance() {
        layer?.backgroundColor = CyberpunkTheme.windowNSColor.withAlphaComponent(0.96).cgColor
        layer?.borderColor = CyberpunkTheme.borderNSColor.withAlphaComponent(0.8).cgColor
        layer?.borderWidth = 1
        layer?.cornerRadius = 8
        layer?.masksToBounds = true
        needsDisplay = true
    }
}
