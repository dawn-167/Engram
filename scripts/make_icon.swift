import Cocoa

// MARK: - Engram 应用图标生成器（纯 CoreGraphics 离线绘制，无外部素材）
// 输出 1024x1024 原图到命令行指定路径，其余尺寸由 sips/iconutil 生成。

let outputPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/engram_icon_1024.png"
let size = 1024
let image = NSImage(size: NSSize(width: size, height: size))

image.lockFocus()
let rect = NSRect(x: 0, y: 0, width: size, height: size)

// 星云紫纵向渐变圆角底
let path = NSBezierPath(roundedRect: rect, xRadius: 224, yRadius: 224)
path.addClip()
let gradient = NSGradient(colors: [
    NSColor(red: 0.424, green: 0.361, blue: 0.906, alpha: 1),
    NSColor(red: 0.557, green: 0.478, blue: 0.957, alpha: 1)
])
gradient?.draw(in: rect, angle: -90)

// 左上角柔光，增加层次
NSColor(white: 1, alpha: 0.14).setFill()
NSBezierPath(ovalIn: NSRect(x: -180, y: 620, width: 560, height: 560)).fill()

// 中央字母 E（粗体、白色）
let paragraph = NSMutableParagraphStyle()
paragraph.alignment = .center
let attrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 600, weight: .heavy),
    .foregroundColor: NSColor.white,
    .paragraphStyle: paragraph
]
let letter = "E"
let textSize = letter.size(withAttributes: attrs)
let textRect = NSRect(x: 0, y: (CGFloat(size) - textSize.height) / 2 - 16,
                      width: CGFloat(size), height: textSize.height)
letter.draw(in: textRect, withAttributes: attrs)

// 右下角记忆节点点缀（呼应“记忆痕迹”）
let nodeColor = NSColor(white: 1, alpha: 0.95)
nodeColor.setFill()
let nodes = [(x: 742, y: 236, r: 34), (x: 836, y: 300, r: 20), (x: 700, y: 330, r: 16)]
NSColor(white: 1, alpha: 0.55).setStroke()
let line = NSBezierPath()
line.lineWidth = 10
line.move(to: NSPoint(x: 742, y: 236))
line.line(to: NSPoint(x: 836, y: 300))
line.line(to: NSPoint(x: 700, y: 330))
line.stroke()
for node in nodes {
    NSBezierPath(ovalIn: NSRect(x: node.x - node.r, y: node.y - node.r,
                                width: node.r * 2, height: node.r * 2)).fill()
}

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fputs("图标编码失败\n", stderr); exit(1)
}
try? png.write(to: URL(fileURLWithPath: outputPath))
print("已生成 \(outputPath)")
