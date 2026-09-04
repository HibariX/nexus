import SwiftUI

struct ResultListView: View {
    @Bindable var coordinator: SearchCoordinator
    let executor: ActionExecutor

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

                        ForEach(section.items) { item in
                            ResultRow(item: item, isSelected: coordinator.selection == item.id)
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
        }
    }
}
