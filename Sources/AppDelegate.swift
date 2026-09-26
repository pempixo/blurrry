import AppKit
import SwiftUI
import Carbon

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let settings = Settings.shared
    private var controller: FocusController!
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var hotKey: HotKey?

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller = FocusController(settings: settings)
        settings.onChange = { [weak self] in self?.settingsChanged() }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusClicked)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])

        let host = NSHostingController(rootView: Panel(settings: settings))
        host.sizingOptions = .preferredContentSize
        popover.contentViewController = host
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self

        hotKey = HotKey(keyCode: kVK_ANSI_B, modifiers: controlKey | optionKey | cmdKey) { [weak self] in
            self?.settings.enabled.toggle()
        }

        // Launch quietly into the menu bar. blurrry needs no permissions at all.
        settingsChanged()
    }

    private func settingsChanged() {
        controller.apply()
        statusItem.button?.image = Self.icon
        statusItem.button?.appearsDisabled = !settings.enabled
    }

    /// A sharp dot in a soft glow — focus, with everything around it blurred away.
    private static let icon: NSImage = {
        let image = NSImage(size: NSSize(width: 22, height: 22), flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext,
                  let glow = CGGradient(colorsSpace: nil,
                                        colors: [NSColor.black.withAlphaComponent(0.8).cgColor,
                                                 NSColor.black.withAlphaComponent(0).cgColor] as CFArray,
                                        locations: [0.3, 1]) else { return false }
            let c = CGPoint(x: 11, y: 11)
            ctx.drawRadialGradient(glow, startCenter: c, startRadius: 0, endCenter: c, endRadius: 11, options: [])
            NSColor.black.setFill()
            NSBezierPath(ovalIn: NSRect(x: 7, y: 7, width: 8, height: 8)).fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "blurrry"
        return image
    }()

    @objc private func statusClicked() {
        guard NSApp.currentEvent?.type == .rightMouseUp else { return togglePopover() }
        let menu = NSMenu()
        menu.addItem(withTitle: "Quit blurrry", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else if let button = statusItem.button {
            NSApp.activate()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            // A plain activate() from a menu bar app is often ignored, which leaves the panel
            // greyed out until clicked. Focus its window directly, like a click would.
            focusPanel()
        }
    }

    func popoverDidShow(_ notification: Notification) {
        focusPanel()
    }

    /// A plain activate() from a menu bar app is often ignored, which leaves the panel greyed out
    /// until clicked. Focus its window directly, the way a click would.
    private func focusPanel() {
        guard let window = popover.contentViewController?.view.window else { return }
        NSApp.activate(ignoringOtherApps: true)
        WindowFocus.focus(CGWindowID(window.windowNumber), pid: getpid())
        window.makeKeyAndOrderFront(nil)
    }

    func popoverDidClose(_ notification: Notification) {
        // Hand focus straight back to whatever you were working in.
        if NSApp.isActive { NSApp.hide(nil) }
    }
}
