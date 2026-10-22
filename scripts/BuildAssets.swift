import AppKit

// 安装素材由本机 AppKit 绘制，不下载字体、图标或照片。
func text(_ value: String, _ rect: NSRect, size: CGFloat, color: NSColor = .darkGray, bold: Bool = false) {
    let paragraph = NSMutableParagraphStyle(); paragraph.lineBreakMode = .byWordWrapping
    (value as NSString).draw(in: rect, withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: bold ? .semibold : .regular), .foregroundColor: color, .paragraphStyle: paragraph])
}
func png(_ size: NSSize, draw: () -> Void) -> Data {
    let image = NSImage(size: size); image.lockFocus(); draw(); image.unlockFocus()
    return NSBitmapImageRep(data: image.tiffRepresentation!)!.representation(using: .png, properties: [:])!
}
final class ManualView: NSView {
    var source = ""
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill(); bounds.fill()
        text("RAW 汇集 · 使用说明", NSRect(x: 42, y: 38, width: 510, height: 40), size: 23, bold: true)
        text(source, NSRect(x: 42, y: 96, width: 510, height: 700), size: 12)
    }
}
let out = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
let iconset = out.appendingPathComponent("AppIcon.iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = CGFloat(points * scale)
        let data = png(NSSize(width: pixels, height: pixels)) {
            let transform = NSAffineTransform(); transform.scale(by: pixels / 1024); transform.concat()
            NSColor(calibratedRed: 0.15, green: 0.34, blue: 0.30, alpha: 1).setFill()
            NSBezierPath(roundedRect: NSRect(x: 20, y: 20, width: 984, height: 984), xRadius: 220, yRadius: 220).fill()
            NSColor(calibratedWhite: 0.95, alpha: 1).setFill()
            NSBezierPath(roundedRect: NSRect(x: 185, y: 280, width: 660, height: 460), xRadius: 75, yRadius: 75).fill()
            NSBezierPath(roundedRect: NSRect(x: 295, y: 690, width: 210, height: 100), xRadius: 25, yRadius: 25).fill()
            NSColor(calibratedRed: 0.15, green: 0.34, blue: 0.30, alpha: 1).setFill()
            NSBezierPath(ovalIn: NSRect(x: 355, y: 350, width: 300, height: 300)).fill()
            NSColor(calibratedWhite: 0.95, alpha: 1).setFill()
            NSBezierPath(ovalIn: NSRect(x: 422, y: 417, width: 166, height: 166)).fill()
        }
        let suffix = scale == 2 ? "@2x" : ""
        try data.write(to: iconset.appendingPathComponent("icon_\(points)x\(points)\(suffix).png"))
    }
}
try png(NSSize(width: 1000, height: 600)) {
    NSColor(calibratedRed: 0.96, green: 0.96, blue: 0.94, alpha: 1).setFill()
    NSRect(x: 0, y: 0, width: 1000, height: 600).fill()
    text("RAW 汇集", NSRect(x: 90, y: 487, width: 600, height: 60), size: 38, bold: true)
    text("双机位与多机位 · 精确时间排序 · 原片保留", NSRect(x: 93, y: 450, width: 750, height: 32), size: 18)
    let arrow = NSBezierPath(); arrow.move(to: NSPoint(x: 360, y: 370)); arrow.line(to: NSPoint(x: 620, y: 370)); arrow.move(to: NSPoint(x: 603, y: 384)); arrow.line(to: NSPoint(x: 620, y: 370)); arrow.line(to: NSPoint(x: 603, y: 356)); arrow.lineWidth = 2
    NSColor(calibratedRed: 0.30, green: 0.45, blue: 0.39, alpha: 1).setStroke(); arrow.stroke()
    text("拖入 Applications 完成安装", NSRect(x: 350, y: 255, width: 360, height: 30), size: 16)
    text("安装包附有使用说明。首次运行请留意 macOS 的开发者验证提示。", NSRect(x: 90, y: 22, width: 850, height: 30), size: 14)
}.write(to: out.appendingPathComponent("dmg-background.png"))
let manual = ManualView(frame: NSRect(x: 0, y: 0, width: 595, height: 842))
manual.source = try String(contentsOfFile: "docs/使用说明.txt", encoding: .utf8)
try manual.dataWithPDF(inside: manual.bounds).write(to: out.appendingPathComponent("使用说明.pdf"))
