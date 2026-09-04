import AppKit
import Carbon.HIToolbox

/// Carbon RegisterEventHotKey 封装：免辅助功能权限的全局热键。
/// 支持按 id 注销重注册（设置里改键），以及录制期间整体暂停。
final class HotkeyManager {
    private var actions: [UInt32: () -> Void] = [:]
    private var hotKeyRefs: [UInt32: EventHotKeyRef] = [:]
    private var specs: [UInt32: HotkeySpec] = [:]
    private var handlerRef: EventHandlerRef?

    func install() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData -> OSStatus in
            guard let userData, let event else { return noErr }
            var hkID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hkID)
            let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
            // Carbon 事件在主线程 run loop 分发，编译器无法证明，运行期断言兜底
            MainActor.assumeIsolated {
                manager.actions[hkID.id]?()
            }
            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &handlerRef)
    }

    /// 改键结果。失败原因要分开，否则 UI 只能笼统报「被其他应用占用」，会误导排查方向
    enum RebindResult: Equatable {
        case ok
        /// 该组合已分配给本 App 的另一个功能（参数是那个功能的 id）
        case usedByOwnHotkey(UInt32)
        /// RegisterEventHotKey 失败，通常是被别的 App 或系统抢先注册
        case rejectedBySystem
        /// 这个 id 从未绑定过 action，属于内部状态异常
        case notBound
    }

    /// 返回 false 表示热键被其他应用占用
    @discardableResult
    func register(id: UInt32, spec: HotkeySpec, action: @escaping () -> Void) -> Bool {
        unregister(id: id)
        // 注册失败也要留住 action：否则这个 id 的 rebind 会永远走不下去，
        // 用户在设置里换任何键都只能得到一句假的「被其他应用占用」
        actions[id] = action
        var ref: EventHotKeyRef?
        let hkID = EventHotKeyID(signature: OSType(0x4D52_4359) /* 'MRCY' */, id: id)
        let status = RegisterEventHotKey(spec.keyCode, spec.carbonModifiers, hkID,
                                         GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else {
            specs[id] = nil
            return false
        }
        hotKeyRefs[id] = ref
        specs[id] = spec
        return true
    }

    /// 改键：保留 action，换新按键。失败时回滚到旧键。
    func rebind(id: UInt32, to spec: HotkeySpec) -> RebindResult {
        guard let action = actions[id] else { return .notBound }
        // 录制期间全部热键处于暂停态，系统查不出「和自己另一个功能撞键」，只能自己比对。
        // 漏掉这层会让两个功能存成同一个键，重启后后注册的那个永久失效
        if let other = specs.first(where: { $0.key != id && $0.value == spec })?.key {
            return .usedByOwnHotkey(other)
        }
        let oldSpec = specs[id]
        if register(id: id, spec: spec, action: action) {
            return .ok
        }
        if let oldSpec {
            _ = register(id: id, spec: oldSpec, action: action)
        }
        return .rejectedBySystem
    }

    /// 首次绑定或重新绑定。窗口动作允许在设置中先停用再重新录制，因此不能要求 id 已绑定。
    func bind(id: UInt32, spec: HotkeySpec, action: @escaping () -> Void) -> RebindResult {
        if let other = specs.first(where: { $0.key != id && $0.value == spec })?.key {
            return .usedByOwnHotkey(other)
        }
        let oldSpec = specs[id]
        let oldAction = actions[id]
        unregister(id: id)
        if register(id: id, spec: spec, action: action) {
            return .ok
        }
        if let oldSpec, let oldAction {
            _ = register(id: id, spec: oldSpec, action: oldAction)
        }
        return .rejectedBySystem
    }

    func unregister(id: UInt32) {
        if let ref = hotKeyRefs.removeValue(forKey: id) {
            UnregisterEventHotKey(ref)
        }
        specs[id] = nil
        // 保留 actions[id]，rebind 需要
    }

    /// 录制新快捷键期间暂停所有热键，避免录制时误触发
    private var suspended: [(id: UInt32, spec: HotkeySpec)] = []

    func suspendAll() {
        suspended = specs.map { ($0.key, $0.value) }
        for (id, _) in suspended {
            if let ref = hotKeyRefs.removeValue(forKey: id) {
                UnregisterEventHotKey(ref)
            }
        }
    }

    func resumeAll() {
        for (id, snapshot) in suspended {
            guard let action = actions[id] else { continue }
            // rebind 发生在 resumeAll 之前，specs 里可能已是新键，
            // 用快照会把刚改好的键覆盖回旧键，所以以 specs 为准
            _ = register(id: id, spec: specs[id] ?? snapshot, action: action)
        }
        suspended = []
    }
}
