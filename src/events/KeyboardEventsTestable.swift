import ShortcutRecorder

class KeyboardEventsTestable {
    /// app 侧注入（见 KeyboardEvents.addEventHandlers）：titles 风格下聚焦第 n 个可见窗口并返回 true。
    /// 为 nil 时（如 unit-tests 目标，不含 Windows/App 等符号）⌘数字直跳静默失效，保证此文件可独立编译。
    static var directSelectJump: ((Int) -> Bool)?

    static var globalShortcutsIds: [String: Int] {
        var ids = [String: Int]()
        (0..<Preferences.maxShortcutCount).forEach { ids[Preferences.indexToName("nextWindowShortcut", $0)] = $0 }
        (0..<Preferences.maxShortcutCount).forEach { ids[Preferences.indexToName("holdShortcut", $0)] = Preferences.maxShortcutCount + $0 }
        return ids
    }
}

@discardableResult
func handleKeyboardEvent(_ globalId: Int?, _ shortcutState: ShortcutState?, _ keyCode: UInt32?, _ modifiers: NSEvent.ModifierFlags?, _ isARepeat: Bool, _ event: NSEvent? = nil) -> Bool {
    // ⌘+数字 1–9：titles 风格 switcher 打开时直跳第 N 个可见窗口（与右侧 ⌘N 徽标一致）。
    // 用 ⌘ 修饰避免与搜索框输入数字冲突，且放在搜索拦截之前，搜索编辑态下同样生效。
    // 必须排除 ⇧/⌃：否则 ⌘⇧3/⌘⇧4/⌘⇧5 截图（keycode 含数字键 21=4 等）会被当成「跳第 N 窗口」吞掉。
    // 纯键码/修饰判断留在此（可测试）；「titles 风格 + 取第 N 窗口并聚焦」依赖 app 专属符号，走 directSelectJump 钩子。
    if SwitcherSession.isActive, let keyCode, let modifiers,
       modifiers.contains(.command), !modifiers.contains(.shift), !modifiers.contains(.control),
       let n = directSelectDigit(keyCode), KeyboardEventsTestable.directSelectJump?(n) == true {
        return true
    }
    if let event, shouldAbsorbSearchEditingKeyDown(event) {
        switch TilesView.handleSearchEditingKeyDown(event) {
        case .handled: return true
        case .passToField: return false
        case .passToShortcuts: break
        }
    }
    logKeyboardEvent(globalId, shortcutState, keyCode, modifiers, isARepeat)
    let someShortcutTriggered = triggerMatchingShortcuts(globalId, shortcutState, keyCode, modifiers, isARepeat)
    return someShortcutTriggered
}

private func logKeyboardEvent(_ globalId: Int?, _ shortcutState: ShortcutState?, _ keyCode: UInt32?, _ modifiers: NSEvent.ModifierFlags?, _ isARepeat: Bool) {
    if let globalId, let shortcutState {
        Logger.debug {
            let shortcut = KeyboardEventsTestable.globalShortcutsIds.first { $0.value == globalId }
            return "globalShortcut:\(shortcut?.key ?? "") state:\(shortcutState)"
        }
        return
    }
    // TODO: use proper pattern from SwiftBeaver to not compute SymbolicModifierFlagsTransformer when logs are off
    Logger.debug {
        let modifiersAsString = modifiers.flatMap { SymbolicModifierFlagsTransformer.shared.transformedValue(NSNumber(value: $0.rawValue)) }
        let keyCodeAsString = keyCode.flatMap { SymbolicKeyCodeTransformer.shared.transformedValue(NSNumber(value: $0)) }
        return "keys:\(modifiersAsString ?? "")\(keyCodeAsString ?? "") isARepeat:\(isARepeat)"
    }
}

/// ANSI 数字键 1–9 的键码 → 数字；其它返回 nil。switcher 打开时数字键直选第 N 个窗口
private func directSelectDigit(_ keyCode: UInt32) -> Int? {
    switch keyCode {
    case 18: return 1
    case 19: return 2
    case 20: return 3
    case 21: return 4
    case 23: return 5
    case 22: return 6
    case 26: return 7
    case 28: return 8
    case 25: return 9
    default: return nil
    }
}

private func shouldAbsorbSearchEditingKeyDown(_ event: NSEvent?) -> Bool {
    guard let event, event.type == .keyDown, SwitcherSession.isActive, TilesPanel.shared.isKeyWindow, TilesView.isSearchEditing else {
        return false
    }
    return true
}

private func triggerMatchingShortcuts(_ globalId: Int?, _ shortcutState: ShortcutState?, _ keyCode: UInt32?, _ modifiers: NSEvent.ModifierFlags?, _ isARepeat: Bool) -> Bool {
    var someShortcutTriggered = false
    for shortcut in ControlsTab.shortcuts.values {
        if shortcut.matches(globalId, shortcutState, keyCode, modifiers) && shortcut.shouldTrigger() {
            shortcut.executeAction(isARepeat)
            // we want to pass-through alt-up to the active app, since it saw alt-down previously
            if !shortcut.id.starts(with: "holdShortcut") {
                someShortcutTriggered = true
            }
        }
        shortcut.redundantSafetyMeasures()
    }
    // TODO if we manage to move all keyboard listening to the background thread, we'll have issues returning this boolean
    // this function uses many objects that are also used on the main-thread. It also executes the actions
    // we'll have to rework this whole approach. Today we rely on somewhat in-order events/actions
    // special attention should be given to SwitcherSession.current which is being set when executing the nextWindowShortcut action
    return someShortcutTriggered
}
