import Cocoa

class TileUnderLayer: CALayer {
    let focusedLayer = noAnimation { CALayer() }
    let hoveredLayer = noAnimation { CALayer() }
    let focusedIndicatorLayer = noAnimation { CALayer() }

    override init() {
        super.init()
        delegate = NoAnimationDelegate.shared
        for highlightLayer in [focusedLayer, hoveredLayer] {
            highlightLayer.isHidden = true
            addSublayer(highlightLayer)
        }
        focusedIndicatorLayer.isHidden = true
        focusedLayer.addSublayer(focusedIndicatorLayer)
    }

    required init?(coder: NSCoder) { fatalError() }

    func updateHighlight(focusedView: TileView?, hoveredView: TileView?) {
        updateLayer(focusedLayer, for: focusedView, isFocused: true)
        updateLayer(hoveredLayer, for: hoveredView, isFocused: false)
    }

    private func updateLayer(_ highlightLayer: CALayer, for view: TileView?, isFocused: Bool) {
        guard let view, view.frame != .zero else {
            highlightLayer.isHidden = true
            if isFocused { focusedIndicatorLayer.isHidden = true }
            return
        }
        let hf = view.highlightFrame
        let rect = CGRect(
            x: view.frame.origin.x + hf.origin.x,
            y: view.frame.origin.y + hf.origin.y,
            width: hf.width,
            height: hf.height
        )
        highlightLayer.frame = rect
        highlightLayer.cornerRadius = Appearance.cellCornerRadius
        highlightLayer.backgroundColor = (isFocused
            ? Appearance.highlightFocusedBackgroundColor
            : Appearance.highlightHoveredBackgroundColor).cgColor
        highlightLayer.borderColor = (isFocused
            ? Appearance.highlightFocusedBorderColor
            : Appearance.highlightHoveredBorderColor).cgColor
        highlightLayer.borderWidth = Appearance.highlightBorderWidth
        highlightLayer.isHidden = false
        if isFocused { updateFocusedIndicator(in: rect.size) }
    }

    // 左侧指示条：宽度 0 表示当前样式不绘制（非 titles）。位于聚焦层内，垂直居中、避开圆角。
    private func updateFocusedIndicator(in size: CGSize) {
        let width = Appearance.highlightFocusedIndicatorWidth
        guard width > 0 else {
            focusedIndicatorLayer.isHidden = true
            return
        }
        let barHeight = (size.height * 0.55).rounded()
        focusedIndicatorLayer.frame = CGRect(x: 3, y: (size.height - barHeight) / 2, width: width, height: barHeight)
        focusedIndicatorLayer.cornerRadius = width / 2
        focusedIndicatorLayer.backgroundColor = Appearance.highlightFocusedIndicatorColor.cgColor
        focusedIndicatorLayer.isHidden = false
    }
}
