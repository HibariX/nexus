import AppKit
import SwiftUI

/// 上报工作台各格子已布局的全局坐标 frame，供选中项可见性判断
private struct WorkbenchCellFrameKey: PreferenceKey {
    static var defaultValue: [ResultItem.ID: CGRect] = [:]
    static func reduce(value: inout [ResultItem.ID: CGRect], nextValue: () -> [ResultItem.ID: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

/// 空态工作台：以图标网格展示全部 App（仿 macOS 工作台）。
struct WorkbenchGridView: View {
    @Bindable var coordinator: SearchCoordinator
    let executor: ActionExecutor
    /// 首屏错峰入场窗口：true 之后出现的格子立即显示（修复快速滚动跟不上）
    @State private var revealed = false
    /// 已布局格子的全局坐标 frame，用于判断选中项是否已在可视区（避免横挪相邻项触发无谓滚动）
    @State private var cellFrames: [ResultItem.ID: CGRect] = [:]

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: 16),
        count: WorkbenchLayout.columns
    )

    var body: some View {
        let items = coordinator.flatItems
        // 外层 GeometryReader 提供可视窗口的全局坐标，用于精确判断选中格是否已滚出可视区。
        GeometryReader { geo in
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !coordinator.workbenchSuggestions.isEmpty {
                        suggestionsSection(items: coordinator.workbenchSuggestions)
                    }
                    LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        WorkbenchCell(item: item, index: index, revealed: revealed,
                                      isSelected: coordinator.selection == item.id)
                            .equatable()
                            .id(item.id)
                            .background(
                                GeometryReader { geo in
                                    Color.clear.preference(
                                        key: WorkbenchCellFrameKey.self,
                                        value: [item.id: geo.frame(in: .global)]
                                    )
                                }
                            )
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
                }
                .padding(20)
            }
            .scrollIndicators(.hidden)
            .onPreferenceChange(WorkbenchCellFrameKey.self) { cellFrames = $0 }
            .onAppear {
                // 给首屏错峰一个短暂窗口，之后滚出的格子立即显示
                guard !revealed else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { revealed = true }
            }
            .onChange(of: coordinator.selection) { _, newValue in
                guard let id = newValue else { return }
                // 仅当选中格子完整处于可视区才不滚；只要它溢出视口（含被底部/顶部裁剪），
                // 就滚动到完全可见——避免出现「选中项露一半」的情况。
                // frame 尚未就绪（如首次渲染）时保守滚动到中心。
                let viewport = geo.frame(in: .global)
                if let frame = cellFrames[id], viewport != .zero {
                    if !viewport.contains(frame) {
                        proxy.scrollTo(id, anchor: .center)
                    }
                } else {
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
    }

    private func select(_ item: ResultItem) {
        coordinator.selection = item.id
    }

    /// 工作台顶部「应用建议」行：标题 + 横向可滚动的小 tile 列表。
    @ViewBuilder
    private func suggestionsSection(items: [ResultItem]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("建议")
                .font(CyberpunkTheme.monoFont(size: 11, weight: .semibold))
                .foregroundStyle(CyberpunkTheme.matrix)
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(items.prefix(WorkbenchLayout.columns)) { item in
                    WorkbenchCell(item: item, index: 0, revealed: true,
                                  isSelected: coordinator.selection == "suggestion-\(item.id)")
                        .id("suggestion-\(item.id)")
                        .onTapGesture {
                            // 建议项用独立前缀 id 选中，避免与网格同 id 应用格子抢高亮；
                            // executeSelected 会经 selectedItem 从 suggestions 反向解析出真实项
                            coordinator.selection = "suggestion-\(item.id)"
                            coordinator.executeSelected(executor: executor)
                        }
                }
            }
        }
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

/// 建议行直接复用网格的 WorkbenchCell（统一图标 64 / 标签 / 透明底 / 选中高亮），无需独立小 tile。
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
            if isSelected {
                if reduceMotion {
                    // 减少动态：静态霓虹描边，不做流光
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(
                            LinearGradient(
                                colors: [CyberpunkTheme.matrix, CyberpunkTheme.cyan],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.4
                        )
                } else {
                    NeonCometBorder(cornerRadius: 12)
                }
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.clear, lineWidth: 1)
            }
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

/// 选中项的霓虹「追光」跑马灯：一个单独的高亮亮块沿边框循环跑一圈。
/// 用 `trim` 截取周长上的一段（约占 12%），随毫秒时钟从 0→1 推进；跨过周长起点时
/// 补画末端一段实现无缝环绕。相比之下 dash 多光点会显得零碎，单一亮块更利落。
/// 「减少动态」时由调用方降级为静态描边，本组件不自行管理。
private struct NeonCometBorder: View {
    var cornerRadius: CGFloat
    /// 跑完一圈的时长
    var duration: Double = 1.8
    /// 亮块占周长的比例
    private let cometFraction: CGFloat = 0.12

    var body: some View {
        // TimelineView 以 ~60fps 驱动 t，让亮块沿边框平滑移动
        TimelineView(.animation(minimumInterval: 1 / 60)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: duration) / duration
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                let start = CGFloat(t)
                let len = cometFraction
                let end = start + len
                ZStack {
                    cometSegment(from: start, to: min(end, 1))
                    // 亮块跨过周长起点(0)时，在开头补画溢出的一段，保证环绕连续
                    if end > 1 {
                        cometSegment(from: 0, to: end - 1)
                    }
                }
                .frame(width: w, height: h)
            }
            .compositingGroup()
            .shadow(color: CyberpunkTheme.matrix.opacity(0.7), radius: 6)
        }
    }

    private func cometSegment(from start: CGFloat, to end: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .trim(from: start, to: end)
            .stroke(
                CyberpunkTheme.matrixBright,
                style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round)
            )
    }
}
