// `Operation`, `BlockOperation` and `OperationQueue` for wasm (RevenueCat's network operations,
// SDWebImage's download queue). The page has one thread, so a queue starts its operations on
// the main queue's next turn, in order of priority and as their dependencies finish. An
// asynchronous subclass overrides `start()` or `main()` and reports `isExecuting` and
// `isFinished` by hand with `willChangeValue(forKey:)` / `didChangeValue(forKey:)`; the
// operation watches its own `isFinished`, so that report runs its completion block and moves
// its queue on.
#if os(WASI)

/// One unit of work: run by a queue, or started by hand with `start()`.
open class Operation: NSObject, @unchecked Sendable {
    public enum QueuePriority: Int, Sendable {
        case veryLow = -8, low = -4, normal = 0, high = 4, veryHigh = 8
    }

    private var _cancelled = false
    private var _executing = false
    private var _finished = false
    private var _dependencies: [Operation] = []
    /// Operations waiting on this one, told to look again when it finishes.
    private var _dependents: [_WeakOperation] = []
    private var _completed = false
    private var _finishObservation: NSKeyValueObservation?
    /// The queue running this operation.
    weak var _queue: OperationQueue?

    #if _runtime(_ObjC)
    @objc open var isCancelled: Bool { _cancelled }
    @objc open var isExecuting: Bool { _executing }
    @objc open var isFinished: Bool { _finished }
    @objc open var isAsynchronous: Bool { false }
    @objc open var isReady: Bool { _dependencies.allSatisfy(\.isFinished) }
    #else
    open var isCancelled: Bool { _cancelled }
    open var isExecuting: Bool { _executing }
    open var isFinished: Bool { _finished }
    open var isAsynchronous: Bool { false }
    open var isReady: Bool { _dependencies.allSatisfy(\.isFinished) }
    #endif
    open var isConcurrent: Bool { isAsynchronous }
    open var name: String?
    open var queuePriority: QueuePriority = .normal
    open var qualityOfService: QualityOfService = .default
    open var completionBlock: (@Sendable () -> Void)?
    open var dependencies: [Operation] { _dependencies }

    public override init() {
        super.init()
        // A subclass's own report of `isFinished` reaches this too.
        _finishObservation = observe(\.isFinished) { operation, _ in
            if operation.isFinished { operation._didFinish() }
        }
    }

    open func addDependency(_ op: Operation) {
        _dependencies.append(op)
        op._dependents.append(_WeakOperation(self))
    }

    open func removeDependency(_ op: Operation) {
        _dependencies.removeAll { $0 === op }
        op._dependents.removeAll { $0.value === self || $0.value == nil }
        _queue?._schedule()
    }

    /// Runs `main()` unless cancelled, then marks the operation finished.
    open func start() {
        guard !_finished, !_executing else { return }
        if !isCancelled {
            _set(executing: true)
            main()
            _set(executing: false)
        }
        _set(finished: true)
    }

    /// The work; a subclass overrides it.
    open func main() {}

    open func cancel() {
        guard !_cancelled else { return }
        willChangeValue(forKey: "isCancelled")
        _cancelled = true
        didChangeValue(forKey: "isCancelled")
        // A cancelled operation is ready at once, whatever it waits on.
        _queue?._schedule()
    }

    /// Returns at once: blocking the page's one thread would never let the operation finish.
    open func waitUntilFinished() {}

    private func _set(executing: Bool) {
        willChangeValue(forKey: "isExecuting")
        _executing = executing
        didChangeValue(forKey: "isExecuting")
    }

    private func _set(finished: Bool) {
        willChangeValue(forKey: "isFinished")
        _finished = finished
        didChangeValue(forKey: "isFinished")
    }

    /// Runs once, when the operation first reports itself finished.
    private func _didFinish() {
        guard !_completed else { return }
        _completed = true
        completionBlock?()
        _queue?._finished(self)
        for dependent in _dependents { dependent.value?._queue?._schedule() }
        _dependents = []
    }
}

private final class _WeakOperation {
    weak var value: Operation?
    init(_ value: Operation) { self.value = value }
}

/// An operation that runs one or more blocks.
open class BlockOperation: Operation, @unchecked Sendable {
    public private(set) var executionBlocks: [@Sendable () -> Void] = []
    public override init() { super.init() }
    public convenience init(block: @escaping @Sendable () -> Void) {
        self.init()
        executionBlocks = [block]
    }
    open func addExecutionBlock(_ block: @escaping @Sendable () -> Void) { executionBlocks.append(block) }
    open override func main() { for block in executionBlocks { block() } }
}

/// A queue that runs operations as their dependencies allow, at most
/// `maxConcurrentOperationCount` at a time (an asynchronous operation counts until it finishes).
open class OperationQueue: NSObject, @unchecked Sendable {
    public static let defaultMaxConcurrentOperationCount = -1
    public static let main: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "NSOperationQueue Main Queue"
        queue.maxConcurrentOperationCount = 1
        return queue
    }()
    /// The queue running the current operation: the browser has only the main one.
    open class var current: OperationQueue? { main }

    private var _pending: [Operation] = []
    private var _running: [Operation] = []
    private var _scheduled = false
    /// The newest barrier not yet finished: operations added after it wait for it.
    private weak var _barrier: Operation?

    /// The dispatch queue operations run on.
    open var underlyingQueue: DispatchQueue? = .main
    open var maxConcurrentOperationCount = OperationQueue.defaultMaxConcurrentOperationCount {
        didSet { _schedule() }
    }
    open var name: String?
    open var qualityOfService: QualityOfService = .default
    /// While suspended, the queue starts nothing new.
    open var isSuspended = false {
        didSet { if !isSuspended { _schedule() } }
    }
    open var operations: [Operation] { _running + _pending }
    open var operationCount: Int { _running.count + _pending.count }

    public override init() { super.init() }

    open func addOperation(_ op: Operation) {
        guard op._queue == nil, !op.isFinished else { return }
        op._queue = self
        if let barrier = _barrier, barrier !== op, !barrier.isFinished { op.addDependency(barrier) }
        _pending.append(op)
        _schedule()
    }

    open func addOperations(_ ops: [Operation], waitUntilFinished wait: Bool) {
        for op in ops { addOperation(op) }
    }

    /// Runs the block later on the main queue: the page has one thread.
    open func addOperation(_ block: @escaping @Sendable () -> Void) {
        addOperation(BlockOperation(block: block))
    }

    /// Runs the block once every operation added before it has finished. Operations added
    /// after it wait until it has run.
    open func addBarrierBlock(_ barrier: @escaping @Sendable () -> Void) {
        let op = BlockOperation(block: barrier)
        for earlier in operations { op.addDependency(earlier) }
        addOperation(op)
        _barrier = op
    }

    open func cancelAllOperations() {
        for op in operations { op.cancel() }
    }

    /// Returns at once: blocking the page's one thread would never let the operations run.
    open func waitUntilAllOperationsAreFinished() {}

    /// Starts what can start on the queue's next turn.
    func _schedule() {
        guard !_scheduled else { return }
        _scheduled = true
        (underlyingQueue ?? .main).async { [self] in
            _scheduled = false
            _drain()
        }
    }

    func _finished(_ op: Operation) {
        _running.removeAll { $0 === op }
        _pending.removeAll { $0 === op }
        op._queue = nil
        _schedule()
    }

    private func _drain() {
        while !isSuspended, maxConcurrentOperationCount < 0 || _running.count < maxConcurrentOperationCount {
            // The ready operation of highest priority, the earliest added among equals.
            var best: Int?
            for (index, op) in _pending.enumerated() where op.isReady || op.isCancelled {
                if best == nil || op.queuePriority.rawValue > _pending[best!].queuePriority.rawValue { best = index }
            }
            guard let index = best else { return }
            let op = _pending.remove(at: index)
            _running.append(op)
            op.start()
        }
    }
}

#endif
