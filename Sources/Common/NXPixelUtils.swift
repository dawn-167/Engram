import Cocoa

// MARK: - Nexus 像素对齐工具
// CommonKit Version: 1.0
// 解决非 Retina 屏字体模糊问题：所有 frame 取整、contentsScale 同步

public enum NXPixelUtils {

    /// 将视图及其所有子视图的 frame 对齐到像素网格
    public static func alignSubviewsToPixels(_ view: NSView) {
        for sub in view.subviews {
            var f = sub.frame
            f.origin.x = round(f.origin.x)
            f.origin.y = round(f.origin.y)
            f.size.width = round(f.size.width)
            f.size.height = round(f.size.height)
            sub.frame = f
            alignSubviewsToPixels(sub)
        }
    }

    /// 同步视图及其所有自定义 layer 的 contentsScale 到当前屏幕
    public static func syncContentsScale(_ view: NSView) {
        guard let scale = view.window?.backingScaleFactor else { return }
        view.layer?.contentsScale = scale
        if let layers = view.layer?.sublayers {
            for layer in layers {
                layer.contentsScale = scale
            }
        }
    }

    /// 对 CGFloat 取整到像素网格
    public static func align(_ value: CGFloat) -> CGFloat {
        round(value)
    }

    /// 对 NSRect 取整到像素网格
    public static func align(_ rect: NSRect) -> NSRect {
        NSRect(
            x: round(rect.origin.x),
            y: round(rect.origin.y),
            width: round(rect.size.width),
            height: round(rect.size.height)
        )
    }
}
