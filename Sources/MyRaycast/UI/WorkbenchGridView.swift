import AppKit
import SwiftUI

/// 空态工作台：以图标网格展示全部 App（仿 macOS 工作台）。
struct WorkbenchGridView: View {
    @Bindable var coordinator: SearchCoordinator
    let executor: ActionExecutor

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: 16),
        count: WorkbenchLayout.columns
    )

    var body: some View {
        let items = coordinator.flatItems
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(items) { item in
                        WorkbenchCell(item: item, isSelected: coordinator.selection == item.id)
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
    let isSelected: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    // 只有 id 或选中态变化才重绘：selection 改变时未涉及的格子被跳过，不重取图标
    static func == (lhs: WorkbenchCell, rhs: WorkbenchCell) -> Bool {
        lhs.item.id == rhs.item.id && lhs.isSelected == rhs.isSelected
    }

    var body: some View {
        VStack(spacing: 8) {
            IconView(source: item.icon)
                .frame(width: 64, height: 64)
                .scaleEffect(reduceMotion ? 1 : (isHovered ? 1.035 : 1))
            Text(item.title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(CyberpunkTheme.text)
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
                    isSelected ? CyberpunkTheme.matrix.opacity(0.78) : .clear,
                    lineWidth: 1
                )
        }
        .shadow(
            color: isSelected ? CyberpunkTheme.matrix.opacity(0.17) : .clear,
            radius: 10
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
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
