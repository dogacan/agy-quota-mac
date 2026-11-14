import AppKit
import Foundation

struct IcnsEntry {
    let type: String
    let pixelSize: Int
}

let icnsEntries: [IcnsEntry] = [
    IcnsEntry(type: "icp4", pixelSize: 16),
    IcnsEntry(type: "ic11", pixelSize: 32),
    IcnsEntry(type: "icp5", pixelSize: 32),
    IcnsEntry(type: "ic12", pixelSize: 64),
    IcnsEntry(type: "ic07", pixelSize: 128),
    IcnsEntry(type: "ic13", pixelSize: 256),
    IcnsEntry(type: "ic08", pixelSize: 256),
    IcnsEntry(type: "ic14", pixelSize: 512),
    IcnsEntry(type: "ic09", pixelSize: 512),
    IcnsEntry(type: "ic10", pixelSize: 1024),
]

func antigravitySymbolPath() -> CGPath {
    let path = CGMutablePath()
    path.move(to: CGPoint(x: 21.751, y: 22.607))
    path.addCurve(
        to: CGPoint(x: 23.259, y: 21.099),
        control1: CGPoint(x: 23.091, y: 23.612),
        control2: CGPoint(x: 25.101, y: 22.942)
    )
    path.addCurve(
        to: CGPoint(x: 12.037, y: 1.000),
        control1: CGPoint(x: 17.730, y: 15.740),
        control2: CGPoint(x: 18.904, y: 1.000)
    )
    path.addCurve(
        to: CGPoint(x: 0.815, y: 21.100),
        control1: CGPoint(x: 5.170, y: 1.000),
        control2: CGPoint(x: 6.342, y: 15.740)
    )
    path.addCurve(
        to: CGPoint(x: 2.322, y: 22.606),
        control1: CGPoint(x: -1.195, y: 23.109),
        control2: CGPoint(x: 0.982, y: 23.611)
    )
    path.addCurve(
        to: CGPoint(x: 12.037, y: 12.892),
        control1: CGPoint(x: 7.514, y: 19.089),
        control2: CGPoint(x: 7.179, y: 12.892)
    )
    path.addCurve(
        to: CGPoint(x: 21.751, y: 22.607),
        control1: CGPoint(x: 16.894, y: 12.892),
        control2: CGPoint(x: 16.559, y: 19.089)
    )
    path.closeSubpath()
    return path
}

func renderIconPNG(pixelSize px: Int) throws -> Data {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: px,
        pixelsHigh: px,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        throw NSError(domain: "GenerateIcon", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to allocate NSBitmapImageRep"])
    }
    rep.size = NSSize(width: px, height: px)

    guard let nsContext = NSGraphicsContext(bitmapImageRep: rep) else {
        throw NSError(domain: "GenerateIcon", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to create NSGraphicsContext"])
    }

    let ctx = nsContext.cgContext
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

    func srgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1.0) -> CGColor {
        CGColor(srgbRed: r / 255.0, green: g / 255.0, blue: b / 255.0, alpha: a)
    }

    // Flip into top-left 200x200 coordinate space matching SVG design.
    ctx.translateBy(x: 0, y: CGFloat(px))
    ctx.scaleBy(x: CGFloat(px) / 200.0, y: -CGFloat(px) / 200.0)
    ctx.setAllowsAntialiasing(true)
    ctx.setShouldAntialias(true)

    let squircleRect = CGRect(x: 19.5, y: 19.5, width: 161.0, height: 161.0)
    let squirclePath = CGPath(
        roundedRect: squircleRect,
        cornerWidth: 36.2,
        cornerHeight: 36.2,
        transform: nil
    )

    // 1-2. Flat background fill. No baked-in drop shadow (macOS adds its own)
    // and no background gradient: Core Graphics dithers gradients, and the
    // resulting per-pixel noise makes the PNGs compress very poorly.
    ctx.saveGState()
    ctx.addPath(squirclePath)
    ctx.setFillColor(srgb(17, 24, 39))
    ctx.fillPath()
    ctx.restoreGState()

    // 3. Crisp inner specular rim.
    let innerRect = squircleRect.insetBy(dx: 0.75, dy: 0.75)
    let innerPath = CGPath(roundedRect: innerRect, cornerWidth: 35.45, cornerHeight: 35.45, transform: nil)
    ctx.saveGState()
    ctx.addPath(innerPath)
    ctx.setStrokeColor(srgb(255, 255, 255, 0.13))
    ctx.setLineWidth(1.4)
    ctx.strokePath()
    ctx.restoreGState()

    // 4. Quota ring track.
    let ringCenter = CGPoint(x: 100.0, y: 100.0)
    let ringRadius: CGFloat = 56.5
    let ringWidth: CGFloat = 9.4
    let trackRect = CGRect(
        x: ringCenter.x - ringRadius,
        y: ringCenter.y - ringRadius,
        width: ringRadius * 2.0,
        height: ringRadius * 2.0
    )
    ctx.saveGState()
    ctx.addEllipse(in: trackRect)
    ctx.setStrokeColor(srgb(255, 255, 255, 0.10))
    ctx.setLineWidth(ringWidth)
    ctx.strokePath()
    ctx.restoreGState()

    // 5. Active 83% clockwise orbital gradient arc starting from 12 o'clock.
    let arcPath = CGMutablePath()
    let segments = 180
    let startAngle = -Double.pi / 2.0
    let sweep = 0.83 * 2.0 * Double.pi
    for i in 0...segments {
        let theta = startAngle + (Double(i) / Double(segments)) * sweep
        let pt = CGPoint(
            x: ringCenter.x + ringRadius * CGFloat(cos(theta)),
            y: ringCenter.y + ringRadius * CGFloat(sin(theta))
        )
        if i == 0 {
            arcPath.move(to: pt)
        } else {
            arcPath.addLine(to: pt)
        }
    }

    ctx.saveGState()
    ctx.addPath(arcPath)
    ctx.setLineWidth(ringWidth)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.replacePathWithStrokedPath()
    ctx.clip()
    let ringColors = [
        srgb(52, 211, 153),
        srgb(56, 189, 248),
        srgb(59, 130, 246),
    ] as CFArray
    if let ringGradient = CGGradient(colorsSpace: colorSpace, colors: ringColors, locations: [0.0, 0.55, 1.0]) {
        ctx.drawLinearGradient(
            ringGradient,
            start: CGPoint(x: 43.5, y: 43.5),
            end: CGPoint(x: 156.5, y: 156.5),
            options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
        )
    }
    ctx.restoreGState()

    // 6. Crisp white Antigravity mark centered inside the ring.
    ctx.saveGState()
    ctx.translateBy(x: 100.0, y: 98.5)
    ctx.scaleBy(x: 2.28, y: 2.28)
    ctx.translateBy(x: -12.037, y: -12.5)
    ctx.addPath(antigravitySymbolPath())
    ctx.setFillColor(srgb(255, 255, 255))
    ctx.fillPath()
    ctx.restoreGState()

    guard let pngData = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "GenerateIcon", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to encode PNG"])
    }
    return pngData
}

var pngCache: [Int: Data] = [:]
var body = Data()

for entry in icnsEntries {
    let pngData: Data
    if let cached = pngCache[entry.pixelSize] {
        pngData = cached
    } else {
        let rendered = try renderIconPNG(pixelSize: entry.pixelSize)
        pngCache[entry.pixelSize] = rendered
        pngData = rendered
    }

    precondition(entry.type.utf8.count == 4, "ICNS type tag must be 4 ASCII bytes")
    body.append(contentsOf: entry.type.utf8)
    let chunkLength = UInt32(8 + pngData.count).bigEndian
    withUnsafeBytes(of: chunkLength) { body.append(contentsOf: $0) }
    body.append(pngData)
}

var icnsData = Data("icns".utf8)
let totalLength = UInt32(8 + body.count).bigEndian
withUnsafeBytes(of: totalLength) { icnsData.append(contentsOf: $0) }
icnsData.append(body)

let outputURL = URL(fileURLWithPath: "Resources/AppIcon.icns")
try FileManager.default.createDirectory(
    at: outputURL.deletingLastPathComponent(),
    withIntermediateDirectories: true
)
try icnsData.write(to: outputURL)
print("Generated \(outputURL.path) (\(icnsData.count) bytes)")
