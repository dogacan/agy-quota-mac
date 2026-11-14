import AppKit
import AgyQuotaCore

/// Renders high-DPI `NSImage` indicators for the macOS menu bar.
enum MenuBarIconRenderer {
    private static let barHeight: CGFloat = 18
    private static let horizontalPadding: CGFloat = 2
    private static let itemGap: CGFloat = 8

    static func render(
        snapshot: QuotaSnapshot?,
        style: MenuBarStyle,
        metric: MenuBarMetric,
        monochrome: Bool
    ) -> NSImage {
        let geminiPercent = snapshot?.gemini?.percent(for: metric)
        let thirdPartyPercent = snapshot?.thirdParty?.percent(for: metric)

        let image: NSImage
        switch style {
        case .ringsAndPercent:
            image = renderRingsAndPercent(
                gemini: geminiPercent,
                thirdParty: thirdPartyPercent,
                monochrome: monochrome
            )
        case .ringsOnly:
            image = renderRingsOnly(
                gemini: geminiPercent,
                thirdParty: thirdPartyPercent,
                monochrome: monochrome
            )
        case .numbersOnly:
            image = renderNumbersOnly(
                gemini: geminiPercent,
                thirdParty: thirdPartyPercent,
                monochrome: monochrome
            )
        }

        image.isTemplate = monochrome
        return image
    }

    // MARK: - Styles

    private static func renderRingsAndPercent(
        gemini: Int?,
        thirdParty: Int?,
        monochrome: Bool
    ) -> NSImage {
        let ringSize: CGFloat = 13
        let ringTextGap: CGFloat = 4
        let font = NSFont.monospacedDigitSystemFont(ofSize: 11.5, weight: .medium)

        let gValue = gemini.map { "\($0)%" } ?? "--"
        let tpValue = thirdParty.map { "\($0)%" } ?? "--"
        let gText = "\(QuotaCategory.gemini.shortLabel) \(gValue)"
        let tpText = "\(QuotaCategory.thirdParty.shortLabel) \(tpValue)"

        let gSize = measureText(gText, font: font)
        let tpSize = measureText(tpText, font: font)

        let totalWidth = ceil(
            horizontalPadding * 2
            + ringSize + ringTextGap + gSize.width
            + itemGap
            + ringSize + ringTextGap + tpSize.width
        )

        return NSImage(size: NSSize(width: totalWidth, height: barHeight), flipped: false) { _ in
            let textColor = primaryTextColor(monochrome: monochrome)
            var x = horizontalPadding

            let gRingRect = NSRect(
                x: x,
                y: (barHeight - ringSize) / 2.0,
                width: ringSize,
                height: ringSize
            )
            drawRing(in: gRingRect, percent: gemini, lineWidth: 2.2, monochrome: monochrome)
            x += ringSize + ringTextGap

            drawText(
                gText,
                at: NSPoint(x: x, y: (barHeight - gSize.height) / 2.0),
                font: font,
                color: textColor
            )
            x += gSize.width + itemGap

            let tpRingRect = NSRect(
                x: x,
                y: (barHeight - ringSize) / 2.0,
                width: ringSize,
                height: ringSize
            )
            drawRing(in: tpRingRect, percent: thirdParty, lineWidth: 2.2, monochrome: monochrome)
            x += ringSize + ringTextGap

            drawText(
                tpText,
                at: NSPoint(x: x, y: (barHeight - tpSize.height) / 2.0),
                font: font,
                color: textColor
            )

            return true
        }
    }

    private static func renderRingsOnly(
        gemini: Int?,
        thirdParty: Int?,
        monochrome: Bool
    ) -> NSImage {
        let ringSize: CGFloat = 15
        let ringGap: CGFloat = 6
        let letterFont = NSFont.systemFont(ofSize: 7.5, weight: .bold)
        let totalWidth = ceil(horizontalPadding * 2 + ringSize * 2 + ringGap)

        return NSImage(size: NSSize(width: totalWidth, height: barHeight), flipped: false) { _ in
            let textColor = primaryTextColor(monochrome: monochrome)
            let y = (barHeight - ringSize) / 2.0

            let gRect = NSRect(x: horizontalPadding, y: y, width: ringSize, height: ringSize)
            drawRing(in: gRect, percent: gemini, lineWidth: 2.1, monochrome: monochrome)
            drawCenteredText(QuotaCategory.gemini.compactLetter, in: gRect, font: letterFont, color: textColor)

            let tpRect = NSRect(x: horizontalPadding + ringSize + ringGap, y: y, width: ringSize, height: ringSize)
            drawRing(in: tpRect, percent: thirdParty, lineWidth: 2.1, monochrome: monochrome)
            drawCenteredText(QuotaCategory.thirdParty.compactLetter, in: tpRect, font: letterFont, color: textColor)

            return true
        }
    }

    private static func renderNumbersOnly(
        gemini: Int?,
        thirdParty: Int?,
        monochrome: Bool
    ) -> NSImage {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 11.5, weight: .medium)
        let gPrefix = "\(QuotaCategory.gemini.shortLabel) "
        let gValue = gemini.map { "\($0)%" } ?? "--"
        let tpPrefix = "\(QuotaCategory.thirdParty.shortLabel) "
        let tpValue = thirdParty.map { "\($0)%" } ?? "--"

        let gPrefixSize = measureText(gPrefix, font: font)
        let gValueSize = measureText(gValue, font: font)
        let tpPrefixSize = measureText(tpPrefix, font: font)
        let tpValueSize = measureText(tpValue, font: font)

        let totalWidth = ceil(
            horizontalPadding * 2
            + gPrefixSize.width + gValueSize.width
            + itemGap
            + tpPrefixSize.width + tpValueSize.width
        )

        return NSImage(size: NSSize(width: totalWidth, height: barHeight), flipped: false) { _ in
            let labelColor = primaryTextColor(monochrome: monochrome)
            let gColor = statusNSColor(for: gemini, monochrome: monochrome)
            let tpColor = statusNSColor(for: thirdParty, monochrome: monochrome)

            var x = horizontalPadding
            let y = (barHeight - gPrefixSize.height) / 2.0

            drawText(gPrefix, at: NSPoint(x: x, y: y), font: font, color: labelColor)
            x += gPrefixSize.width

            drawText(gValue, at: NSPoint(x: x, y: y), font: font, color: gColor)
            x += gValueSize.width + itemGap

            drawText(tpPrefix, at: NSPoint(x: x, y: y), font: font, color: labelColor)
            x += tpPrefixSize.width

            drawText(tpValue, at: NSPoint(x: x, y: y), font: font, color: tpColor)

            return true
        }
    }

    // MARK: - Drawing Primitives

    private static func drawRing(
        in ringRect: NSRect,
        percent: Int?,
        lineWidth: CGFloat,
        monochrome: Bool
    ) {
        let inset = lineWidth / 2.0
        let pathRect = ringRect.insetBy(dx: inset, dy: inset)
        let center = NSPoint(x: pathRect.midX, y: pathRect.midY)
        let radius = min(pathRect.width, pathRect.height) / 2.0

        let trackColor = monochrome
            ? NSColor.black.withAlphaComponent(0.25)
            : NSColor.labelColor.withAlphaComponent(0.20)
        let trackPath = NSBezierPath(ovalIn: pathRect)
        trackPath.lineWidth = lineWidth
        trackColor.setStroke()
        trackPath.stroke()

        guard let percent else { return }
        let fraction = min(max(Double(percent) / 100.0, 0.0), 1.0)
        guard fraction > 0.001 else { return }

        let strokeColor = statusNSColor(for: percent, monochrome: monochrome)
        strokeColor.setStroke()

        if fraction >= 0.999 {
            let fullPath = NSBezierPath(ovalIn: pathRect)
            fullPath.lineWidth = lineWidth
            fullPath.stroke()
        } else {
            let arcPath = NSBezierPath()
            arcPath.lineCapStyle = .round
            arcPath.lineWidth = lineWidth
            arcPath.appendArc(
                withCenter: center,
                radius: radius,
                startAngle: 90,
                endAngle: 90 - CGFloat(fraction) * 360.0,
                clockwise: true
            )
            arcPath.stroke()
        }
    }

    private static func primaryTextColor(monochrome: Bool) -> NSColor {
        monochrome ? .black : .labelColor
    }

    private static func statusNSColor(for percent: Int?, monochrome: Bool) -> NSColor {
        if monochrome {
            return .black
        }
        guard let percent else {
            return .secondaryLabelColor
        }
        if percent >= 50 {
            return .systemGreen
        }
        if percent >= 20 {
            return .systemOrange
        }
        return .systemRed
    }

    private static func measureText(_ text: String, font: NSFont) -> NSSize {
        (text as NSString).size(withAttributes: [.font: font])
    }

    private static func drawText(_ text: String, at point: NSPoint, font: NSFont, color: NSColor) {
        (text as NSString).draw(
            at: point,
            withAttributes: [
                .font: font,
                .foregroundColor: color
            ]
        )
    }

    private static func drawCenteredText(_ text: String, in rect: NSRect, font: NSFont, color: NSColor) {
        let size = measureText(text, font: font)
        let point = NSPoint(
            x: rect.midX - size.width / 2.0,
            y: rect.midY - size.height / 2.0 - 0.5
        )
        drawText(text, at: point, font: font, color: color)
    }
}
