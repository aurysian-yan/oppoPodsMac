#if os(macOS)
import Foundation

/// 专用的蓝牙运行循环线程。
///
/// 背景：`IOBluetooth` 的 RFCOMM 回调（`rfcommChannelOpenComplete` / `rfcommChannelClosed` /
/// `rfcommChannelData`）会被投递到“发起异步调用的那个线程的 run loop”，并且只有当该 run loop
/// 正在运行、且持续服务 IOBluetooth 注册的 source 时回调才会触发。
///
/// 问题：`OppoProtocolBackend` 是 `actor`，其方法跑在 Swift 并发的协作线程池（cooperative pool）上。
/// 这些线程的 run loop 不会服务 IOBluetooth 的 source，于是 `openRFCOMMChannelAsync` 之后无论怎么
/// `RunLoop.current.run(...)` 自旋，open/close 回调都不会到来 → 每次尝试都要等满 open/close 超时
/// （日志里的 `open timeout` / `channel closed timeout`），表现为“连得很慢且经常连不上”。
///
/// 解决：用一个常驻、持续运行 run loop 的专用线程承载所有 IOBluetooth 操作。由于
/// `openRFCOMMChannelAsync` 在该线程上调用，IOBluetooth 会把 source 注册到该线程的 run loop，
/// 而该 run loop 一直在运行，回调便能可靠送达。
final class BluetoothRunLoopThread {
    static let shared = BluetoothRunLoopThread()

    private let thread: Thread
    private var runLoop: CFRunLoop!
    private let ready = DispatchSemaphore(value: 0)

    private init() {
        let ready = self.ready
        var capturedRunLoop: CFRunLoop?

        thread = Thread {
            let runLoop = RunLoop.current
            // 挂一个常驻 mach port，避免 run loop 因没有任何 source 而立即返回（空转）。
            runLoop.add(NSMachPort(), forMode: .common)
            capturedRunLoop = CFRunLoopGetCurrent()
            // run loop 已就绪，唤醒等待的初始化方。capturedRunLoop 的写-读通过信号量建立 happens-before。
            ready.signal()

            while !Thread.current.isCancelled {
                // 阻塞直到有输入源被唤醒；处理完后回到循环继续等待。
                runLoop.run(mode: .default, before: .distantFuture)
            }
        }
        thread.name = "top.aurysian.auribuds.bluetooth"
        thread.qualityOfService = .userInitiated
        thread.start()

        ready.wait()
        runLoop = capturedRunLoop
    }

    /// 在蓝牙线程上同步执行闭包并返回结果。若已在蓝牙线程上则直接执行（支持重入）。
    func sync<T>(_ work: @escaping () -> T) -> T {
        if Thread.current === thread {
            return work()
        }

        var result: T?
        let done = DispatchSemaphore(value: 0)
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.defaultMode.rawValue) {
            result = work()
            done.signal()
        }
        CFRunLoopWakeUp(runLoop)
        done.wait()
        return result!
    }

    /// 在蓝牙线程上同步执行可抛出闭包。
    func syncThrowing<T>(_ work: @escaping () throws -> T) throws -> T {
        try sync { Result(catching: work) }.get()
    }
}
#endif
