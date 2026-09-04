import SwiftUI

enum LauncherLayout {
    static let size = CGSize(width: 820, height: 520)
}

struct LauncherView: View {
    @Bindable var coordinator: SearchCoordinator
    let executor: ActionExecutor
    @State private var passwordFormFocusRequest = 0

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
                    WorkbenchGridView(coordinator: coordinator, executor: executor)
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
            .frame(maxHeight: .infinity)

            FooterBar(isWorkbench: coordinator.isWorkbench)
        }
        .frame(width: LauncherLayout.size.width, height: LauncherLayout.size.height)
        .background(CyberpunkPanelBackground())
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(CyberpunkTheme.border.opacity(0.85), lineWidth: 1)
        )
        .shadow(color: CyberpunkTheme.matrix.opacity(0.12), radius: 22)
        .tint(CyberpunkTheme.matrix)
        .preferredColorScheme(.dark)
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
