import AppKit

struct Win {
    let id: CGWindowID
    let pid: pid_t
    let layer: Int
    let bounds: CGRect
    let alpha: Double
}

/// Keeps every window of the active app sharp and everything else blurred.
///
/// One full-screen veil sits directly beneath the active app's frontmost window, so that window is
/// never touched — not even while you drag it. The app's other windows further down show through
/// sharp holes cut into the veil. When the active app changes, holes simply fade open or closed.
final class FocusController {
    private let settings: Settings
    private var veils: [Veil] = []                  // one per screen
    private var running = false
    private var shown = false
    private var activePID: pid_t = 0
    private var sharpIDs: Set<CGWindowID> = []      // what looked sharp on the last pass
    private var handoffPID: pid_t?                  // app we're about to focus after a close
    private var handoffDeadline: Date = .distantPast
    private var poll: Timer?
    private var lastFocus: Win?                     // front window on the last normal pass
    private var desktopFrom: Win?                   // where you were before clicking the desktop
    private var windowsMovedAway = false
    private var pendingHandoff: DispatchWorkItem?
    private let me = ProcessInfo.processInfo.processIdentifier
    private var observers: [NSObjectProtocol] = []

    init(settings: Settings) {
        self.settings = settings
        let ws = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.activeSpaceDidChangeNotification,
                     NSWorkspace.didTerminateApplicationNotification, NSWorkspace.didHideApplicationNotification] {
            observers.append(ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.refresh() })
        }
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.rebuild() })
    }

    func apply() {
        if settings.enabled && !running { start() }
        if !settings.enabled && running { stop() }
        for v in veils { v.configure(blur: settings.blur, tint: settings.tint) }
    }

    // MARK: Lifecycle

    private func start() {
        running = true
        rebuild()
        let t = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in self?.refresh() }
        RunLoop.main.add(t, forMode: .common)
        poll = t
    }

    private func stop() {
        running = false
        poll?.invalidate(); poll = nil
        clear()
    }

    private func rebuild() {
        for v in veils { v.halt(); v.orderOut(nil) }
        veils = NSScreen.screens.map { s in
            let v = Veil(frame: s.frame)
            v.configure(blur: settings.blur, tint: settings.tint)
            return v
        }
        shown = false
        refresh()
    }

    private func clear() {
        pendingHandoff?.cancel(); pendingHandoff = nil
        handoffPID = nil
        shown = false
        sharpIDs = []
        activePID = 0
        for v in veils where v.isVisible {
            v.animate(to: 0) { v.clearRegions(); v.orderOut(nil) }
        }
    }

    // MARK: Tracking

    func refresh() {
        guard running, let front = NSWorkspace.shared.frontmostApplication?.processIdentifier, front != me else { return }
        let all = Self.windows()
        let candidates = all.filter(isCandidate)

        if let h = handoffPID, front == h || Date() > handoffDeadline { handoffPID = nil }
        let active = handoffPID ?? front

        let closedLast = !candidates.contains(where: { $0.pid == active })
            && !sharpIDs.isEmpty && !all.contains(where: { sharpIDs.contains($0.id) })
        // You clicked the desktop: get out of the way until you pick a window again.
        if handoffPID == nil, !closedLast,
           NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder",
           candidates.first?.pid != front {
            if shown {
                desktopFrom = lastFocus
                windowsMovedAway = false
                clear()
            } else if let from = desktopFrom, let w = all.first(where: { $0.id == from.id }) {
                // macOS slides windows aside on the first wallpaper click and back on the second.
                // Once they're home again, give focus back to where you were.
                let home = abs(w.bounds.minX - from.bounds.minX) < 2 && abs(w.bounds.minY - from.bounds.minY) < 2
                if !home {
                    windowsMovedAway = true
                } else if windowsMovedAway {
                    desktopFrom = nil
                    activate(from)
                }
            }
            return
        }
        desktopFrom = nil
        // No windows on screen at all: there's nothing to focus, so show the desktop as it is.
        guard let top = candidates.first else {
            if shown { clear() }
            return
        }
        guard candidates.contains(where: { $0.pid == active }) else { return nothingFocused(all) }
        // The active app's windows are buried under others (e.g. you clicked the desktop): hold still.
        guard top.pid == active else { return }
        pendingHandoff?.cancel(); pendingHandoff = nil
        activePID = active
        lastFocus = top

        let veilIDs = Set(veils.map { CGWindowID($0.windowNumber) })
        let veilIndex = all.firstIndex(where: { veilIDs.contains($0.id) }) ?? all.count
        let topIndex = all.firstIndex(where: { $0.id == top.id }) ?? 0

        let wasAbove = Set(all[..<veilIndex].map(\.id))
        var topAbove = topIndex < veilIndex
        if !shown {
            seat(below: top)
            topAbove = true
            shown = true
            for v in veils { v.animate(to: 1) }
        } else if topAbove {
            // Keep the veil directly beneath the front window. Anything it slides over was sharp,
            // so its hole starts open and eases shut.
            let between = all[(topIndex + 1)..<veilIndex].contains { !veilIDs.contains($0.id) && isCandidate($0) }
            if between { seat(below: top) }
        } else if isFullySharp(top.id) {
            // The front window has been showing through a hole (after a close). Now that it's fully
            // sharp, move the veil beneath it for good and hand it focus.
            seat(below: top)
            topAbove = true
            if handoffPID != nil { activate(top) }
        }

        // Everything except a front window above the veil lies under it. Work out what of each is
        // visible and whether it belongs sharp (active app) or blurred (everyone else).
        var covered = CGMutablePath() as CGPath
        var regions: [Veil.Region] = []
        var nowSharp: Set<CGWindowID> = topAbove ? [top.id] : []
        for w in candidates where !(topAbove && w.id == top.id) {
            let shape = CGPath(roundedRect: w.bounds, cornerWidth: 14, cornerHeight: 14, transform: nil)
            let visible = covered.isEmpty ? shape : shape.subtracting(covered)
            let sharp = w.pid == active
            if sharp { nowSharp.insert(w.id) }
            regions.append(Veil.Region(id: w.id, path: visible, blurred: !sharp,
                                       wasSharp: sharpIDs.contains(w.id) || wasAbove.contains(w.id)))
            covered = covered.union(shape)
        }
        for v in veils { v.setRegions(regions) }
        sharpIDs = nowSharp
    }

    /// The active app shows no windows. If the ones we kept sharp are still on screen (Spotlight,
    /// a menu…), hold still; if they were closed or minimized, hand focus to whatever is beneath.
    private func nothingFocused(_ all: [Win]) {
        guard handoffPID == nil, pendingHandoff == nil, !sharpIDs.isEmpty,
              !all.contains(where: { sharpIDs.contains($0.id) }) else { return }
        let work = DispatchWorkItem { [weak self] in self?.handOff() }
        pendingHandoff = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
    }

    private func handOff() {
        pendingHandoff = nil
        guard running else { return }
        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let candidates = Self.windows().filter(isCandidate)
        if candidates.contains(where: { $0.pid == front }) { return refresh() }
        guard settings.focusBeneath, let next = candidates.first else { return clear() }
        // Treat the app beneath as active right away so its windows fade sharp under the veil;
        // refresh() activates it once the fade has settled.
        handoffPID = next.pid
        handoffDeadline = Date().addingTimeInterval(2)
        refresh()
    }

    // MARK: Helpers

    private func isFullySharp(_ id: CGWindowID) -> Bool {
        let states = veils.compactMap { $0.sharpness(of: id) }
        return !states.isEmpty && states.allSatisfy { $0 }
    }

    private func seat(below w: Win) {
        for v in veils { v.order(.below, relativeTo: Int(w.id)) }
    }

    private func isCandidate(_ w: Win) -> Bool {
        w.layer == 0 && w.pid != me && w.alpha > 0.01 && w.bounds.width >= 80 && w.bounds.height >= 60
    }

    /// Brings exactly that window to the front with keyboard focus. No Accessibility permission needed.
    private func activate(_ w: Win) {
        if !WindowFocus.focus(w.id, pid: w.pid) {
            NSRunningApplication(processIdentifier: w.pid)?.activate()
        }
    }

    /// On-screen windows, front to back.
    static func windows() -> [Win] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return [] }
        return list.compactMap { d in
            guard let id = d[kCGWindowNumber as String] as? CGWindowID,
                  let pid = d[kCGWindowOwnerPID as String] as? pid_t,
                  let layer = d[kCGWindowLayer as String] as? Int else { return nil }
            let bounds = (d[kCGWindowBounds as String] as? NSDictionary)
                .flatMap { CGRect(dictionaryRepresentation: $0 as CFDictionary) } ?? .zero
            return Win(id: id, pid: pid, layer: layer, bounds: bounds, alpha: d[kCGWindowAlpha as String] as? Double ?? 1)
        }
    }
}
