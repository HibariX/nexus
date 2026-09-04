import AppKit
import SwiftUI
import Observation

/// 标注会话状态：工具条与画布共享
@Observable
final class AnnotationState {
    /// nil = 未选工具：可拖动贴图、点选已画标注编辑
    var activeTool: Annotation.Tool? {
        didSet { onToolChanged?() }
    }
    var color: NSColor = .systemRed {
        didSet { applyToSelection { $0.color = color } }
    }
    var weight: Annotation.Weight = .regular {
        didSet { applyToSelection { $0.weight = weight } }
    }
    var annotations: [Annotation] = []
    var draft: Annotation?
    /// 聚焦遮罩：矩形框之外压暗
    var maskEnabled = false {
        didSet { onNeedsRedraw?() }
    }
    var selectedID: UUID? {
        didSet {
            // 选中标注时，工具条同步显示它的颜色/粗细（不回写）
            if let selected = selectedAnnotation {
                syncing = true
                color = selected.color
                weight = selected.weight
                syncing = false
            }
            onNeedsRedraw?()
        }
    }

    private var syncing = false

    /// 裁剪子模式：进入后框选一个矩形，⏎ 确认 / Esc 取消（不是持久标注）
    var croppingMode = false {
        didSet { onToolChanged?(); onNeedsRedraw?() }
    }
    var cropDraft: CGRect?   // 归一化裁剪框（左下原点）

    var onNeedsRedraw: (() -> Void)?
    var onToolChanged: (() -> Void)?
    var onOCR: (() -> Void)?

    // 四个终结动作：标注画完了才决定这张图去哪儿。
    // 除 onPin 外都会关掉贴图窗——点复制/保存的人本来就不想要屏幕上多一张图
    /// 贴图：留在原位继续当贴图用
    var onPin: (() -> Void)?
    /// 复制到剪贴板并关闭
    var onCopy: (() -> Void)?
    /// 存 PNG 并关闭
    var onSave: (() -> Void)?
    /// 丢弃：不写剪贴板、不落盘
    var onCancel: (() -> Void)?

    var selectedAnnotation: Annotation? {
        guard let id = selectedID else { return nil }
        return annotations.first { $0.id == id }
    }

    /// 下一个编号：现有编号最大值 +1（不维护可变计数器，删除/撤销天然自洽；中间删号不重排）
    func nextNumber() -> Int {
        (annotations.filter { $0.tool == .number }.map(\.number).max() ?? 0) + 1
    }

    /// 进入裁剪模式：清空当前工具与选中，开始框选
    func enterCropMode() {
        activeTool = nil
        selectedID = nil
        cropDraft = nil
        croppingMode = true
    }

    func cancelCrop() {
        croppingMode = false
        cropDraft = nil
    }

    /// 改色/改粗细时套用到选中的标注
    private func applyToSelection(_ mutate: (inout Annotation) -> Void) {
        guard !syncing, let id = selectedID,
              let index = annotations.firstIndex(where: { $0.id == id }) else { return }
        mutate(&annotations[index])
        onNeedsRedraw?()
    }

    func updateSelected(_ mutate: (inout Annotation) -> Void) {
        guard let id = selectedID,
              let index = annotations.firstIndex(where: { $0.id == id }) else { return }
        mutate(&annotations[index])
        onNeedsRedraw?()
    }

    func deleteSelected() {
        guard let id = selectedID else { return }
        annotations.removeAll { $0.id == id }
        selectedID = nil
        onNeedsRedraw?()
    }

    func undo() {
        guard !annotations.isEmpty else { return }
        let removed = annotations.removeLast()
        if selectedID == removed.id { selectedID = nil }
        onNeedsRedraw?()
    }
}

struct AnnotationToolbarView: View {
    @Bindable var state: AnnotationState

    var body: some View {
        HStack(spacing: 10) {
            // 选择/编辑模式：点已画标注即可选中、拖动、改形
            Button {
                state.cancelCrop()
                state.activeTool = nil
            } label: {
                Image(systemName: "cursorarrow")
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 26, height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(state.activeTool == nil && !state.croppingMode
                                  ? CyberpunkTheme.matrix.opacity(0.82) : .clear)
                    )
                    .foregroundStyle(state.activeTool == nil && !state.croppingMode
                                     ? CyberpunkTheme.windowBackground : CyberpunkTheme.secondaryText)
            }
            .buttonStyle(.plain)
            .help("选择/编辑已画标注 (V)")

            Divider().frame(height: 16)

            // 工具
            HStack(spacing: 2) {
                ForEach(Annotation.Tool.allCases, id: \.self) { tool in
                    Button {
                        // 点已选中的工具再次点击 = 取消选择，回到拖动/编辑模式
                        state.activeTool = (state.activeTool == tool) ? nil : tool
                        state.selectedID = nil
                    } label: {
                        Image(systemName: tool.symbolName)
                            .font(.system(size: 13, weight: .medium))
                            .frame(width: 26, height: 24)
                            .background(
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(state.activeTool == tool
                                          ? CyberpunkTheme.matrix.opacity(0.82) : .clear)
                            )
                            .foregroundStyle(state.activeTool == tool
                                             ? CyberpunkTheme.windowBackground : CyberpunkTheme.secondaryText)
                    }
                    .buttonStyle(.plain)
                    .help("\(tool.title) (⌘\(tool.shortcutIndex))")
                }
            }

            Divider().frame(height: 16)

            // 粗细（作用于新标注；有选中项时改选中项）
            HStack(spacing: 3) {
                ForEach(Annotation.Weight.allCases, id: \.self) { weight in
                    Button {
                        state.weight = weight
                    } label: {
                        Circle()
                            .fill(state.weight == weight ? CyberpunkTheme.matrix : CyberpunkTheme.mutedText)
                            .frame(width: weight.dotSize, height: weight.dotSize)
                            .frame(width: 18, height: 24)
                            .background(
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(state.weight == weight
                                          ? CyberpunkTheme.matrix.opacity(0.14) : .clear)
                            )
                    }
                    .buttonStyle(.plain)
                    .help(weight.title)
                }
            }

            Divider().frame(height: 16)

            // 颜色（作用于新标注；有选中项时改选中项）
            HStack(spacing: 5) {
                ForEach(Array(Annotation.palette.enumerated()), id: \.offset) { _, color in
                    Button {
                        state.color = color
                    } label: {
                        Circle()
                            .fill(Color(nsColor: color))
                            .frame(width: 14, height: 14)
                            .overlay(
                                Circle().strokeBorder(
                                    state.color == color ? CyberpunkTheme.matrix : CyberpunkTheme.secondaryText.opacity(0.35),
                                    lineWidth: state.color == color ? 2 : 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider().frame(height: 16)

            // 聚焦遮罩：矩形框外压暗
            Button {
                state.maskEnabled.toggle()
            } label: {
                Image(systemName: state.maskEnabled ? "circle.rectangle.filled.pattern.diagonalline" : "circle.rectangle.dashed")
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 26, height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                                    .fill(state.maskEnabled ? CyberpunkTheme.matrix.opacity(0.82) : .clear)
                    )
                    .foregroundStyle(state.maskEnabled ? CyberpunkTheme.windowBackground : CyberpunkTheme.secondaryText)
            }
            .buttonStyle(.plain)
            .help("聚焦遮罩：矩形框外压暗")

            // 裁剪
            Button {
                state.enterCropMode()
            } label: {
                Image(systemName: "crop")
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 26, height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(state.croppingMode ? CyberpunkTheme.matrix.opacity(0.82) : .clear)
                    )
                    .foregroundStyle(state.croppingMode ? CyberpunkTheme.windowBackground : CyberpunkTheme.secondaryText)
            }
            .buttonStyle(.plain)
            .help("裁剪：框选后 ⏎ 确认")

            Divider().frame(height: 16)

            Button { state.onOCR?() } label: {
                Image(systemName: "text.viewfinder")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help("OCR 识别文字")

            Divider().frame(height: 16)

            // 删除选中项
            Button {
                state.deleteSelected()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help("删除选中标注 (⌫)")
            .disabled(state.selectedID == nil)

            Button {
                state.undo()
            } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help("撤销 (⌘Z)")
            .disabled(state.annotations.isEmpty)

            Divider().frame(height: 16)

            // 去向：贴图留在屏幕上，其余三个都会关掉这张图
            Button { state.onCancel?() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help("取消，丢弃这次截图 (Esc)")

            Button { state.onSave?() } label: {
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help("保存为 PNG 并关闭 (⌘S)")

            Button { state.onCopy?() } label: {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help("复制到剪贴板并关闭 (⌘C)")

            Button {
                state.onPin?()
            } label: {
                Image(systemName: "pin.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(CyberpunkTheme.windowBackground)
                    .frame(width: 32, height: 24)
                    .background(RoundedRectangle(cornerRadius: 5).fill(CyberpunkTheme.matrix.opacity(0.9)))
            }
            .buttonStyle(.plain)
            .help("贴图：留在屏幕上 (⏎)")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(CyberpunkTheme.surface, in: RoundedRectangle(cornerRadius: 9))
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .strokeBorder(CyberpunkTheme.border.opacity(0.9), lineWidth: 1)
        )
        .shadow(color: CyberpunkTheme.matrix.opacity(0.14), radius: 10)
        .tint(CyberpunkTheme.matrix)
        .preferredColorScheme(.dark)
        .fixedSize()
    }
}

/// 承载工具条的子窗口：挂在贴图窗下方，随贴图移动
final class AnnotationToolbarPanel: NSPanel {
    init(state: AnnotationState) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 430, height: 40),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear
        appearance = NSAppearance(named: .darkAqua)
        hasShadow = true
        let hosting = NSHostingView(rootView: AnnotationToolbarView(state: state))
        hosting.frame = contentRect(forFrameRect: frame)
        contentView = hosting
        setContentSize(hosting.fittingSize)
    }

    override var canBecomeKey: Bool { false }
}
