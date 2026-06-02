import Cocoa

class StatusIconsView: FlippedView {
    struct Icon {
        var symbol: String
        var tooltip: String?
        var visible = false
    }

    static let spaceIdx = 0
    static let hiddenIdx = 1
    static let fullscreenIdx = 2
    static let minimizedIdx = 3

    private static let defaultSymbols: [(Symbols, String?)] = [
        (.circledNumber0, nil),
        (.circledSlashSign, NSLocalizedString("App is hidden", comment: "")),
        (.circledPlusSign, NSLocalizedString("Window is fullscreen", comment: "")),
        (.circledMinusSign, NSLocalizedString("Window is minimized", comment: "")),
    ]

    var icons: [Icon]
    private var visibleCount = 0
    private var tooltipsDirty = true
    /// Single-character cell size, cached at init for the layout cache
    let iconCellSize: NSSize

    @objc func _windowChangedKeyState() {}
    @objc func _layoutSubtreeWithOldSize(_ oldSize: NSSize) {}

    convenience init() {
        self.init(frame: .zero)
    }

    override init(frame: NSRect) {
        let font = NSFont(name: "SF Pro Text", size: (Appearance.fontHeight * 0.85).rounded())!
        let measureAttrs: [NSAttributedString.Key: Any] = [.font: font, .paragraphStyle: TileFontIconView.paragraphStyle]
        icons = Self.defaultSymbols.map { Icon(symbol: $0.0.rawValue, tooltip: $0.1) }
        iconCellSize = NSAttributedString(string: Symbols.circledNumber0.rawValue, attributes: measureAttrs).size()
        super.init(frame: frame)
    }

    static func cachedAttrString(for symbol: String) -> NSAttributedString {
        let size = Appearance.fontHeight
        // 状态圆圈（Space 号 / 隐藏 / 全屏 / 最小化）退到次要色，不抢镜
        let color = Appearance.secondaryFontColor
        let key = TileFontIconView.SymbolCacheKey(symbol: symbol, size: size, colorKey: TileFontIconView.symbolColorKey(color))
        if let cached = TileFontIconView.symbolCache[key] { return cached }
        let font = NSFont(name: "SF Pro Text", size: (size * 0.85).rounded())!
        let str = NSAttributedString(string: symbol, attributes: [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: TileFontIconView.paragraphStyle,
        ])
        TileFontIconView.symbolCache[key] = str
        return str
    }

    required init?(coder: NSCoder) { fatalError() }

    var totalWidth: CGFloat { CGFloat(visibleCount) * TilesView.layoutCache.iconWidth }

    func update(isHidden: Bool, isFullscreen: Bool, isMinimized: Bool, showSpace: Bool) {
        icons[Self.hiddenIdx].visible = isHidden
        icons[Self.fullscreenIdx].visible = isFullscreen
        icons[Self.minimizedIdx].visible = isMinimized
        icons[Self.spaceIdx].visible = showSpace
        visibleCount = icons.count(where: { $0.visible })
    }

    func setSpaceStar() {
        icons[Self.spaceIdx].symbol = Symbols.circledStar.rawValue
        icons[Self.spaceIdx].tooltip = NSLocalizedString("Window is on every Space", comment: "")
    }

    func setSpaceNumber(_ number: Int) {
        icons[Self.spaceIdx].symbol = Self.symbolForSpace(number)
        icons[Self.spaceIdx].tooltip = String(format: NSLocalizedString("Window is on Space %d", comment: ""), number)
    }

    static func symbolForSpace(_ number: Int) -> String {
        let (base, offset) = number <= 9
            ? (Symbols.circledNumber0.rawValue, number * 2)
            : (Symbols.circledNumber10.rawValue, number - 10)
        return String(UnicodeScalar(Int(base.unicodeScalars.first!.value) + offset)!)
    }

    var spaceVisible: Bool { icons[Self.spaceIdx].visible }

    func layoutIcons(hWidth: CGFloat, hHeight: CGFloat, edgeInsets: CGFloat) {
        let indicatorSpace = totalWidth
        assignIfDifferent(&frame.size.width, indicatorSpace)
        assignIfDifferent(&frame.size.height, hHeight)
        let isLTR = App.shared.userInterfaceLayoutDirection == .leftToRight
        assignIfDifferent(&frame.origin.x, isLTR ? edgeInsets + hWidth - indicatorSpace : edgeInsets)
        assignIfDifferent(&frame.origin.y, edgeInsets)
        tooltipsDirty = true
        needsDisplay = true
    }

    func ensureTooltipsInstalled() {
        guard tooltipsDirty else { return }
        tooltipsDirty = false
        removeAllToolTips()
        let iconWidth = TilesView.layoutCache.iconWidth
        let iconHeight = TilesView.layoutCache.iconHeight
        let isLTR = App.shared.userInterfaceLayoutDirection == .leftToRight
        let yOffset = ((frame.height - iconHeight) / 2).rounded()
        var offset = CGFloat(0)
        for icon in icons {
            guard icon.visible else { continue }
            offset += iconWidth
            let x = isLTR ? frame.width - offset : offset - iconWidth
            if let tooltip = icon.tooltip {
                _ = addToolTip(NSRect(x: x, y: yOffset, width: iconWidth, height: iconHeight), owner: tooltip as NSString, userData: nil)
            }
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard visibleCount > 0 else { return }
        let iconWidth = TilesView.layoutCache.iconWidth
        let iconHeight = TilesView.layoutCache.iconHeight
        let isLTR = App.shared.userInterfaceLayoutDirection == .leftToRight
        let yOffset = ((frame.height - iconHeight) / 2).rounded()
        // 药丸底：仅 titles 风格画（appIcons 整个 statusIcons 隐藏；thumbnails 上不画以保留缩略图视觉重心）。
        // 走 labelColor 透明，自动适配浅深色；轻量 0.08 让"Space 号"看起来是个 chip 而不是孤立字符。
        if TileView.cachedEffectiveStyle == .titles {
            let h = max(iconHeight, frame.height) - 2
            let pillW = CGFloat(visibleCount) * iconWidth
            let pillX = isLTR ? frame.width - pillW : 0
            let pillY = ((frame.height - h) / 2).rounded()
            let bounds = NSRect(x: pillX, y: pillY, width: pillW, height: h)
            let path = NSBezierPath(roundedRect: bounds, xRadius: h / 2, yRadius: h / 2)
            NSColor.labelColor.withAlphaComponent(0.08).setFill()
            path.fill()
        }
        var offset = CGFloat(0)
        for icon in icons {
            guard icon.visible else { continue }
            offset += iconWidth
            let x = isLTR ? frame.width - offset : offset - iconWidth
            Self.cachedAttrString(for: icon.symbol).draw(at: NSPoint(x: x, y: yOffset))
        }
    }
}
