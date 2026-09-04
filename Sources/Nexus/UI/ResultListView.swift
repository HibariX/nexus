import SwiftUI

struct ResultListView: View {
    @Bindable var coordinator: SearchCoordinator
    let executor: ActionExecutor
    /// 首屏错峰入场窗口：true 之后出现的行立即显示（修复快速滚动跟不上）
    @State private var revealed = false

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2, pinnedViews: []) {
                    ForEach(coordinator.sections) { section in
                        Text(section.title)
                            .font(CyberpunkTheme.monoFont(size: 11, weight: .semibold))
                            .foregroundStyle(CyberpunkTheme.matrix)
                            .padding(.horizontal, 12)
                            .padding(.top, 8)
                            .padding(.bottom, 2)

                        ForEach(Array(section.items.enumerated()), id: \.element.id) { index, item in
                            ResultRow(item: item, index: index, revealed: revealed,
                                      isSelected: coordinator.selection == item.id)
                                .id(item.id)
                                .onTapGesture {
                                    coordinator.selection = item.id
                                    coordinator.executeSelected(executor: executor)
                                }
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
            .onChange(of: coordinator.selection) { _, newValue in
                if let id = newValue {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
            .scrollIndicators(.hidden)
            .onAppear {
                // 给首屏错峰一个短暂窗口，之后滚出的行立即显示
                guard !revealed else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { revealed = true }
            }
        }
    }
}
