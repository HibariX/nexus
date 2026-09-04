import AppKit
import SwiftUI

/// 便笺式待办清单：顶部标题条（可拖动）+ 输入框 + 列表 + 今日日程 + 页脚。
/// 数据来自系统「提醒事项」，日程区只读展示日历。
struct TodoListView: View {
    let store: TodoStore
    var onClose: () -> Void

    @State private var newTitle = ""
    @State private var editingID: String?
    @State private var editingText = ""

    /// 日程区最多列几条，超出折叠成一行提示
    private static let visibleEventLimit = 3

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(CyberpunkTheme.border.opacity(0.55))
            if store.authorization == .granted {
                inputRow
                Divider().overlay(CyberpunkTheme.border.opacity(0.55))
            }
            listBody
            scheduleSection
            footer
        }
        .frame(width: 300, height: 500)
        .background(CyberpunkPanelBackground())
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(CyberpunkTheme.border.opacity(0.85), lineWidth: 1)
        )
        .shadow(color: CyberpunkTheme.matrix.opacity(0.12), radius: 18)
        .tint(CyberpunkTheme.matrix)
        .preferredColorScheme(.dark)
    }

    // MARK: - 标题条（背景可拖动窗口）

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("今日待办").font(CyberpunkTheme.monoFont(size: 16, weight: .semibold))
                Text(Self.todayString)
                    .font(CyberpunkTheme.monoFont(size: 11))
                    .foregroundStyle(CyberpunkTheme.secondaryText)
            }
            Spacer()
            if store.hasCompleted {
                Button(action: store.clearCompleted) {
                    Image(systemName: "eye.slash")
                }
                .buttonStyle(.plain)
                .foregroundStyle(CyberpunkTheme.secondaryText)
                .help("从面板隐藏已完成项（不会删除提醒事项）")
            }
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.plain)
            .foregroundStyle(CyberpunkTheme.secondaryText)
            .help("关闭（数据保留）")
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    // MARK: - 新增输入

    private var inputRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus.circle").foregroundStyle(CyberpunkTheme.matrix)
            TextField("添加待办，回车确认", text: $newTitle)
                .textFieldStyle(.plain)
                .foregroundStyle(CyberpunkTheme.matrixBright)
                .onSubmit {
                    store.add(newTitle)
                    newTitle = ""
                }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - 列表

    @ViewBuilder
    private var listBody: some View {
        switch store.authorization {
        case .notDetermined:
            permissionGuide(
                icon: "checklist",
                message: "今日待办与系统「提醒事项」同步，需要你授权访问。",
                buttonTitle: "允许访问提醒事项",
                action: { Task { await store.requestAccess() } }
            )
        case .denied:
            permissionGuide(
                icon: "lock",
                message: "无法访问「提醒事项」。请在系统设置中允许 Nexus 访问后重试。",
                buttonTitle: "打开系统设置",
                action: PermissionCenter.openRemindersSettings
            )
        case .granted:
            if store.items.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "checklist")
                        .font(.system(size: 30))
                        .foregroundStyle(CyberpunkTheme.mutedText)
                    Text("今天还没有待办").foregroundStyle(CyberpunkTheme.secondaryText)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(store.sorted) { item in
                            TodoRow(
                                item: item,
                                isEditing: editingID == item.id,
                                editingText: $editingText,
                                onToggle: { store.toggle(id: item.id) },
                                onBeginEdit: {
                                    editingText = item.title
                                    editingID = item.id
                                },
                                onCommitEdit: commitEdit,
                                onDelete: { store.remove(id: item.id) }
                            )
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private func permissionGuide(
        icon: String, message: String, buttonTitle: String, action: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 30))
                .foregroundStyle(CyberpunkTheme.mutedText)
            Text(message)
                .font(.callout)
                .foregroundStyle(CyberpunkTheme.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button(buttonTitle, action: action)
                .controlSize(.small)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 今日日程（只读）

    private var visibleEvents: [CalendarEvent] {
        Array(store.todayEvents.prefix(Self.visibleEventLimit))
    }

    /// 下一个即将开始的事件没出现在可见行里（在明天、或被折叠了）时，单独补一行
    private var detachedNextEvent: CalendarEvent? {
        guard let next = store.nextEvent,
              !visibleEvents.contains(where: { $0.id == next.id }) else { return nil }
        return next
    }

    @ViewBuilder
    private var scheduleSection: some View {
        if !store.todayEvents.isEmpty || detachedNextEvent != nil {
            // TimelineView 在窗口不可见时自动停摆，不用手动管 Timer 生命周期
            TimelineView(.periodic(from: .now, by: 60)) { context in
                VStack(alignment: .leading, spacing: 0) {
                    Divider().overlay(CyberpunkTheme.border.opacity(0.55))

                    HStack {
                        Text("今日日程")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(CyberpunkTheme.secondaryText)
                        Spacer()
                        if store.todayEvents.count > Self.visibleEventLimit {
                            Text("共 \(store.todayEvents.count) 个")
                                .font(.caption2)
                                .foregroundStyle(CyberpunkTheme.mutedText)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 8)
                    .padding(.bottom, 4)

                    ForEach(visibleEvents) { event in
                        EventRow(
                            event: event,
                            countdown: store.nextEvent?.id == event.id
                                ? event.countdownText(now: context.date) : nil
                        )
                    }

                    if let next = detachedNextEvent {
                        EventRow(
                            event: next,
                            countdown: next.countdownText(now: context.date),
                            prefix: Self.dayPrefix(for: next.start)
                        )
                    }
                }
                .padding(.bottom, 4)
                .contentShape(Rectangle())
                .onTapGesture {
                    if let url = URL(string: "ical://") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
    }

    /// 非今天的事件加个"明天/周三"前缀，免得误读成今天的
    private static func dayPrefix(for date: Date) -> String? {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return nil }
        if calendar.isDateInTomorrow(date) { return "明天" }
        return date.formatted(.dateTime.weekday(.abbreviated).locale(Locale(identifier: "zh_CN")))
    }

    // MARK: - 页脚

    private var footer: some View {
        HStack {
            if let error = store.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(CyberpunkTheme.danger)
                    .lineLimit(2)
            } else {
                Text("剩余 \(store.remainingCount) 项")
                    .font(.caption)
                    .foregroundStyle(CyberpunkTheme.secondaryText)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    // MARK: - 逻辑

    private func commitEdit() {
        guard let id = editingID else { return }
        store.updateTitle(id: id, title: editingText)
        editingID = nil
        editingText = ""
    }

    private static var todayString: String {
        Date.now.formatted(
            .dateTime.month(.wide).day().weekday(.wide)
                .locale(Locale(identifier: "zh_CN"))
        )
    }
}

// MARK: - 待办单行

private struct TodoRow: View {
    let item: TodoItem
    let isEditing: Bool
    @Binding var editingText: String
    let onToggle: () -> Void
    let onBeginEdit: () -> Void
    let onCommitEdit: () -> Void
    let onDelete: () -> Void

    @State private var hovering = false
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onToggle) {
                Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(item.isDone ? CyberpunkTheme.matrix : CyberpunkTheme.secondaryText)
                    .font(.system(size: 15))
            }
            .buttonStyle(.plain)

            if isEditing {
                TextField("", text: $editingText)
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .onSubmit(onCommitEdit)
                    .onAppear { focused = true }
                    .onChange(of: focused) { _, now in
                        if !now { onCommitEdit() }  // 失焦即提交
                    }
            } else {
                Text(item.title)
                    .strikethrough(item.isDone)
                    .foregroundStyle(item.isDone ? CyberpunkTheme.mutedText : CyberpunkTheme.text)
                    .lineLimit(2)
                    .onTapGesture(count: 2, perform: onBeginEdit)
                Spacer(minLength: 4)
                if hovering {
                    Button(action: onDelete) {
                        Image(systemName: "xmark")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(CyberpunkTheme.secondaryText)
                    }
                    .buttonStyle(.plain)
                    .help("删除（同时从提醒事项中移除）")
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(hovering ? CyberpunkTheme.cyan.opacity(0.07) : .clear)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}

// MARK: - 日程单行

private struct EventRow: View {
    let event: CalendarEvent
    var countdown: String?
    var prefix: String?

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(color)
                .frame(width: 3, height: 14)

            Text(timeLabel)
                .font(.caption.monospacedDigit())
                .foregroundStyle(CyberpunkTheme.secondaryText)
                .frame(width: 52, alignment: .leading)

            Text(event.title)
                .font(.caption)
                .lineLimit(1)

            Spacer(minLength: 4)

            if let countdown {
                Text(countdown)
                    .font(CyberpunkTheme.monoFont(size: 11))
                    .foregroundStyle(CyberpunkTheme.matrix)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 3)
    }

    private var timeLabel: String {
        guard let prefix else { return event.timeText }
        return "\(prefix) \(event.timeText)"
    }

    private var color: Color {
        guard let rgb = event.color else { return CyberpunkTheme.secondaryText }
        return Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }
}
