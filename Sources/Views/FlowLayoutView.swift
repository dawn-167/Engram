import Cocoa

// MARK: - 流式自动换行布局容器（词块按钮按行排列，超出宽度自动换行）
// Views 层：只负责子视图 frame 计算，不关心词块业务。手动 layout 以获得最稳的换行效果。

final class FlowLayoutView: NSView {

    // MARK: - 属性

    var horizontalSpacing: CGFloat = 8
    var verticalSpacing: CGFloat = 8
    var contentInset = NSEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
    /// 内容总高度变化时回调，外部可据此调整自身高度
    var onContentHeightChange: ((CGFloat) -> Void)?
    private var contentHeight: CGFloat = 0

    /// 与页面一致，使用翻转坐标自顶向下排布
    override var isFlipped: Bool { true }

    // MARK: - 公开方法

    /// 用新的子视图重建
    func setSubviews(_ views: [NSView]) {
        subviews.forEach { $0.removeFromSuperview() }
        views.forEach { addSubview($0) }
        needsLayout = true
    }

    // MARK: - 布局

    override func layout() {
        super.layout()
        var x = contentInset.left
        var y = contentInset.top
        let maxWidth = bounds.width
        let lineHeight = subviews.map(\.bounds.height).max() ?? 28

        for view in subviews {
            let width = view.bounds.width
            if x + width > maxWidth - contentInset.right && x > contentInset.left {
                x = contentInset.left
                y += (lineHeight + verticalSpacing)
            }
            view.frame = CGRect(x: x, y: y, width: view.bounds.width, height: lineHeight)
            x += width + horizontalSpacing
        }
        let newHeight = y + (lineHeight) + contentInset.bottom
        if abs(newHeight - contentHeight) > 0.5 {
            contentHeight = newHeight
            onContentHeightChange?(newHeight)
        }
    }

    /// 计算给定宽度下所需高度（供外部预估）
    func requiredHeight(for width: CGFloat) -> CGFloat {
        var x = contentInset.left
        var y = contentInset.top
        let lineHeight = subviews.map(\.bounds.height).max() ?? 28
        for view in subviews {
            if x + view.bounds.width > width - contentInset.right && x > contentInset.left {
                x = contentInset.left
                y += lineHeight + verticalSpacing
            }
            x += view.bounds.width + horizontalSpacing
        }
        return y + lineHeight + contentInset.bottom
    }
}
