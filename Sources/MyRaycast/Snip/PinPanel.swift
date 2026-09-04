import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Snipaste 式置顶贴图窗。
/// 普通模式：按住拖动移位；滚轮/捏合/⌘+·⌘- 缩放（⌘0 还原）；⌘C 复制；双击/Esc 关闭。
/// 标注模式：工具条选矩形/直线/箭头/文字，拖拽绘制，⌘Z 撤销，⏎/Esc/✓ 完成并烙进图片。
final class PinPanel: NSPanel {
    private var image: NSImage
    private var imageAspect: CGFloat  // 高/宽（aspectRatio 与 NSWindow 属性重名）；裁剪会改变，故为 var
    private let settings: AppSettings
    var onClose: ((PinPanel) -> Void)?

    private static let minScale: CGFloat = 0.1
    private static let maxScale: CGFloat = 5.0
    private var originalSize: NSSize

    private var imageView: PinImageView!

    // 标注
    private var annotationState: AnnotationState?
    private var toolbarPanel: AnnotationToolbarPanel?
    /// 标注期间把选区之外的屏幕压暗
    private let dimming = AnnotationDimming()
    /// 上次 OCR 的结果，key 是识别时那张图的对象身份。裁剪会换掉 image，
    /// 对象身份跟着变，缓存自然失效，不需要额外的失效逻辑
    private var ocrCache: (imageID: ObjectIdentifier, text: String)?
    /// 同上，缓存已编码的 PNG，省掉重复的压缩
    private var pngCache: (imageID: ObjectIdentifier, data: Data)?
    var isAnnotating: Bool { annotationState != nil }

    /// 原位贴图：窗口 frame 与截图区域重合（框选完不挪窝）
    convenience init(image: NSImage, exactFrame: NSRect, settings: AppSettings) {
        self.init(image: image, contentRect: exactFrame, settings: settings)
    }

    /// 居中于 location 贴图（剪贴板贴图等无原位信息的场景）
    convenience init(image: NSImage, near location: NSPoint, settings: AppSettings) {
        // Retina 截图是 2x 像素，用 point 尺寸展示才 1:1
        var size = image.size
        let screen = NSScreen.screens.first { NSMouseInRect(location, $0.frame, false) } ?? NSScreen.main
        if let screen {
            let maxW = screen.visibleFrame.width * 0.9
            let maxH = screen.visibleFrame.height * 0.9
            if size.width > maxW || size.height > maxH {
                let ratio = min(maxW / size.width, maxH / size.height)
                size = NSSize(width: size.width * ratio, height: size.height * ratio)
            }
        }
        let origin = NSPoint(x: location.x - size.width / 2, y: location.y - size.height / 2)
        self.init(image: image, contentRect: NSRect(origin: origin, size: size), settings: settings)
    }

    private init(image: NSImage, contentRect: NSRect, settings: AppSettings) {
        self.image = image
        self.settings = settings
        originalSize = contentRect.size
        imageAspect = contentRect.height / max(contentRect.width, 1)

        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isFloatingPanel = true
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        appearance = NSAppearance(named: .darkAqua)
        hasShadow = true

        let view = PinImageView(image: image)
        view.onDoubleClick = { [weak self] in self?.closePin() }
        view.onCopy = { [weak self] in self?.copyImage() }
        view.onResetSize = { [weak self] in self?.resetSize() }
        view.onRequestClose = { [weak self] in self?.closePin() }
        view.onRequestAnnotate = { [weak self] in self?.beginAnnotation() }
        imageView = view
        contentView = view
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// 兜底：遮罩是全屏且会吞点击的，任何一条关闭路径漏掉清理，
    /// 屏幕就永远暗着且点不动了
    override func close() {
        dimming.hide()
        super.close()
    }

    // MARK: - 标注模式

    /// dimmed=false 用于整屏标注（演讲模式）：整块屏就是标注区，
    /// 没有「选区之外」可压暗，铺遮罩纯属多两个全屏窗口
    func beginAnnotation(dimmed: Bool = true) {
        guard annotationState == nil else { return }
        let state = AnnotationState()
        state.onNeedsRedraw = { [weak self] in self?.imageView.needsDisplay = true }
        state.onToolChanged = { [weak self] in
            guard let self else { return }
            // 切工具时把输入中的文字落定；同步光标（选工具=十字，未选=箭头）
            self.imageView.commitPendingText()
            self.invalidateCursorRects(for: self.imageView)
        }
        state.onPin = { [weak self] in self?.endAnnotation() }
        state.onCopy = { [weak self] in self?.copyAndClose() }
        state.onSave = { [weak self] in self?.saveAndClose() }
        state.onCancel = { [weak self] in self?.discardPin() }
        state.onOCR = { [weak self] in self?.runOCR() }
        annotationState = state
        imageView.annotationState = state
        // 选区之外压暗，接着框选的遮罩往下演
        if dimmed { dimming.show(hole: frame) }
        // 趁用户标注这几秒把 Vision 模型加载掉，点 OCR 时就不用等冷启动了
        OCRService.prewarm(languages: settings.ocrLanguages)

        let toolbar = AnnotationToolbarPanel(state: state)
        // 跟随贴图窗的层级：整屏标注会把贴图窗提到 .screenSaver 去盖菜单栏和 Dock，
        // 工具条不跟上就会被压在下面看不见
        toolbar.level = level
        toolbarPanel = toolbar
        addChildWindow(toolbar, ordered: .above)  // 子窗口随贴图移动
        layoutToolbar()
        toolbar.orderFront(nil)
        makeKeyAndOrderFront(nil)
    }

    /// 「贴图」：把标注烘焙进图，收起工具栏和遮罩，图留在原位继续当贴图用。
    /// updatePasteboard 为 false 表示调用方已经写过剪贴板了，别再写第二遍
    private func endAnnotation(updatePasteboard: Bool = true) {
        guard let state = annotationState else { return }
        imageView.commitPendingText()
        let didAnnotate = !state.annotations.isEmpty
        if didAnnotate {
            image = AnnotationRenderer.bake(annotations: state.annotations, into: image,
                                            masked: state.maskEnabled)
            imageView.updateImage(image)
        }
        teardownAnnotation()
        imageView.needsDisplay = true
        // 截图时已经复制过一份原图，标注改了内容就得把剪贴板换成最终版。
        // 没画任何标注时不重复写，否则剪贴板历史里会多出一条一模一样的
        if didAnnotate && updatePasteboard { copyImage() }
    }

    /// 只收起标注 UI，不动图、不碰剪贴板。取消那条路要的就是这个
    private func teardownAnnotation() {
        if let toolbar = toolbarPanel {
            removeChildWindow(toolbar)
            toolbar.orderOut(nil)
        }
        toolbarPanel = nil
        annotationState = nil
        imageView.annotationState = nil
        dimming.hide()
    }

    private func layoutToolbar() {
        guard let toolbar = toolbarPanel else { return }
        let size = toolbar.frame.size
        var x = frame.midX - size.width / 2
        var y = frame.minY - size.height - 8
        // 贴图在屏幕底部时工具条翻到上方
        if let screen = screen ?? NSScreen.main {
            let visible = screen.visibleFrame
            if y < visible.minY {
                let above = frame.maxY + 8
                // 上下都放不下——整屏标注就是这种情况——就收进屏幕内侧底部，
                // 否则工具条会被顶到屏幕外面去
                y = (above + size.height <= visible.maxY) ? above : visible.minY + 8
            }
            x = min(max(x, visible.minX + 4), visible.maxX - size.width - 4)
        }
        toolbar.setFrameOrigin(NSPoint(x: x, y: y))
    }

    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        super.setFrame(frameRect, display: flag)
        layoutToolbar()
    }

    // MARK: - 缩放

    override func scrollWheel(with event: NSEvent) {
        guard !isAnnotating else { return }  // 标注中锁定尺寸，保证落点精确
        zoom(by: 1 + event.scrollingDeltaY * 0.01)
    }

    override func magnify(with event: NSEvent) {
        guard !isAnnotating else { return }
        zoom(by: 1 + event.magnification)
    }

    /// 锚定鼠标位置缩放；鼠标不在窗内（键盘缩放）则锚定窗口中心
    private func zoom(by factor: CGFloat) {
        let currentScale = frame.width / max(originalSize.width, 1)
        let newScale = min(max(currentScale * factor, Self.minScale), Self.maxScale)
        let newWidth = originalSize.width * newScale
        let newHeight = newWidth * imageAspect

        let mouse = NSEvent.mouseLocation
        let anchor: NSPoint
        let relX: CGFloat
        let relY: CGFloat
        if NSMouseInRect(mouse, frame, false) {
            anchor = mouse
            relX = (mouse.x - frame.minX) / max(frame.width, 1)
            relY = (mouse.y - frame.minY) / max(frame.height, 1)
        } else {
            anchor = NSPoint(x: frame.midX, y: frame.midY)
            relX = 0.5
            relY = 0.5
        }
        let newOrigin = NSPoint(x: anchor.x - newWidth * relX, y: anchor.y - newHeight * relY)
        setFrame(NSRect(x: newOrigin.x, y: newOrigin.y, width: newWidth, height: newHeight),
                 display: true)
    }

    private func resetSize() {
        let center = NSPoint(x: frame.midX, y: frame.midY)
        setFrame(NSRect(x: center.x - originalSize.width / 2,
                        y: center.y - originalSize.height / 2,
                        width: originalSize.width, height: originalSize.height),
                 display: true, animate: true)
    }

    // MARK: - 键盘

    /// LSUIElement 应用没有主菜单，⌘A/⌘C/⌘V/⌘X/⌘Z 不会被编辑菜单路由。
    /// 文字标注输入中时，手动把标准编辑快捷键转发给 field editor，
    /// 否则 ⌘A 会落到 keyDown 触发「标注」、⌘C 变成复制贴图。
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command),
           let editor = firstResponder as? NSTextView, editor.isFieldEditor {
            switch event.charactersIgnoringModifiers {
            case "a": editor.selectAll(nil); return true
            case "c": editor.copy(nil); return true
            case "v": editor.paste(nil); return true
            case "x": editor.cut(nil); return true
            case "z":
                if event.modifierFlags.contains(.shift) {
                    editor.undoManager?.redo()
                } else {
                    editor.undoManager?.undo()
                }
                return true
            default: break
            }
        }
        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        // 裁剪子模式优先：⏎ 确认，Esc 取消，其它键吞掉
        if let state = annotationState, state.croppingMode {
            if event.keyCode == 36 { confirmCrop() }       // Return
            else if event.keyCode == 53 { state.cancelCrop() }  // Esc
            return
        }

        if isAnnotating {
            if event.keyCode == 36 {  // Return：贴图，留在屏幕上
                endAnnotation()
                return
            }
            if event.keyCode == 53 {  // Esc：取消，整张丢弃
                discardPin()
                return
            }
            if event.keyCode == 51 || event.keyCode == 117 {  // Delete / ⌦：删除选中标注
                annotationState?.deleteSelected()
                return
            }
            // 注意这个 isAnnotating 分支结尾是无条件 return，
            // 标注期间要用的 ⌘ 快捷键必须写在这里面，写到下面那段永远执行不到
            if event.modifierFlags.contains(.command) {
                switch event.charactersIgnoringModifiers {
                case "z": annotationState?.undo(); return
                case "c": copyAndClose(); return   // 复制走人
                case "s": saveAndClose(); return   // 保存走人
                default: break
                }
            }
            if event.charactersIgnoringModifiers == "v", !event.modifierFlags.contains(.command) {
                annotationState?.cancelCrop()
                annotationState?.activeTool = nil  // 切到选择/编辑模式
                return
            }
            // ⌘数字 = 按工具条顺序切工具（Snipaste 式）
            if event.modifierFlags.contains(.command),
               let chars = event.charactersIgnoringModifiers, let digit = Int(chars),
               let tool = Annotation.Tool.from(shortcutIndex: digit) {
                annotationState?.cancelCrop()
                annotationState?.selectedID = nil
                annotationState?.activeTool = tool
                return
            }
            super.keyDown(with: event)
            return
        }

        if event.keyCode == 53 {  // Esc
            closePin()
            return
        }
        if event.modifierFlags.contains(.command) {
            switch event.charactersIgnoringModifiers {
            // 这里只可能是贴好之后的普通模式（标注中已在上面分支处理掉）：
            // 复制/保存都只做事，图留在屏幕上
            case "c": copyImage(); return
            case "s": Task { await saveImage() }; return
            case "=", "+": zoom(by: 1.1); return
            case "-": zoom(by: 0.9); return
            case "0": resetSize(); return
            case "w": closePin(); return
            case "a": beginAnnotation(); return
            default: break
            }
        }
        super.keyDown(with: event)
    }

    override func cancelOperation(_ sender: Any?) {
        if let state = annotationState, state.croppingMode {
            state.cancelCrop()
        } else if isAnnotating {
            // 标注中的 Esc 是「取消这次截图」，不是「结束标注」——
            // 想留在屏幕上得按 ⏎ 或点贴图
            discardPin()
        } else {
            closePin()
        }
    }

    // MARK: - 复制 / 关闭

    /// 当前应输出的图：标注会话中把标注（含 blur/mask）烘焙进来；否则就是当前 image。
    private func currentImage() -> NSImage {
        imageView.commitPendingText()
        guard let state = annotationState, !state.annotations.isEmpty else { return image }
        return AnnotationRenderer.bake(annotations: state.annotations, into: image,
                                       masked: state.maskEnabled)
    }

    /// CGImage → PNG。直接走 CGImageDestination，比
    /// tiffRepresentation → NSBitmapImageRep → PNG 少一次 TIFF 编码和一次解码，
    /// 全屏图实测省 11ms（79 → 68）。剩下的都是 PNG 压缩本身，压不动，只能挪出主线程
    nonisolated private static func encodePNG(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            data, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }

    /// 多个贴图窗可能先后发起复制，大图编码慢、小图编码快，
    /// 不排序的话先发起的反而后落地。只认最后一次请求
    @MainActor private static var copyToken = 0

    /// 写 PNG 到剪贴板并闪一下绿边。截图完成、标注完成、⌘C、右键菜单都走这里。
    /// PNG 压缩全屏图要 71ms，同步做会把主线程冻住，所以挪到后台，
    /// 主线程只留写剪贴板那 0.4ms
    func copyImage() {
        let img = currentImage()
        let cacheable = img === image
        let imageID = ObjectIdentifier(img)
        imageView.flashBorder(color: .systemGreen)

        // 截图完成时已经编码过一次，之后手动 ⌘C 直接命中，同步写完立即可粘贴
        if cacheable, let cache = pngCache, cache.imageID == imageID {
            Self.writePasteboard(cache.data)
            return
        }
        guard let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }

        Self.copyToken += 1
        let token = Self.copyToken
        Task { [weak self] in
            guard let png = await Task.detached(priority: .userInitiated, operation: {
                Self.encodePNG(cg)
            }).value else { return }
            // 即使这次结果被更晚的请求盖掉，编码好的数据对本窗口仍然有效
            if let self, cacheable {
                self.pngCache = (imageID, png)
            }
            guard Self.copyToken == token else { return }  // 已有更晚的复制请求
            Self.writePasteboard(png)
        }
    }

    private static func writePasteboard(_ png: Data) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setData(png, forType: .png)
    }

    /// 复制并关闭：点复制的人要的是剪贴板内容，不是屏幕上再多一张图
    private func copyAndClose() {
        copyImage()
        closePin(pasteboardUpdated: true)
    }

    /// 保存并关闭。编码同样放后台，窗口留到写盘结束再关；失败就不关，让人看见那下红闪
    private func saveAndClose() {
        Task { [weak self] in
            guard let self, await self.saveImage() else { return }
            self.closePin()
        }
    }

    /// 取消：标注不烘焙、不落盘、不动剪贴板，直接丢掉整张图
    private func discardPin() {
        teardownAnnotation()
        onClose?(self)
        close()
    }

    /// 保存为 PNG 到设置里配置的目录（带时间戳文件名）
    @discardableResult
    private func saveImage() async -> Bool {
        guard let cg = currentImage().cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return false
        }
        let dir = URL(fileURLWithPath: settings.snipSaveDirectory)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let url = dir.appendingPathComponent("Snip-\(formatter.string(from: Date())).png")

        // 编码和写盘都在后台：全屏图光压缩就要 71ms
        let ok = await Task.detached(priority: .userInitiated) {
            guard let png = Self.encodePNG(cg) else { return false }
            do {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                try png.write(to: url, options: .atomic)
                return true
            } catch {
                return false
            }
        }.value

        imageView.flashBorder(color: ok ? .systemGreen : .systemRed)
        return ok
    }

    /// OCR：识别当前图，弹出可编辑结果窗
    private func runOCR() {
        let img = currentImage()
        let anchor = NSPoint(x: frame.midX, y: frame.maxY)

        // 没有未落定标注时 currentImage() 就是 image 本身，同一张图重复点
        // OCR 不必再识别一遍（全屏图一次要 800ms+）。有标注时每次 bake 出的都是
        // 新对象，本来也命中不了，直接跳过缓存
        let cacheable = img === image
        if cacheable, let cache = ocrCache, cache.imageID == ObjectIdentifier(img) {
            OCRResultPanel.show(text: cache.text, near: anchor)
            return
        }

        guard let cgImage = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        let languages = settings.ocrLanguages
        Task {
            let text = await OCRService.recognize(image: cgImage, languages: languages)
            if cacheable {
                ocrCache = (ObjectIdentifier(img), text)
            }
            OCRResultPanel.show(text: text, near: anchor)
        }
    }

    /// 确认裁剪：把当前 cropDraft 应用到图片与窗口
    private func confirmCrop() {
        guard let state = annotationState else { return }
        guard let norm = state.cropDraft, norm.width > 0.005, norm.height > 0.005 else {
            state.cancelCrop()
            return
        }
        performCrop(norm)
        state.cancelCrop()
    }

    /// 裁剪：先展平标注，再裁到归一化子区域，并把窗口缩到对应屏幕位置。
    /// 展平（非重映射矢量标注）是刻意取舍：跨裁剪边的箭头/文字重映射代价大，展平后失去可编辑性可接受。
    private func performCrop(_ norm: CGRect) {
        guard let state = annotationState else { return }
        imageView.commitPendingText()

        // 1. 展平所有标注（含 blur/mask）
        let flat = AnnotationRenderer.bake(annotations: state.annotations, into: image,
                                           masked: state.maskEnabled)
        guard let cg = flat.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        let pw = CGFloat(cg.width), ph = CGFloat(cg.height)

        // 2. 归一化裁剪框 → 像素裁剪矩形（CGImage 左上原点，y 翻转）
        var cropPx = CGRect(x: norm.minX * pw,
                            y: (1 - norm.minY - norm.height) * ph,
                            width: norm.width * pw,
                            height: norm.height * ph).integral
        cropPx = cropPx.intersection(CGRect(x: 0, y: 0, width: pw, height: ph))
        guard cropPx.width >= 1, cropPx.height >= 1,
              let cropped = cg.cropping(to: cropPx) else { return }

        // 3. 新图（保持 point 尺寸，Retina 1:1）
        let newPointSize = NSSize(width: norm.width * image.size.width,
                                  height: norm.height * image.size.height)
        let newImage = NSImage(cgImage: cropped, size: newPointSize)

        // 4. 新窗口 frame（屏幕坐标、zoom 无关）
        let newFrame = NSRect(x: frame.minX + norm.minX * frame.width,
                              y: frame.minY + norm.minY * frame.height,
                              width: norm.width * frame.width,
                              height: norm.height * frame.height)

        // 5. 落定：标注已展平，清空并替换图与几何
        image = newImage
        originalSize = newPointSize
        imageAspect = newPointSize.height / max(newPointSize.width, 1)
        state.annotations = []
        state.selectedID = nil
        state.maskEnabled = false
        imageView.updateImage(newImage)
        setFrame(newFrame, display: true)
        layoutToolbar()
        // 裁剪是标注期间唯一会改窗口 frame 的路径，挖洞得跟着缩
        dimming.update(hole: frame)
    }

    /// pasteboardUpdated：调用方已把最终图写进剪贴板，endAnnotation 别再写一遍
    fileprivate func closePin(pasteboardUpdated: Bool = false) {
        if isAnnotating { endAnnotation(updatePasteboard: !pasteboardUpdated) }
        onClose?(self)
        close()
    }
}

// MARK: - 内容视图

/// 显式接管鼠标事件：普通模式拖动窗口，标注模式拖拽绘制。
private final class PinImageView: NSView {
    private var image: NSImage
    var onDoubleClick: (() -> Void)?
    var onCopy: (() -> Void)?
    var onResetSize: (() -> Void)?
    var onRequestClose: (() -> Void)?
    var onRequestAnnotate: (() -> Void)?

    var annotationState: AnnotationState? {
        didSet {
            needsDisplay = true
            updateCursor()
        }
    }

    private var textEditor: NSTextField?
    private var pendingTextOrigin: CGPoint?  // 归一化
    private var editingAnnotationID: UUID?   // 双击文字重编辑时，暂存被编辑的标注

    // 编辑拖拽会话
    private enum DragMode {
        case move(last: CGPoint)              // 整体移动（归一化坐标）
        case handle(Annotation.Handle)        // 拖手柄改形
    }
    private var dragMode: DragMode?
    private var cropStart: CGPoint?   // 裁剪框选起点（归一化）
    private var hoveredID: UUID?      // 编辑态下鼠标悬停的标注
    /// 最近一次拖拽位置（归一化）。拖到一半才按下 ⇧ 时，靠它重算正方形约束
    private var lastDragPoint: CGPoint?

    init(image: NSImage) {
        self.image = image
        super.init(frame: .zero)
        wantsLayer = true
        layer?.borderWidth = 1
        layer?.borderColor = CyberpunkTheme.matrixNSColor.withAlphaComponent(0.7).cgColor
        toolTip = "拖动移位 · 滚轮缩放 · ⌘A 标注 · ⌘C 复制 · 双击/Esc 关闭"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func updateImage(_ newImage: NSImage) {
        image = newImage
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        image.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1)
        guard let state = annotationState else { return }
        let scale = bounds.width / max(image.size.width, 1)
        // 分层绘制（顺序：mask → highlight → blur → 线/字/编号），与 bake 一致
        AnnotationRenderer.drawContent(annotations: state.annotations, draft: state.draft,
                                       image: image, in: bounds.size, scale: scale,
                                       masked: state.maskEnabled)
        // 悬停高亮（编辑态、非选中项）
        if state.activeTool == nil, !state.croppingMode, let hoveredID, hoveredID != state.selectedID,
           let hovered = state.annotations.first(where: { $0.id == hoveredID }) {
            hovered.drawHover(in: bounds.size, scale: scale)
        }
        // 选中态叠加在最上层
        state.selectedAnnotation?.drawSelection(in: bounds.size, scale: scale)
        // 裁剪框
        if state.croppingMode { drawCropOverlay(state: state) }
    }

    /// 裁剪模式：框外压暗，框内亮 + 白边
    private func drawCropOverlay(state: AnnotationState) {
        let full = bounds
        guard let d = state.cropDraft, d.width > 0, d.height > 0 else {
            // 未开始框选：整幅压暗提示
            NSColor.black.withAlphaComponent(0.4).setFill()
            full.fill()
            return
        }
        let rect = NSRect(x: d.minX * bounds.width, y: d.minY * bounds.height,
                          width: d.width * bounds.width, height: d.height * bounds.height)
        NSColor.black.withAlphaComponent(0.5).setFill()
        let path = NSBezierPath(rect: full)
        path.append(NSBezierPath(rect: rect))
        path.windingRule = .evenOdd
        path.fill()
        let border = NSBezierPath(rect: rect)
        border.lineWidth = 1
        NSColor.white.setStroke()
        border.stroke()
    }

    // 面板未激活时第一次点击也直接生效
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    // 拖动自己实现，禁掉系统的背景拖动避免抢事件
    override var mouseDownCanMoveWindow: Bool { false }

    private func normalized(_ event: NSEvent) -> CGPoint {
        let p = convert(event.locationInWindow, from: nil)
        return CGPoint(x: min(max(p.x / max(bounds.width, 1), 0), 1),
                       y: min(max(p.y / max(bounds.height, 1), 0), 1))
    }

    /// 按住 ⇧ 时把矩形类标注约束成正方形。
    ///
    /// 标注坐标是归一化的（0…1），x 除以视图宽、y 除以视图高——同样的归一化增量
    /// 在屏幕上并不等长，必须换算回视图像素空间取等边再转回来，否则拖出来的是
    /// 「与画布同比例的长方形」而不是正方形。
    /// 边长另受画布边界约束，免得约束后越界又被 clamp 成长方形。
    private func constrainedToSquare(
        _ end: CGPoint, from start: CGPoint, tool: Annotation.Tool, event: NSEvent
    ) -> CGPoint {
        guard tool.isRectangular, event.modifierFlags.contains(.shift) else { return end }

        let width = max(bounds.width, 1)
        let height = max(bounds.height, 1)
        let dx = (end.x - start.x) * width
        let dy = (end.y - start.y) * height

        // 朝哪个方向拖，就只能吃到那一侧的余量
        let limitX = (dx < 0 ? start.x : 1 - start.x) * width
        let limitY = (dy < 0 ? start.y : 1 - start.y) * height
        let side = min(max(abs(dx), abs(dy)), limitX, limitY)

        return CGPoint(x: start.x + (dx < 0 ? -side : side) / width,
                       y: start.y + (dy < 0 ? -side : side) / height)
    }

    /// 命中某条标注：精确边框优先，兜底填充/矩形内部（取面积最小避免大框吞小框）
    private func annotationHit(at viewPoint: NSPoint) -> Annotation? {
        guard let state = annotationState else { return nil }
        let scale = bounds.width / max(image.size.width, 1)
        let precise = state.annotations.reversed().first {
            $0.hitTest(viewPoint, in: bounds.size, scale: scale)
        }
        let interior = state.annotations
            .filter { ($0.tool == .rect || $0.tool.isFilled) && $0.hitTest(viewPoint, in: bounds.size, scale: scale, interior: true) }
            .min { a, b in
                let ra = a.bounds(in: bounds.size, scale: scale)
                let rb = b.bounds(in: bounds.size, scale: scale)
                return ra.width * ra.height < rb.width * rb.height
            }
        return precise ?? interior
    }

    // MARK: 悬停反馈（编辑态提示可点选）

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self, userInfo: nil))
    }

    override func mouseMoved(with event: NSEvent) {
        guard let state = annotationState, state.activeTool == nil, !state.croppingMode else {
            setHovered(nil)  // 绘制/裁剪态光标交给 cursor rects（十字准星）
            return
        }
        let viewPoint = convert(event.locationInWindow, from: nil)
        let scale = bounds.width / max(image.size.width, 1)
        let hit = annotationHit(at: viewPoint)
        setHovered(hit?.id)
        // 选中项手柄上 = 改形光标；命中标注 = 手型；空白 = 箭头
        if let selected = state.selectedAnnotation,
           selected.hitHandle(viewPoint, in: bounds.size, scale: scale) != nil {
            NSCursor.crosshair.set()
        } else if hit != nil {
            NSCursor.openHand.set()
        } else {
            NSCursor.arrow.set()
        }
    }

    override func mouseExited(with event: NSEvent) {
        setHovered(nil)
    }

    private func setHovered(_ id: UUID?) {
        guard hoveredID != id else { return }
        hoveredID = id
        needsDisplay = true
    }

    // MARK: 鼠标

    override func mouseDown(with event: NSEvent) {
        lastDragPoint = nil  // 新拖拽会话，清掉上一次的残留基准
        // 非标注模式：双击关闭 / 拖动窗口
        guard let state = annotationState else {
            if event.clickCount == 2 {
                onDoubleClick?()
                return
            }
            window?.performDrag(with: event)
            return
        }

        let viewPoint = convert(event.locationInWindow, from: nil)
        let point = normalized(event)
        let scale = bounds.width / max(image.size.width, 1)

        // 裁剪模式：框选裁剪区
        if state.croppingMode {
            cropStart = point
            state.cropDraft = CGRect(origin: point, size: .zero)
            needsDisplay = true
            return
        }

        // 选工具 = 绘制新标注
        if let tool = state.activeTool {
            commitPendingText()
            // 允许直接拖拽已选中标注的手柄微调，不必先切回选择工具
            if let selected = state.selectedAnnotation,
               let handle = selected.hitHandle(viewPoint, in: bounds.size, scale: scale) {
                dragMode = .handle(handle)
                return
            }
            if tool == .text {
                beginTextInput(at: point, state: state)
            } else if tool == .number {
                // 点标注：单击立即落点（走 draft/mouseUp 会被零尺寸过滤器丢弃）
                var badge = Annotation(tool: .number, start: point, end: point,
                                       color: state.color, weight: state.weight)
                badge.number = state.nextNumber()
                state.annotations.append(badge)
                state.selectedID = badge.id
            } else {
                state.draft = Annotation(tool: tool, start: point, end: point,
                                         color: state.color, weight: state.weight)
            }
            needsDisplay = true
            return
        }

        // 未选工具 = 编辑模式：手柄 > 命中标注 > 空白
        commitPendingText()

        // 1. 已选中标注的手柄
        if let selected = state.selectedAnnotation,
           let handle = selected.hitHandle(viewPoint, in: bounds.size, scale: scale) {
            dragMode = .handle(handle)
            return
        }

        // 2. 命中某条标注（精确边框优先，兜底填充/矩形内部，取面积最小避免大框吞小框）
        if let hit = annotationHit(at: viewPoint) {
            // 双击文字 = 重新编辑内容
            if hit.tool == .text, event.clickCount == 2 {
                beginEditingText(hit, state: state)
                return
            }
            state.selectedID = hit.id
            dragMode = .move(last: point)
            return
        }

        // 3. 空白：清选中，拖动窗口
        if state.selectedID != nil {
            state.selectedID = nil
            needsDisplay = true
            return
        }
        window?.performDrag(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let state = annotationState else { return }
        let point = normalized(event)
        lastDragPoint = point

        // 裁剪框选中
        if state.croppingMode, let s = cropStart {
            state.cropDraft = CGRect(x: min(s.x, point.x), y: min(s.y, point.y),
                                     width: abs(point.x - s.x), height: abs(point.y - s.y))
            needsDisplay = true
            return
        }

        // 绘制中
        if let draft = state.draft {
            state.draft?.end = constrainedToSquare(point, from: draft.start,
                                                   tool: draft.tool, event: event)
            needsDisplay = true
            return
        }

        // 编辑拖拽
        switch dragMode {
        case .move(let last):
            let dx = point.x - last.x
            let dy = point.y - last.y
            state.updateSelected { annotation in
                annotation.start.x += dx
                annotation.start.y += dy
                annotation.end.x += dx
                annotation.end.y += dy
            }
            dragMode = .move(last: point)
        case .handle(let handle):
            state.updateSelected { annotation in
                // 拖手柄改形同样吃 ⇧：对角是固定的那个点
                switch handle {
                case .start:
                    annotation.start = constrainedToSquare(point, from: annotation.end,
                                                           tool: annotation.tool, event: event)
                case .end:
                    annotation.end = constrainedToSquare(point, from: annotation.start,
                                                         tool: annotation.tool, event: event)
                }
            }
        case nil:
            break
        }
    }

    /// 拖到一半才按下（或松开）⇧ 时不会有新的 mouseDragged，这里补一次重算，
    /// 否则要抖一下鼠标约束才生效
    override func flagsChanged(with event: NSEvent) {
        super.flagsChanged(with: event)
        guard let state = annotationState, let point = lastDragPoint else { return }

        if let draft = state.draft {
            state.draft?.end = constrainedToSquare(point, from: draft.start,
                                                   tool: draft.tool, event: event)
            needsDisplay = true
            return
        }

        if case .handle(let handle) = dragMode {
            state.updateSelected { annotation in
                switch handle {
                case .start:
                    annotation.start = constrainedToSquare(point, from: annotation.end,
                                                           tool: annotation.tool, event: event)
                case .end:
                    annotation.end = constrainedToSquare(point, from: annotation.start,
                                                         tool: annotation.tool, event: event)
                }
            }
        }
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            dragMode = nil
            lastDragPoint = nil
        }
        // 裁剪框选完成：保留 cropDraft，等 ⏎ 确认
        if let state = annotationState, state.croppingMode {
            cropStart = nil
            return
        }
        guard let state = annotationState, var draft = state.draft else { return }
        // 松手这一下同样要约束，否则正方形会在收尾时弹回长方形
        draft.end = constrainedToSquare(normalized(event), from: draft.start,
                                        tool: draft.tool, event: event)
        state.draft = nil
        // 过滤误触的零尺寸涂抹
        let dx = abs(draft.end.x - draft.start.x) * bounds.width
        let dy = abs(draft.end.y - draft.start.y) * bounds.height
        if dx > 3 || dy > 3 {
            state.annotations.append(draft)
            // 画完自动选中，方便立刻调色/调粗细
            state.selectedID = draft.id
        }
        needsDisplay = true
    }

    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()
        if annotationState == nil {
            menu.addItem(withTitle: "标注…", action: #selector(annotate), keyEquivalent: "a").target = self
            menu.addItem(withTitle: "复制图片", action: #selector(copyImage), keyEquivalent: "c").target = self
            menu.addItem(withTitle: "还原大小", action: #selector(resetSize), keyEquivalent: "0").target = self
            menu.addItem(.separator())
            menu.addItem(withTitle: "关闭贴图", action: #selector(closePin), keyEquivalent: "w").target = self
        } else {
            menu.addItem(withTitle: "撤销上一笔", action: #selector(undoAnnotation), keyEquivalent: "z").target = self
            menu.addItem(withTitle: "贴图（结束标注）", action: #selector(finishAnnotation), keyEquivalent: "").target = self
        }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    // MARK: 文字标注

    private func beginTextInput(at point: CGPoint, state: AnnotationState) {
        let viewPoint = NSPoint(x: point.x * bounds.width, y: point.y * bounds.height)
        let scale = bounds.width / max(image.size.width, 1)
        let fontSize = max(state.weight.fontSize * scale, 12)

        let field = NSTextField(frame: NSRect(x: viewPoint.x, y: viewPoint.y,
                                              width: max(bounds.width - viewPoint.x - 4, 60),
                                              height: fontSize * 1.5))
        field.font = .boldSystemFont(ofSize: fontSize)
        field.textColor = state.color
        field.backgroundColor = NSColor.black.withAlphaComponent(0.25)
        field.isBordered = false
        field.focusRingType = .none
        field.placeholderString = "输入文字，⏎ 确认"
        field.delegate = self
        addSubview(field)
        window?.makeFirstResponder(field)
        textEditor = field
        pendingTextOrigin = point
    }

    /// 双击已有文字标注：暂时移除并把内容放回输入框重新编辑
    private func beginEditingText(_ annotation: Annotation, state: AnnotationState) {
        commitPendingText()
        state.annotations.removeAll { $0.id == annotation.id }
        state.selectedID = nil
        editingAnnotationID = annotation.id
        beginTextInput(at: annotation.start, state: state)
        textEditor?.stringValue = annotation.text
        // 输入框样式跟随被编辑标注
        let scale = bounds.width / max(image.size.width, 1)
        textEditor?.font = .boldSystemFont(ofSize: max(annotation.weight.fontSize * scale, 12))
        textEditor?.textColor = annotation.color
        needsDisplay = true
    }

    /// 把正在输入的文字落为标注（切工具/完成/再点击时调用）
    func commitPendingText() {
        guard let field = textEditor, let origin = pendingTextOrigin,
              let state = annotationState else { return }
        let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            let annotation = Annotation(tool: .text, start: origin, end: origin,
                                        color: state.color, weight: state.weight, text: text)
            state.annotations.append(annotation)
            state.selectedID = annotation.id
        }
        editingAnnotationID = nil
        field.removeFromSuperview()
        textEditor = nil
        pendingTextOrigin = nil
        window?.makeFirstResponder(window?.contentView)
        needsDisplay = true
    }

    // MARK: 菜单动作

    @objc private func copyImage() { onCopy?() }
    @objc private func resetSize() { onResetSize?() }
    @objc private func closePin() { onRequestClose?() }
    @objc private func annotate() { onRequestAnnotate?() }
    @objc private func undoAnnotation() { annotationState?.undo() }
    @objc private func finishAnnotation() { annotationState?.onPin?() }

    // MARK: 光标 / 反馈

    private func updateCursor() {
        window?.invalidateCursorRects(for: self)
    }

    override func resetCursorRects() {
        // 选中工具或裁剪模式显示十字准星；未选工具可拖动，保持普通箭头
        if annotationState?.activeTool != nil || annotationState?.croppingMode == true {
            addCursorRect(bounds, cursor: .crosshair)
        }
    }

    func flashBorder(color: NSColor) {
        layer?.borderColor = color.cgColor
        layer?.borderWidth = 2
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            layer?.borderColor = CyberpunkTheme.matrixNSColor.withAlphaComponent(0.7).cgColor
            layer?.borderWidth = 1
        }
    }
}

extension PinImageView: NSTextFieldDelegate {
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            commitPendingText()
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            textEditor?.stringValue = ""
            commitPendingText()
            return true
        default:
            return false
        }
    }
}
