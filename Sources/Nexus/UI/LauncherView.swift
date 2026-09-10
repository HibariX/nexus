import SwiftUI

enum LauncherLayout {
    static let size = CGSize(width: 820, height: 520)
}

struct LauncherView: View {
    @Bindable var coordinator: SearchCoordinator
    let executor: ActionExecutor
    let settings: AppSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var passwordFormFocusRequest = 0
    @State private var appear = false
    @State private var shuttingDown = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                if coordinator.canGoBack {
                    BackChip(title: coordinator.pageTitle) { coordinator.pop() }
                }
                SearchField(
                    text: $coordinator.query,
                    placeholder: coordinator.searchPlaceholder,
                    onMoveUp: { coordinator.moveUp() },
                    onMoveDown: { coordinator.moveDown() },
                    onMoveLeft: { coordinator.moveLeft() },
                    onMoveRight: { coordinator.moveRight() },
                    onSubmit: { coordinator.executeSelected(executor: executor) },
                    onSubmitCopyExpression: {
                        coordinator.executeSelected(executor: executor, copyExpression: true)
                    },
                    onEscape: {
                        if coordinator.canGoBack { coordinator.pop() }
                        else { coordinator.onDismiss?() }
                    },
                    onBackIfEmpty: {
                        guard coordinator.canGoBack else { return false }
                        coordinator.pop()
                        return true
                    },
                    onActionKey: {
                        if coordinator.isRandomPasswordPluginPage {
                            passwordFormFocusRequest += 1
                            return true
                        }
                        return coordinator.beginAliasEditing()
                    }
                )
                .frame(height: 38)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Divider()
                .overlay(CyberpunkTheme.border.opacity(0.55))

            Group {
                if coordinator.isWorkbench {
                    WorkbenchGridView(coordinator: coordinator, executor: executor,
                                      focusEffect: settings.focusEffect)
                } else if coordinator.isRandomPasswordPluginPage {
                    RandomPasswordFormView(
                        initialArguments: coordinator.currentPluginPath,
                        focusRequest: passwordFormFocusRequest,
                        executor: executor
                    )
                } else {
                    ResultListView(coordinator: coordinator, executor: executor)
                }
            }
            .id(coordinator.pageKey)
            .transition(pageTransition)
            .frame(maxHeight: .infinity)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: coordinator.pageKey)

            FooterBar(isWorkbench: coordinator.isWorkbench)
        }
        .frame(width: LauncherLayout.size.width, height: LauncherLayout.size.height)
        .background(CyberpunkPanelBackground())
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(CyberpunkTheme.border.opacity(0.85), lineWidth: 1)
        )
        .shadow(color: CyberpunkTheme.matrix.opacity(0.13), radius: 22)
        .tint(CyberpunkTheme.matrix)
        .preferredColorScheme(.dark)
        .scaleEffect(reduceMotion ? 1 : (appear ? 1 : 0.96))
        .opacity(appear ? 1 : 0)
        .animation(
            reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.82),
            value: appear
        )
        // 每次面板显示都重播入场（面板窗口复用，onAppear 只在首次触发）
        .onChange(of: coordinator.panelShowCounter) { _, _ in playEntrance() }
        // 关机退场：垂直收拢成水平亮线（CRT 关机效果）
        .scaleEffect(x: 1, y: reduceMotion ? 1 : (shuttingDown ? 0.02 : 1), anchor: .center)
        .opacity(shuttingDown ? 0 : 1)
        .animation(reduceMotion ? nil : .easeIn(duration: 0.28), value: shuttingDown)
        .overlay {
            if shuttingDown {
                GeometryReader { geo in
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Color.clear, CyberpunkTheme.matrix.opacity(0.9),
                                         CyberpunkTheme.cyan, Color.clear],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(height: 2)
                        .offset(y: geo.size.height / 2 - 1)
                        .shadow(color: CyberpunkTheme.cyan.opacity(0.8), radius: 8)
                }
            }
        }
        .onChange(of: coordinator.isShuttingDown) { _, v in
            shuttingDown = v
        }
    }

    /// 面板每次显示时重播入场（面板窗口复用，onAppear 只在首次触发）
    private func playEntrance() {
        if reduceMotion { appear = true; return }
        appear = false
        DispatchQueue.main.async {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) {
                appear = true
            }
        }
    }

    /// 跨页切换转场：push 新页从右滑入 / pop 回到上层从左侧滑回，均带淡入
    private var pageTransition: AnyTransition {
        let edge: Edge = coordinator.navDirection == .push ? .trailing : .leading
        let opposite: Edge = edge == .trailing ? .leading : .trailing
        return .asymmetric(
            insertion: .move(edge: edge).combined(with: .opacity),
            removal: .move(edge: opposite).combined(with: .opacity)
        )
    }
}

/// 页面层级的返回 chip：显示「‹ 当前页名」，点击返回上一层
private struct BackChip: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .semibold))
                Text(title)
                    .font(CyberpunkTheme.monoFont(size: 13, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(CyberpunkTheme.secondaryText)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(CyberpunkTheme.surface)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(CyberpunkTheme.border.opacity(0.7), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .fixedSize()
    }
}
