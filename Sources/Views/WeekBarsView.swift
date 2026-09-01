import Cocoa

// MARK: - 最近 7 天活跃柱状图（轻量自绘，无第三方依赖）
// Views 层：只按传入的 DailyStat 绘制，不做统计计算。

final class WeekBarsView: NSView {

    // MARK: - 属性

    private var values: [Int] = Array(repeating: 0, count: 7)
    private var labels: [String] = []
    private let barColor = Theme.primary.withAlphaComponent(0.85)

    // MARK: - 公开方法

    /// 注入最近 7 天数据（按时间升序）
    func setData(_ week: [DailyStat]) {
        values = week.map(\.totalActions)
        labels = week.map { String($0.dateKey.suffix(2)) }
        needsDisplay = true
    }

    // MARK: - 绘制

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let count = max(values.count, 1)
        let slotWidth = bounds.width / CGFloat(count)
        let barWidth: CGFloat = 26
        let maxValue = max(values.max() ?? 1, 1)

        for (index, value) in values.enumerated() {
            let height = max(CGFloat(value) / CGFloat(maxValue) * (bounds.height - 16),
                             value > 0 ? 4 : 2)
            let x = CGFloat(index) * slotWidth + (slotWidth - barWidth) / 2
            let barRect = CGRect(x: x, y: 14, width: barWidth, height: height)
            let path = CGPath(roundedRect: barRect, cornerWidth: 4, cornerHeight: 4, transform: nil)
            ctx.setFillColor((value > 0 ? barColor : NSColor.black.withAlphaComponent(0.08)).cgColor)
            ctx.addPath(path)
            ctx.fillPath()

            let day = labels.indices.contains(index) ? labels[index] : ""
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 10),
                .foregroundColor: Theme.textSecondary
            ]
            let text = NSAttributedString(string: day, attributes: attrs)
            text.draw(at: CGPoint(x: x + 4, y: 0))
        }
    }
}
