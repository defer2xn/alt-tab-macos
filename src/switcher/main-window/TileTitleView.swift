import Cocoa

class TileTitleView: NSTextField {
    static let searchHighlightBackgroundKey = NSAttributedString.Key("tileSearchHighlightBackground")
    private var currentWidth: CGFloat = -1
    // 每帧最多 20 个 tile 绘制，原实现每次 draw 都新建一整套 Cocoa 文本布局栈
    // (NSTextStorage/NSLayoutManager/NSTextContainer)——这是文本渲染里最贵的对象。
    // 这里改为每个实例复用同一套，draw 里只 setAttributedString + 按需调 size。
    private let highlightTextStorage = NSTextStorage()
    private let highlightLayoutManager = NSLayoutManager()
    private let highlightTextContainer = NSTextContainer(size: .zero)

    // we set their size manually; override this to remove wasteful appkit-side work
    override var intrinsicContentSize: NSSize {
        return NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }

    // 关闭 vibrancy：在毛玻璃面板里 NSTextField 默认会被"洗"成偏灰，关掉后文字以实色清晰渲染（与自绘的 ⌘N 徽标一致）
    override var allowsVibrancy: Bool { false }

    /// `NSView` is its own `CALayerDelegate`. By implementing `action(for:forKey:)` on this
    /// subclass we intercept the lookup AppKit performs when a layer property changes, and
    /// return `NSNull()` for the animation keys — the documented "no animation for this key"
    /// sentinel. Without this, the label slides smoothly from its previous-style position
    /// during a cross-style summon (e.g. right-of-icon → under-icon when going thumbnails →
    /// appIcons), because `caTransaction { setDisableActions(true) }` in `TilesPanel.updateContents`
    /// doesn't cover the follow-up layout pass that `NSWindow.setContentSize` triggers outside
    /// the transaction.
    ///
    /// Not marked `override`: `NSView`'s `CALayerDelegate` conformance is via Objective-C and
    /// Swift doesn't expose the method as overridable. Providing it here at the Swift level
    /// installs it for the runtime to find when the layer asks the delegate for actions.
    @objc func action(for layer: CALayer, forKey event: String) -> CAAction? {
        switch event {
        case "position", "bounds", "frame", "hidden", "opacity", "transform":
            return NSNull()
        default:
            return nil
        }
    }

    convenience init(font: NSFont) {
        self.init(frame: .zero)
        stringValue = ""
        isEditable = false
        isSelectable = false
        isBezeled = false
        drawsBackground = false
        self.font = font
        textColor = Appearance.fontColor
        lineBreakMode = .byTruncatingTail
        allowsDefaultTighteningForTruncation = false
        highlightTextContainer.lineFragmentPadding = 0
        highlightTextContainer.maximumNumberOfLines = 1
        highlightTextContainer.lineBreakMode = .byClipping
        highlightLayoutManager.addTextContainer(highlightTextContainer)
        highlightTextStorage.addLayoutManager(highlightLayoutManager)
    }

    override func draw(_ dirtyRect: NSRect) {
        drawRoundedSearchHighlights()
        super.draw(dirtyRect)
    }

    func fixHeight() {
        frame.size.height = cell!.cellSize.height
    }

    func setWidth(_ width: CGFloat) {
        guard currentWidth != width else { return }
        currentWidth = width
        frame.size.width = width
    }

    func updateTruncationModeIfNeeded() {
        let newLineBreakMode = getTruncationMode()
        if lineBreakMode != newLineBreakMode {
            lineBreakMode = newLineBreakMode
        }
    }

    private func getTruncationMode() -> NSLineBreakMode {
        if Preferences.titleTruncation == .end {
            return .byTruncatingTail
        }
        if Preferences.titleTruncation == .middle {
            return .byTruncatingMiddle
        }
        return .byTruncatingHead
    }

    private func drawRoundedSearchHighlights() {
        let attributed = attributedStringValue
        guard attributed.length > 0 else { return }
        var hasHighlights = false
        attributed.enumerateAttribute(Self.searchHighlightBackgroundKey, in: NSRange(location: 0, length: attributed.length)) { value, _, stop in
            if value != nil {
                hasHighlights = true
                stop.pointee = true
            }
        }
        guard hasHighlights else { return }
        let textRect = cell?.drawingRect(forBounds: bounds) ?? bounds
        guard textRect.width > 0, textRect.height > 0 else { return }
        // 复用实例字段而不是每帧重建：先重置内容，再按需更新容器尺寸，最后 ensureLayout，
        // 保证后面 boundingRect 取到的是当前内容/尺寸下的最新 glyph 布局。
        highlightTextStorage.setAttributedString(attributed)
        if highlightTextContainer.size != textRect.size {
            highlightTextContainer.size = textRect.size
        }
        highlightLayoutManager.ensureLayout(for: highlightTextContainer)
        attributed.enumerateAttribute(Self.searchHighlightBackgroundKey, in: NSRange(location: 0, length: attributed.length)) { value, range, _ in
            guard let color = value as? NSColor else { return }
            let glyphRange = highlightLayoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            guard glyphRange.length > 0 else { return }
            let glyphRect = highlightLayoutManager.boundingRect(forGlyphRange: glyphRange, in: highlightTextContainer)
            guard glyphRect.width > 0, glyphRect.height > 0 else { return }
            var rect = glyphRect
            rect.origin.x += textRect.origin.x + 1.05
            rect.origin.y += textRect.origin.y + 0.45
            rect.size.width += 0.75
            rect.size.height = max(1, rect.size.height - 0.9)
            rect = pixelAligned(rect)
            let radius = min(4, rect.height * 0.35)
            color.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
        }
    }

    private func pixelAligned(_ rect: NSRect) -> NSRect {
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        var result = rect
        result.origin.x = round(result.origin.x * scale) / scale
        result.origin.y = round(result.origin.y * scale) / scale
        result.size.width = max(1 / scale, ceil(result.size.width * scale) / scale)
        result.size.height = max(1 / scale, ceil(result.size.height * scale) / scale)
        return result
    }
}
