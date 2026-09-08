import AppKit
import ScreenCaptureKit

/// 一块屏在按下热键那一刻的定格画面
struct FrozenScreen {
    /// 屏幕 frame，全局 Cocoa 坐标（左下原点，points）
    let frame: NSRect
    /// 该屏的位图，Retina 下是 2x 像素
    let image: CGImage

    /// 位图像素 / 屏幕 points
    var scale: CGFloat { CGFloat(image.width) / max(frame.width, 1) }
}

/// 屏幕定格与裁剪：走 ScreenCaptureKit 直接拿 CGImage。
/// 早先是 spawn `screencapture -R` 写临时文件再读回（实测 336ms），
/// SCScreenshotManager 热态约 78ms，且没有进程启动、PNG 编解码和磁盘往返。
final class ScreenshotService {

    /// 检查权限，未授权时弹引导。返回是否已授权。
    func ensurePermission() -> Bool {
        guard PermissionCenter.hasScreenCapture else {
            // request 的返回值代表本次请求结果；不要继续使用请求前的旧状态。
            let granted = PermissionCenter.requestScreenCapture()
            if granted || PermissionCenter.hasScreenCapture {
                return true
            }
            PermissionCenter.showGuide(
                title: "需要屏幕录制权限",
                message: "截图功能需要屏幕录制权限。请在系统设置中允许\(PermissionCenter.appName)，授权后需重新启动应用。",
                openSettings: PermissionCenter.openScreenCaptureSettings
            )
            return false
        }
        return true
    }

    /// 把每块屏定格成一张位图。必须在遮罩窗上屏之前调用，否则会把遮罩定格进去。
    /// 定格之后框选的是静态画面，一闪而过的 tooltip、动画、下拉菜单才截得到
    func freezeAllScreens() async -> [FrozenScreen] {
        guard let primary = NSScreen.screens.first else { return [] }
        // Cocoa 坐标（左下原点）→ SCK 的翻转坐标（主屏左上原点）。
        // 与旧的 `screencapture -R` 参数算法一致：同一 rect 下两者输出尺寸相同、
        // 逐像素比对最大差 0
        let flipHeight = primary.frame.maxY

        var frozen: [FrozenScreen] = []
        for screen in NSScreen.screens {
            let frame = screen.frame
            let flipped = CGRect(x: frame.minX, y: flipHeight - frame.maxY,
                                 width: frame.width, height: frame.height)
            guard let image = try? await SCScreenshotManager.captureImage(in: flipped) else { continue }
            frozen.append(FrozenScreen(frame: frame, image: image))
        }
        return frozen
    }
}

// MARK: - 从定格画面裁剪选区

extension Array where Element == FrozenScreen {

    /// 按全局 Cocoa 坐标裁出选区。跨屏时把各屏那一段拼到一起。
    /// 返回的 NSImage 显式带 points 尺寸，贴图窗才能 1:1 对上选区
    func crop(to rect: NSRect) -> NSImage? {
        let hits = filter { $0.frame.intersects(rect) }
        guard !hits.isEmpty else { return nil }

        // 单屏是绝大多数情况，直接裁，不走拼接那条更贵的路
        if hits.count == 1, let only = hits.first {
            guard let cg = only.crop(rect) else { return nil }
            return NSImage(cgImage: cg, size: rect.size)
        }

        // 跨屏：以最高的 scale 建目标画布，各屏按自己的位置画进去
        let scale = hits.map(\.scale).max() ?? 2
        let pixelW = Int((rect.width * scale).rounded())
        let pixelH = Int((rect.height * scale).rounded())
        guard pixelW > 0, pixelH > 0,
              let ctx = CGContext(data: nil, width: pixelW, height: pixelH,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return nil
        }
        for screen in hits {
            let piece = rect.intersection(screen.frame)
            guard let cg = screen.crop(piece) else { continue }
            // CGContext 与 Cocoa 同为左下原点，直接按相对位置放
            let dest = CGRect(x: (piece.minX - rect.minX) * scale,
                              y: (piece.minY - rect.minY) * scale,
                              width: piece.width * scale,
                              height: piece.height * scale)
            ctx.draw(cg, in: dest)
        }
        guard let merged = ctx.makeImage() else { return nil }
        return NSImage(cgImage: merged, size: rect.size)
    }
}

extension FrozenScreen {
    /// 裁出该屏范围内的一块（全局 Cocoa 坐标）
    fileprivate func crop(_ rect: NSRect) -> CGImage? {
        let local = rect.intersection(frame)
        guard local.width > 0, local.height > 0 else { return nil }
        // 位图是左上原点、y 向下，Cocoa 是左下原点，所以取的是到顶边的距离
        let pixel = CGRect(x: (local.minX - frame.minX) * scale,
                           y: (frame.maxY - local.maxY) * scale,
                           width: local.width * scale,
                           height: local.height * scale).integral
        return image.cropping(to: pixel)
    }
}
