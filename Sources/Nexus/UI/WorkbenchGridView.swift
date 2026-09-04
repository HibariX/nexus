import AppKit
import SwiftUI

/// 空态工作台：以图标网格展示全部 App（仿 macOS 工作台）。
struct WorkbenchGridView: View {
    @Bindable var coordinator: SearchCoordinator
    let executor: ActionExecutor
    /// 首屏错峰入场窗口：true 之后出现的格子立即显示（修复快速滚动跟不上）
    @State private var revealed = false

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: 16),
        count: WorkbenchLayout.columns
    )

    var body: some View {
        let items = coordinator.flatItems
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        WorkbenchCell(item: item, index: index, revealed: revealed,
                                      isSelected: coordinator.selection == item.id)
                            .equatable()
                            .id(item.id)
                            .onTapGesture {
                                coordinator.selection = item.id
                                coordinator.executeSelected(executor: executor)
                            }
                            .contextMenu {
                                if let path = item.applicationPath {
                                    Button {
                                        select(item)
                                        coordinator.executeSelected(executor: executor)
                                    } label: {
                                        Label("打开", systemImage: "arrow.up.forward.app")
                                    }

                                    Divider()

                                    Button {
                                        select(item)
                                        coordinator.onDismiss?()
                                        executor.execute(.revealInFinder(path: path))
                                    } label: {
                                        Label("在 Finder 中显示", systemImage: "folder")
                                    }

                                    Button {
                                        select(item)
                                        _ = coordinator.beginAliasEditing()
                                    } label: {
                                        Label("设置别名…", systemImage: "tag")
                                    }

                                    Divider()

                                    Button {
                                        select(item)
                                        executor.execute(.copyText(path))
                                    } label: {
                                        Label("复制应用路径", systemImage: "doc.on.doc")
                                    }

                                    Divider()

                                    Button(role: .destructive) {
                                        select(item)
                                        confirmUninstall(item)
                                    } label: {
                                        Label("卸载…", systemImage: "trash")
                                    }
                                }
                            }
                    }
                }
                .padding(20)
            }
            .scrollIndicators(.hidden)
            .onAppear {
                // 给首屏错峰一个短暂窗口，之后滚出的格子立即显示
                guard !revealed else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { revealed = true }
            }
            .onChange(of: coordinator.selection) { _, newValue in
                if let id = newValue {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
            .task(id: items.map(\.id)) {
                let paths = items.compactMap { item -> String? in
                    switch item.icon {
                    case .appBundle(let path), .file(let path): path
                    default: nil
                    }
                }
                await AppIconCache.shared.prefetch(paths: paths)
            }
        }
    }

    private func select(_ item: ResultItem) {
        coordinator.selection = item.id
    }

    /// 卸载前弹确认框；确认后才把 .app 移到废纸篓
    private func confirmUninstall(_ item: ResultItem) {
        guard let path = item.applicationPath else { return }
        let alert = NSAlert()
        alert.messageText = "确定卸载“\(item.title)”吗？"
        alert.informativeText = "“\(item.title)”将被移到废纸篓。若该应用仍在运行，请先退出应用。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "移至废纸篓")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        executor.execute(.uninstallApp(path: path))
    }
}

private struct WorkbenchCell: View, Equatable {
    let item: ResultItem
    let index: Int
    let revealed: Bool
    let isSelected: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false
    @State private var pulsate = false
    @State private var appeared = false

    // 只有 id 或选中态变化才重绘：selection 改变时未涉及的格子被跳过，不重取图标
    static func == (lhs: WorkbenchCell, rhs: WorkbenchCell) -> Bool {
        lhs.item.id == rhs.item.id && lhs.index == rhs.index && lhs.revealed == rhs.revealed && lhs.isSelected == rhs.isSelected
    }

    var body: some View {
        VStack(spacing: 8) {
            IconView(source: item.icon)
                .frame(width: 64, height: 64)
                .scaleEffect(reduceMotion ? 1 : (isHovered ? 1.035 : 1))
            CyberpunkGlitchText(
                text: item.title,
                font: .system(size: 13, weight: .medium),
                glitching: isSelected
            )
            .lineLimit(1)
            .truncationMode(.tail)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(backgroundColor)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    isSelected
                        ? AnyShapeStyle(
                            LinearGradient(
                                colors: [CyberpunkTheme.matrix, CyberpunkTheme.cyan],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        : AnyShapeStyle(Color.clear),
                    lineWidth: isSelected ? 1.4 : 1
                )
        }
        .overlay(alignment: .top) {
            // 顶部霓虹灯管：仅选中时点亮，随呼吸明暗，模拟赛博灯光条
            if isSelected {
                Capsule()
                    .fill(CyberpunkTheme.matrix.opacity(pulsate ? 0.9 : 0.65))
                    .frame(height: 2)
                    .padding(.horizontal, 16)
                    .shadow(
                        color: CyberpunkTheme.matrix.opacity(pulsate ? 0.55 : 0.35),
                        radius: pulsate ? 7 : 4
                    )
            }
        }
        .shadow(
            color: isSelected
                ? CyberpunkTheme.matrix.opacity(pulsate ? 0.34 : 0.18)
                : (isHovered ? CyberpunkTheme.cyan.opacity(0.16) : .clear),
            radius: isSelected ? 12 : 10
        )
        // 错峰入场：应用列表出现时逐格自下而上淡入 + 轻微放大
        .opacity(appeared || reduceMotion ? 1 : 0)
        .offset(y: reduceMotion ? 0 : (appeared ? 0 : 12))
        .scaleEffect(reduceMotion ? 1 : (appeared ? 1 : 0.92))
        .animation(
            reduceMotion || revealed ? nil : .easeOut(duration: 0.3).delay(Double(index) * 0.03),
            value: appeared
        )
        // revealed 翻转为 true 后，onAppear 设置的 appeared 立即生效，不再带延迟动画
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onAppear {
            appeared = true
            guard !reduceMotion else { return }
            pulsate = false
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
                pulsate = true
            }
        }
        .animation(interactionAnimation, value: isHovered)
        .animation(interactionAnimation, value: isSelected)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item.title)
        .accessibilityHint("点击打开，右键显示更多操作")
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var backgroundColor: Color {
        if isSelected { return CyberpunkTheme.matrix.opacity(0.15) }
        if isHovered { return CyberpunkTheme.cyan.opacity(0.08) }
        return .clear
    }

    private var interactionAnimation: Animation? {
        reduceMotion ? nil : .easeOut(duration: 0.14)
    }
}

private extension ResultItem {
    var applicationPath: String? {
        guard case .launchApp(let path) = action else { return nil }
        return path
    }
}
