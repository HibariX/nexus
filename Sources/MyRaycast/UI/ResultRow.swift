import AppKit
import SwiftUI

struct ResultRow: View {
    let item: ResultItem
    let isSelected: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            IconView(source: item.icon)
                .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(CyberpunkTheme.monoFont(size: 15))
                    .foregroundStyle(CyberpunkTheme.text)
                    .lineLimit(1)
                if let subtitle = item.subtitle {
                    Text(subtitle)
                        .font(CyberpunkTheme.monoFont(size: 12))
                        .foregroundStyle(CyberpunkTheme.secondaryText)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            if let hint = item.accessoryHint {
                Text(hint)
                    .font(.system(size: 12))
                    .foregroundStyle(CyberpunkTheme.mutedText)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(backgroundColor)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(
                    isSelected ? CyberpunkTheme.matrix.opacity(0.7) : .clear,
                    lineWidth: 1
                )
        }
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .animation(interactionAnimation, value: isHovered)
        .animation(interactionAnimation, value: isSelected)
    }

    private var backgroundColor: Color {
        if isSelected { return CyberpunkTheme.matrix.opacity(0.14) }
        if isHovered { return CyberpunkTheme.cyan.opacity(0.07) }
        return .clear
    }

    private var interactionAnimation: Animation? {
        reduceMotion ? nil : .easeOut(duration: 0.14)
    }
}

struct IconView: View {
    let source: IconSource

    var body: some View {
        switch source {
        case .appBundle(let path), .file(let path):
            AsyncFileIcon(path: path)
        case .symbol(let name):
            Image(systemName: name)
                .font(.system(size: 18))
                .foregroundStyle(CyberpunkTheme.secondaryText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .clipboardImage(let id):
            ClipThumbnailView(id: id)
        }
    }
}

private struct AsyncFileIcon: View {
    let path: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var icon: CGImage?

    init(path: String) {
        self.path = path
        _icon = State(initialValue: AppIconCache.cachedIcon(forFile: path))
    }

    var body: some View {
        Group {
            if let icon {
                Image(decorative: icon, scale: AppIconCache.displayScale)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .transition(.opacity)
            } else {
                Image(systemName: "app.dashed")
                    .font(.system(size: 18))
                    .foregroundStyle(CyberpunkTheme.mutedText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: icon != nil)
        .task(id: path) {
            if let cached = AppIconCache.cachedIcon(forFile: path) {
                icon = cached
                return
            }
            icon = nil
            let loaded = await AppIconCache.shared.icon(forFile: path)
            guard !Task.isCancelled else { return }
            icon = loaded
        }
    }
}

/// 剪贴板图片缩略图（M3 实现存储后接入）
struct ClipThumbnailView: View {
    let id: UUID
    @State private var thumbnail: CGImage?

    init(id: UUID) {
        self.id = id
        _thumbnail = State(initialValue: ClipboardThumbnailCache.cached(id))
    }

    var body: some View {
        Group {
            if let thumbnail {
                Image(decorative: thumbnail, scale: ClipboardThumbnailCache.displayScale)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                Image(systemName: "photo")
                    .foregroundStyle(CyberpunkTheme.secondaryText)
            }
        }
        .task(id: id) {
            guard thumbnail == nil,
                  let urls = ClipboardStore.shared?.thumbnailURLs(for: id) else { return }
            thumbnail = await ClipboardThumbnailCache.shared.image(
                id: id, thumbnailURL: urls.thumbnail, blobURL: urls.blob
            )
        }
    }
}
