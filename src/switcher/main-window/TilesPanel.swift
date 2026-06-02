import Cocoa

class TilesPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    static var maxPossibleThumbnailSize = NSSize.zero
    static var maxPossibleAppIconSize = NSSize.zero
    static var shared: TilesPanel!
    private var frozenTopCenter: NSPoint?
    private var highWaterHeight: CGFloat = 0

    convenience init() {
        self.init(contentRect: .zero, styleMask: .nonactivatingPanel, backing: .buffered, defer: false)
        delegate = self
        isFloatingPanel = true
        animationBehavior = .none
        hidesOnDeactivate = false
        titleVisibility = .hidden
        backgroundColor = .clear
        TilesView.initialize()
        contentView! = TilesView.contentView
        // triggering AltTab before or during Space transition animation brings the window on the Space post-transition
        collectionBehavior = .canJoinAllSpaces
        // 2nd highest level possible; this allows the app to go on top of context menus
        // highest level is .screenSaver but makes drag and drop on top the main window impossible
        level = .popUpMenu
        // helps filter out this window from the thumbnails
        setAccessibilitySubrole(.unknown)
        // for VoiceOver
        setAccessibilityLabel(App.name)
        updateAppearance()
        Self.shared = self
    }

    func updateAppearance() {
        hasShadow = Appearance.enablePanelShadow
        appearance = NSAppearance(named: Appearance.currentTheme == .dark ? .vibrantDark : .vibrantLight)
    }

    func updateContents(_ preservedScrollOrigin: CGPoint?) {
        caTransaction {
            TilesView.updateItemsAndLayout(preservedScrollOrigin)
            guard SwitcherSession.isActive else { return }
            setContentSize(TilesView.contentView.frame.size)
            guard SwitcherSession.isActive else { return }
            repositionOrFreeze()
        }
        // prevent further AppKit work
        TilesView.clearNeedsLayout()
    }


    private func repositionOrFreeze() {
        let size = frame.size
        guard TilesView.isSearchModeOn else {
            NSScreen.preferred.repositionPanel(self)
            resetFrozenPosition()
            return
        }
        if size.height > highWaterHeight {
            NSScreen.preferred.repositionPanel(self)
            highWaterHeight = size.height
            frozenTopCenter = NSPoint(x: frame.midX, y: frame.maxY)
        } else if let topCenter = frozenTopCenter {
            setFrameOrigin(NSPoint(x: topCenter.x - size.width * 0.5, y: topCenter.y - size.height))
        }
    }

    func resetFrozenPosition() {
        frozenTopCenter = nil
        highWaterHeight = 0
    }

    override func orderOut(_ sender: Any?) {
        TilesView.clearNeedsLayout()
        if Preferences.fadeOutAnimation {
            NSAnimationContext.runAnimationGroup(
                { _ in animator().alphaValue = 0 },
                completionHandler: { super.orderOut(sender) }
            )
        } else {
            // orderOut requires WindowServer. Let's hide before calling it, in case it lags
            alphaValue = 0
            super.orderOut(sender)
        }
    }

    func show() {
        updateAppearance()
        // The panel may have been hidden (alpha=0) by `App.showUiOrCycleSelection` on a
        // cross-shortcut summon to mask the rebuild. Reveal it atomically now that contents
        // and Appearance are in their final state.
        alphaValue = 1
        makeKeyAndOrderFront(nil)
        ContextMenuEvents.toggle(true)
        CursorEvents.toggle(true)
        DispatchQueue.main.async { TilesView.scrollView.flashScrollers() }
    }

    static func maxThumbnailsWidth(_ screen: NSScreen = NSScreen.preferred) -> CGFloat {
        if Preferences.effectiveAppearanceStyle(SwitcherSession.activeShortcutIndex) == .titles {
            // titles 风格按当前可见窗口的最长标题做内容自适应；其它风格保持屏宽比例。
            // 上限三选最小：屏宽比例、880pt 软上限；下限保证极短列表不至于细长难看。
            let titlesSoftCap = CGFloat(880)
            let screenCap = (screen.frame.width * Appearance.maxWidthOnScreen - Appearance.windowPadding * 2)
            let upperBound = min(screenCap, titlesSoftCap - Appearance.windowPadding * 2)
            let lowerBound = CGFloat(380)
            // 单行所需 frame 宽 = 最长标题 + 左侧图标 + 图标-标题间距 + 右侧状态徽标 + 两侧 edgeInsets。
            // 不除 windowMaxWidthInRow(0.9)：那个比例是行内 tile 占面板宽的比例；用 (.../0.9) 还原面板宽，
            // 使 setFrameWidthHeight 计算出的 contentWidth 恰好容纳最长标题，不留多余右侧空白。
            let titleWidth = TilesView.layoutCache.longestVisibleTitleWidth ?? 0
            let statusWidth = TilesView.layoutCache.maxStatusIconsWidth
            let tileFrameNeeded = titleWidth + Appearance.iconSize + Appearance.appIconLabelSpacing
                + statusWidth + Appearance.edgeInsetsSize * 2
            let widthRatio = max(Appearance.windowMaxWidthInRow, 0.01)
            let contentNeeded = (tileFrameNeeded + Appearance.interCellPadding * 2) / widthRatio
            let clamped = min(max(contentNeeded, lowerBound), upperBound)
            return clamped.rounded()
        }
        return (screen.frame.width * Appearance.maxWidthOnScreen - Appearance.windowPadding * 2).rounded()
    }

    static func maxThumbnailsHeight(_ screen: NSScreen = NSScreen.preferred) -> CGFloat {
        return (screen.frame.height * Appearance.maxHeightOnScreen - Appearance.windowPadding * 2).rounded()
    }

    static func updateMaxPossibleThumbnailSize() {
        let (w, h) = NSScreen.screens.reduce((CGFloat.zero, CGFloat.zero)) { acc, screen in
            (max(acc.0, TileView.maxThumbnailWidth(screen) * screen.backingScaleFactor),
            max(acc.1, TileView.maxThumbnailHeight(screen) * screen.backingScaleFactor))
        }
        maxPossibleThumbnailSize = NSSize(width: w.rounded(), height: h.rounded())
    }

    static func updateMaxPossibleAppIconSize() {
        let (w, h) = NSScreen.screens.reduce((CGFloat.zero, CGFloat.zero)) { acc, screen in
            // in Thumbnails Appearance, AppIcons can be used for windowless apps, thus much bigger than the app icon near the title
            if Preferences.effectiveAppearanceStyle(SwitcherSession.activeShortcutIndex) == .thumbnails {
                return (max(acc.0, TileView.maxThumbnailWidth(screen) * screen.backingScaleFactor),
                    max(acc.1, TileView.maxThumbnailHeight(screen) * screen.backingScaleFactor))
            } else {
                let size = TileView.iconSize(screen)
                return (max(acc.0, size.width * screen.backingScaleFactor),
                    max(acc.1, size.height * screen.backingScaleFactor))
            }
        }
        maxPossibleAppIconSize = NSSize(width: w.rounded(), height: h.rounded())
    }
}

extension TilesPanel: NSWindowDelegate {
    func windowDidResignKey(_ notification: Notification) {
        // other windows can steal key focus from alt-tab; we make sure that if it's active, if keeps key focus
        // dispatching to the main queue is necessary to introduce a delay in scheduling the makeKey; otherwise it is ignored
        DispatchQueue.main.async {
            if SwitcherSession.isActive {
                TilesPanel.shared.makeKeyAndOrderFront(nil)
            }
            MainMenu.toggle(true)
        }
    }

    func windowDidBecomeKey(_ notification: Notification) {
        // we toggle the mainMenu off when showing the main window
        // this avoids command+q from quitting AltTab itself, or command+p from printing
        DispatchQueue.main.async {
            MainMenu.toggle(false)
            if TilesView.isSearchEditing {
                MainMenu.toggleEditMenu(true)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            Applications.manuallyRefreshAllWindows()
        }
    }
}
