import AppKit

/// Focuses a specific window of another app the way the window server does for a user click,
/// using the same private SkyLight calls as window switchers like AltTab. Background apps can't
/// reliably do this with public API on current macOS, and this needs no Accessibility permission.
enum WindowFocus {
    private typealias SetFront = @convention(c) (UnsafeMutablePointer<ProcessSerialNumber>, CGWindowID, UInt32) -> CGError
    private typealias PostEvent = @convention(c) (UnsafeMutablePointer<ProcessSerialNumber>, UnsafeMutablePointer<UInt8>) -> CGError
    private typealias GetPSN = @convention(c) (pid_t, UnsafeMutablePointer<ProcessSerialNumber>) -> OSStatus

    private static let setFront: SetFront? = symbol("_SLPSSetFrontProcessWithOptions")
    private static let postEvent: PostEvent? = symbol("SLPSPostEventRecordTo")
    private static let getPSN: GetPSN? = symbol("GetProcessForPID")

    @discardableResult
    static func focus(_ window: CGWindowID, pid: pid_t) -> Bool {
        guard let setFront, let postEvent, let getPSN else { return false }
        var psn = ProcessSerialNumber()
        guard getPSN(pid, &psn) == noErr else { return false }
        guard setFront(&psn, window, 0x200 /* kCPSUserGenerated */) == .success else { return false }
        // Make it the key window: a synthetic "window activated" event pair.
        var bytes = [UInt8](repeating: 0, count: 0xf8)
        bytes[0x04] = 0xf8
        bytes[0x3a] = 0x10
        withUnsafeBytes(of: window) { for (i, b) in $0.enumerated() { bytes[0x3c + i] = b } }
        for i in 0x20..<0x30 { bytes[i] = 0xff }
        bytes[0x08] = 0x01
        _ = postEvent(&psn, &bytes)
        bytes[0x08] = 0x02
        _ = postEvent(&psn, &bytes)
        return true
    }

    private static func symbol<T>(_ name: String) -> T? {
        dlsym(UnsafeMutableRawPointer(bitPattern: -2), name).map { unsafeBitCast($0, to: T.self) }
    }
}
