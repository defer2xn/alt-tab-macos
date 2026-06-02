import Cocoa

class Appearance {
    // size
    static var resolvedSize = AppearanceSizePreference.medium
    static var hideThumbnails = Bool(false)
    static var windowPadding = CGFloat(1000)
    static var windowCornerRadius = CGFloat(1000)
    static var cellCornerRadius = CGFloat(1000)
    static var edgeInsetsSize = CGFloat(1000)
    static var maxWidthOnScreen = CGFloat(1000)
    static var rowsCount = CGFloat(1000)
    static var iconSize = CGFloat(1000)
    static var fontHeight = CGFloat(3)
    static var font = NSFont.systemFont(ofSize: fontHeight)
    // 应用名段字体：与 font 同字号、字重 semibold，用于切换器行内"应用名 + 窗口标题"分层渲染
    static var appNameFont = NSFont.systemFont(ofSize: fontHeight, weight: .semibold)
    static var windowMinWidthInRow = CGFloat(1000)
    static var windowMaxWidthInRow = CGFloat(1000)

    // size: constants
    static let maxHeightOnScreen = CGFloat(0.8)
    static let interCellPadding = CGFloat(1)
    static let intraCellPadding = CGFloat(5)
    static let appIconLabelSpacing = CGFloat(2)

    // theme
    // 语义色：随面板 effectiveAppearance（vibrantDark / vibrantLight，见 TilesPanel.updateAppearance）
    // 自动解析为浅/深色对应色，避免硬编码 alpha 在两种主题下其一偏淡。
    static var fontColor = NSColor.labelColor
    // 次级文本色：用于"应用名 + 窗口标题"行内分层时的窗口标题段，制造层次
    static var secondaryFontColor = NSColor.secondaryLabelColor
    static var imagesShadowColor = NSColor.red // for icon, thumbnail and windowless images
    static var material = NSVisualEffectView.Material.ultraDark
    static var highlightBorderWidth = CGFloat(3)

    // theme: constants
    static var enablePanelShadow = true
    // 实心 accent 选中态：靠饱和填充色块区分选中行，描边交由 updateTheme() 把 titles 的 borderWidth 设 0。
    static var highlightFocusedBackgroundColor: NSColor { get { NSColor.systemAccentColor.withAlphaComponent(0.85) } }
    static var highlightHoveredBackgroundColor: NSColor { get { NSColor.systemAccentColor.withAlphaComponent(0.18) } }
    static var highlightFocusedBorderColor: NSColor { get { currentStyle == .titles ? .clear : NSColor.systemAccentColor.withAlphaComponent(0.5) } }
    static var highlightHoveredBorderColor: NSColor { get { NSColor.systemAccentColor.withAlphaComponent(0.28) } }
    static var searchMatchHighlightColor: NSColor { get { NSColor.systemYellow.withAlphaComponent(0.5) } }
    static var searchMatchForegroundColor: NSColor { get { NSColor(calibratedWhite: 0.12, alpha: 1) } }

    private static var currentStyle: AppearanceStylePreference { Preferences.effectiveAppearanceStyle(SwitcherSession.activeShortcutIndex) }
    private static var currentSize: AppearanceSizePreference { Preferences.effectiveAppearanceSize(SwitcherSession.activeShortcutIndex) }
    static var currentTheme: AppearanceThemePreference {
        let theme = Preferences.effectiveAppearanceTheme(SwitcherSession.activeShortcutIndex)
        return theme == .system ? NSAppearance.current.getThemeName() : theme
    }

    static func update() {
        updateSize()
        updateTheme()
    }

    private static func updateSize() {
        let isHorizontalScreen = NSScreen.preferred.isHorizontal()
        maxWidthOnScreen = AppearanceTestable.comfortableWidth(NSScreen.preferred.physicalSize().map { $0.width })
        let sizeToApply: AppearanceSizePreference = currentSize == .auto ? .large : currentSize
        resolvedSize = sizeToApply
        applyConcreteSize(sizeToApply, isHorizontalScreen)
        updateFont()
    }

    static func applySize(_ size: AppearanceSizePreference) {
        let isHorizontalScreen = NSScreen.preferred.isHorizontal()
        resolvedSize = size
        applyConcreteSize(size, isHorizontalScreen)
        updateFont()
    }

    private static func applyConcreteSize(_ size: AppearanceSizePreference, _ isHorizontalScreen: Bool) {
        if currentStyle == .appIcons {
            appIconsSize(size)
        } else if currentStyle == .titles {
            titlesSize(isHorizontalScreen, size)
        } else {
            thumbnailsSize(isHorizontalScreen, size)
        }
    }

    private static func updateTheme() {
        highlightBorderWidth = currentStyle == .titles ? 0 : 3
        if currentTheme == .dark {
            darkTheme()
        } else {
            lightTheme()
        }
        // for Liquid Glass, we don't want a shadow around the panel
        if #available(macOS 26.0, *), currentStyle == .appIcons && LiquidGlassEffectView.canUsePrivateLiquidGlassLook() {
            enablePanelShadow = false
        } else {
            enablePanelShadow = true
        }
    }

    private static func thumbnailsSize(_ isHorizontalScreen: Bool, _ size: AppearanceSizePreference) {
        hideThumbnails = false
        windowPadding = 18
        windowCornerRadius = 23
        cellCornerRadius = 10
        edgeInsetsSize = 12
        if #available(macOS 26.0, *) {
            windowPadding = 28
            windowCornerRadius = 43
            cellCornerRadius = 18
        }
        switch size {
            case .small:
                rowsCount = isHorizontalScreen ? 5 : 8
                iconSize = 16
                fontHeight = 13
            case .medium:
                rowsCount = isHorizontalScreen ? 4 : 7
                iconSize = 26
                fontHeight = 14
            case .large, .auto:
                rowsCount = isHorizontalScreen ? 3 : 6
                iconSize = 28
                fontHeight = 16
        }
        let tilesPanelRatio = (NSScreen.preferred.frame.width * maxWidthOnScreen) / (NSScreen.preferred.frame.height * maxHeightOnScreen)
        (windowMinWidthInRow, windowMaxWidthInRow) = AppearanceTestable.goodValuesForThumbnailsWidthMinMax(tilesPanelRatio, rowsCount)
    }

    private static func appIconsSize(_ size: AppearanceSizePreference) {
        hideThumbnails = true
        windowPadding = 25
        windowCornerRadius = 23
        cellCornerRadius = 10
        edgeInsetsSize = 5
        if #available(macOS 26.0, *) {
            edgeInsetsSize = 6
        }
        windowMinWidthInRow = 0.04
        windowMaxWidthInRow = 0.3
        rowsCount = 1
        switch size {
            case .small:
                iconSize = 70
                fontHeight = 13
                if #available(macOS 26.0, *) {
                    windowCornerRadius = 50
                    cellCornerRadius = 24
                }
            case .medium:
                iconSize = 110
                fontHeight = 14
                if #available(macOS 26.0, *) {
                    windowCornerRadius = 55
                    cellCornerRadius = 35
                }
            case .large, .auto:
                windowPadding = 28
                iconSize = 150
                fontHeight = 16
                if #available(macOS 26.0, *) {
                    windowCornerRadius = 75
                    cellCornerRadius = 45
                }
        }
    }

    private static func titlesSize(_ isHorizontalScreen: Bool, _ size: AppearanceSizePreference) {
        hideThumbnails = true
        windowPadding = 14
        windowCornerRadius = 23
        cellCornerRadius = 8
        edgeInsetsSize = 6
        windowMinWidthInRow = 0.6
        windowMaxWidthInRow = 0.9
        rowsCount = 1
        switch size {
            case .small:
                iconSize = 18
                fontHeight = 13
            case .medium:
                iconSize = 20
                fontHeight = 14
            case .large, .auto:
                iconSize = 24
                fontHeight = 16
        }
    }

    private static func updateFont() {
        if #available(macOS 26.0, *) {
            font = NSFont.systemFont(ofSize: fontHeight, weight: currentStyle == .appIcons ? .semibold : .medium)
        } else {
            font = NSFont.systemFont(ofSize: fontHeight)
        }
        appNameFont = NSFont.systemFont(ofSize: fontHeight, weight: .semibold)
    }

    private static func lightTheme() {
        imagesShadowColor = .gray.withAlphaComponent(0.8)
        material = preferredMaterial(forDark: false)
    }

    private static func darkTheme() {
        imagesShadowColor = .gray.withAlphaComponent(0.8)
        material = preferredMaterial(forDark: true)
    }

    // hudWindow 仅 10.14+ 可用；老系统回退到原 mediumLight/dark，保证编译与运行兼容
    private static func preferredMaterial(forDark: Bool) -> NSVisualEffectView.Material {
        if #available(macOS 10.14, *) {
            return .hudWindow
        }
        return forDark ? .dark : .mediumLight
    }
}
