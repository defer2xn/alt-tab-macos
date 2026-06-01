import Cocoa

class Throttler {
    private let delayInNanoseconds: UInt64
    private var lastTimeInNanoseconds = DispatchTime.now().uptimeNanoseconds
    private var nextScheduled = false

    init(delayInMs: Int) {
        self.delayInNanoseconds = UInt64(delayInMs) * 1_000_000
    }

    func throttleOrProceed(_ block: @escaping () -> Void) {
        dispatchPrecondition(condition: .onQueue(.main))
        let now = DispatchTime.now().uptimeNanoseconds
        let (elapsed, overflow) = now.subtractingReportingOverflow(lastTimeInNanoseconds)
        if !overflow, elapsed >= delayInNanoseconds {
            lastTimeInNanoseconds = now
            block()
            return
        }
        guard !nextScheduled else { return }
        nextScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + .nanoseconds(Int(delayInNanoseconds))) { [self] in
            nextScheduled = false
            lastTimeInNanoseconds = DispatchTime.now().uptimeNanoseconds
            block()
        }
    }
}

class ThrottlerWithKey {
    private let delayInNanoseconds: UInt64
    private let map = ConcurrentMap<String, ThrottleState>()

    private struct ThrottleState {
        let time: UInt64
        var tailScheduled: Bool
    }

    init(delayInMs: Int) {
        self.delayInNanoseconds = UInt64(delayInMs) * 1_000_000
    }

    func removeEntry(withKey key: String) {
        map.withLock { $0[key] = nil }
    }

    func removeEntries(withSuffix suffix: String) {
        map.withLock { map in
            for key in map.keys where key.hasSuffix(suffix) {
                map[key] = nil
            }
        }
    }

    func removeEntries(withPrefix prefix: String) {
        map.withLock { map in
            for key in map.keys where key.hasPrefix(prefix) {
                map[key] = nil
            }
        }
    }

    func throttleOrProceed(key: String, queue: LabeledOperationQueue? = nil, priority: Operation.QueuePriority = .normal, _ block: @escaping () -> Void) {
        // 锁内只决策与改 map；asyncAfter 放到解锁后调用，避免在 os_unfair_lock 临界区内进系统调度
        enum Decision { case proceed, drop, scheduleTail(UInt64) }
        let decision: Decision = map.withLock { map in
            let now = DispatchTime.now().uptimeNanoseconds
            if let state = map[key] {
                let elapsed = now >= state.time ? (now - state.time) : delayInNanoseconds
                if elapsed < delayInNanoseconds {
                    guard !state.tailScheduled else { return .drop }
                    map[key] = ThrottleState(time: state.time, tailScheduled: true)
                    return .scheduleTail(delayInNanoseconds - elapsed)
                }
            }
            map[key] = ThrottleState(time: now, tailScheduled: false)
            return .proceed
        }
        switch decision {
        case .drop:
            return
        case .proceed:
            if let queue {
                let op = BlockOperation(block: block)
                op.queuePriority = priority
                queue.addOperation(op)
            } else {
                block()
            }
        case .scheduleTail(let remaining):
            let tailBlock = { [self] in
                let shouldExecute = map.withLock { map -> Bool in
                    guard let state = map[key], state.tailScheduled else { return false }
                    map[key] = ThrottleState(time: DispatchTime.now().uptimeNanoseconds, tailScheduled: false)
                    return true
                }
                if shouldExecute { block() }
            }
            if let queue {
                queue.strongUnderlyingQueue.asyncAfter(deadline: .now() + .nanoseconds(Int(remaining))) { [weak queue] in
                    guard let queue else { return }
                    let op = BlockOperation(block: tailBlock)
                    op.queuePriority = priority
                    queue.addOperation(op)
                }
            } else {
                let callerQueue = OperationQueue.current?.underlyingQueue ?? DispatchQueue.main
                callerQueue.asyncAfter(deadline: .now() + .nanoseconds(Int(remaining)), execute: tailBlock)
            }
        }
    }
}

final class ConcurrentMap<K: Hashable, V>: @unchecked Sendable {
    private var map = [K: V]()
    // os_unfair_lock is ~10x lighter than NSLock on the uncontended path (single atomic CAS, no ObjC dispatch).
    // The hot path holds the lock for a dictionary lookup or assignment only; contention is rare.
    private let lock: UnsafeMutablePointer<os_unfair_lock> = {
        let p = UnsafeMutablePointer<os_unfair_lock>.allocate(capacity: 1)
        p.initialize(to: os_unfair_lock())
        return p
    }()

    deinit {
        lock.deinitialize(count: 1)
        lock.deallocate()
    }

    @discardableResult
    @inline(__always)
    func withLock<T>(_ block: (inout [K: V]) -> T) -> T {
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }
        return block(&map)
    }
}

final class ConcurrentArray<T>: @unchecked Sendable {
    private var array: [T]
    private let lock: UnsafeMutablePointer<os_unfair_lock> = {
        let p = UnsafeMutablePointer<os_unfair_lock>.allocate(capacity: 1)
        p.initialize(to: os_unfair_lock())
        return p
    }()

    init(_ initial: [T] = []) { self.array = initial }

    deinit {
        lock.deinitialize(count: 1)
        lock.deallocate()
    }

    @discardableResult
    @inline(__always)
    func withLock<R>(_ block: (inout [T]) -> R) -> R {
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }
        return block(&array)
    }
}
