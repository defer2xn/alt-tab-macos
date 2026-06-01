import Cocoa

/// this is a lightweight CALayer which displays an image
/// it is an alternative to NSView-based image display, avoiding AppKit overhead (layout recursion, responder chain, drag-and-drop)
class LightImageLayer: CALayer {
    // 仅内容不透明的矩形（缩略图）才设 shadowPath 消除离屏渲染；透明图标保留 alpha 推导的轮廓阴影
    var usesShadowPath = false
    override init() {
        super.init()
        contentsGravity = .resize
        magnificationFilter = .trilinear
        minificationFilter = .trilinear
        minificationFilterBias = 0.0
        shouldRasterize = false
        delegate = NoAnimationDelegate.shared
    }

    required init?(coder: NSCoder) {
        fatalError("Class only supports programmatic initialization")
    }

    override init(layer: Any) {
        super.init(layer: layer)
    }

    func updateContents(_ caLayerContents: CALayerContents, _ size: NSSize) {
        switch caLayerContents {
        case .cgImage(let image?):
            contents = image
        case .pixelBuffer(let pixelBuffer?):
            contents = CVPixelBufferGetIOSurface(pixelBuffer)?.takeUnretainedValue()
        default: break
        }
        if frame.size != size {
            frame.size = size
            // bounds 变了 shadowPath 必须跟着重设，否则阴影形状错位
            if usesShadowPath { updateShadowPathIfNeeded() }
        }
    }

    func releaseImage() {
        contents = nil
    }
}
