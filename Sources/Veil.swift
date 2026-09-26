import AppKit
import QuartzCore

/// Private WindowServer call that gives a transparent window a live backdrop blur of any radius.
/// Resolved at runtime; if it's ever missing we fall back to NSVisualEffectView.
enum SkyLight {
    private typealias MainConnection = @convention(c) () -> UInt32
    private typealias SetBlurRadius = @convention(c) (UInt32, UInt32, Int32) -> Int32
    private static let connection: MainConnection? = symbol("CGSMainConnectionID")
    private static let setBlurRadius: SetBlurRadius? = symbol("CGSSetWindowBackgroundBlurRadius")

    static var available: Bool { connection != nil && setBlurRadius != nil }

    static func blur(_ window: NSWindow, radius: Int) {
        guard let connection, let setBlurRadius else { return }
        _ = setBlurRadius(connection(), UInt32(window.windowNumber), Int32(radius))
    }

    private static func symbol<T>(_ name: String) -> T? {
        dlsym(UnsafeMutableRawPointer(bitPattern: -2), name).map { unsafeBitCast($0, to: T.self) }
    }
}

/// Core Animation's backdrop layer: samples whatever lies behind the window and runs filters on it,
/// composited by the WindowServer. Private, so it's resolved at runtime.
enum Backdrop {
    static let layerClass = NSClassFromString("CABackdropLayer") as? CALayer.Type
    private static let filterClass = NSClassFromString("CAFilter") as? NSObject.Type
    static var available: Bool { layerClass != nil && filterClass != nil }

    static func filter(_ type: String, name: String) -> NSObject? {
        let f = filterClass?.perform(NSSelectorFromString("filterWithType:"), with: type)?.takeUnretainedValue() as? NSObject
        f?.setValue(name, forKey: "name")
        return f
    }
}

/// A click-through pane that blurs and restyles everything behind it. Full-screen ones sit beneath the
/// focused window; a window-sized one blurs a single window in or out during transitions.
final class Veil: NSWindow {
    static let duration = 0.3

    private let backdrop: CALayer?
    private var link: CADisplayLink?
    private var animation: (from: CGFloat, to: CGFloat, start: CFTimeInterval, span: Double, done: (() -> Void)?)?
    private var radius: CGFloat = 0
    private var tint: CGFloat = 0
    private(set) var progress: CGFloat = 0

    init(frame: NSRect) {
        backdrop = Backdrop.layerClass?.init()
        super.init(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        animationBehavior = .none
        level = .normal
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]

        let view = NSView(frame: NSRect(origin: .zero, size: frame.size))
        view.autoresizingMask = [.width, .height]
        view.wantsLayer = true
        if let l = backdrop {
            l.frame = view.bounds
            l.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
            view.layer?.addSublayer(l)
        }
        backdrop?.setValue(true, forKey: "windowServerAware")
        backdrop?.filters = Veil.filters()
        setUpMask()
        contentView = view
    }

    /// A window region the veil should leave sharp, or fade between sharp and blurred.
    struct Region {
        let id: CGWindowID
        let path: CGPath        // global CoreGraphics coordinates (top-left origin)
        let blurred: Bool
        let wasSharp: Bool
    }

    private let maskRoot = CALayer()
    private let base = CAShapeLayer()
    private var holes: [CGWindowID: CAShapeLayer] = [:]
    private var holeBlurred: [CGWindowID: Bool] = [:]

    private func setUpMask() {
        guard let backdrop else { return }
        maskRoot.frame = backdrop.bounds
        base.frame = maskRoot.bounds
        base.fillColor = NSColor.black.cgColor
        base.path = CGPath(rect: maskRoot.bounds, transform: nil)
        maskRoot.addSublayer(base)
        backdrop.mask = maskRoot
    }

    /// Cuts sharp holes into the blur where `regions` say so, fading holes open and closed.
    func setRegions(_ regions: [Region]) {
        guard backdrop != nil else { return }
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        var toLocal = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: -frame.minX, ty: top - frame.minY)
        let bounds = maskRoot.bounds
        var seen = Set<CGWindowID>()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for r in regions {
            guard let p = r.path.copy(using: &toLocal), p.boundingBoxOfPath.intersects(bounds) else { continue }
            seen.insert(r.id)
            if let l = holes[r.id] {
                l.path = p
                if holeBlurred[r.id] != r.blurred { fade(r.id, to: r.blurred) }
            } else if !(r.blurred && !r.wasSharp) {
                // Start from how the window looked a moment ago, then ease to how it should look.
                let l = CAShapeLayer()
                l.frame = bounds
                l.fillColor = NSColor.black.cgColor
                l.path = p
                l.opacity = r.wasSharp ? 0 : 1
                maskRoot.addSublayer(l)
                holes[r.id] = l
                holeBlurred[r.id] = !r.wasSharp
                if r.blurred != !r.wasSharp { fade(r.id, to: r.blurred) }
            }
        }
        for id in holes.keys where !seen.contains(id) { dropHole(id) }
        updateBase()
        CATransaction.commit()
    }

    func clearRegions() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for id in holes.keys { dropHole(id) }
        updateBase()
        CATransaction.commit()
    }

    /// Whether `id`'s hole is fully open and done fading; nil if this veil has no hole for it.
    func sharpness(of id: CGWindowID) -> Bool? {
        guard let l = holes[id] else { return nil }
        return holeBlurred[id] == false && l.animation(forKey: "fade") == nil
    }

    private func fade(_ id: CGWindowID, to blurred: Bool) {
        guard let l = holes[id] else { return }
        let from = l.presentation()?.opacity ?? l.opacity
        let to: Float = blurred ? 1 : 0
        holeBlurred[id] = blurred
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            // A fully blurred hole is just more veil — fold it back in.
            guard let self, self.holeBlurred[id] == true, self.holes[id] === l, l.animation(forKey: "fade") == nil else { return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            self.dropHole(id)
            self.updateBase()
            CATransaction.commit()
        }
        let anim = CABasicAnimation(keyPath: "opacity")
        anim.fromValue = from
        anim.toValue = to
        anim.duration = Veil.duration * Double(max(0.3, abs(to - from)))
        anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        l.opacity = to
        l.add(anim, forKey: "fade")
        CATransaction.commit()
    }

    private func dropHole(_ id: CGWindowID) {
        holes.removeValue(forKey: id)?.removeFromSuperlayer()
        holeBlurred[id] = nil
    }

    private func updateBase() {
        let full = CGPath(rect: maskRoot.bounds, transform: nil)
        guard !holes.isEmpty else { base.path = full; return }
        var cut = CGMutablePath() as CGPath
        for l in holes.values { if let p = l.path { cut = cut.union(p) } }
        base.path = full.subtracting(cut)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Slider positions are perceptual: small moves near zero stay subtle.
    func configure(blur: Double, tint: Double) {
        radius = 22 * pow(blur, 1.7)
        self.tint = 0.7 * pow(tint, 1.3)
        render()
    }

    private static func filters() -> [NSObject] {
        let blur = Backdrop.filter("gaussianBlur", name: "blur")
        blur?.setValue(true, forKey: "inputNormalizeEdges") // keep full strength right up to the screen edges
        let tint = Backdrop.filter("colorMonochrome", name: "tint")
        tint?.setValue(NSColor.controlAccentColor.usingColorSpace(.sRGB)?.cgColor, forKey: "inputColor")
        return [blur, tint].compactMap { $0 }
    }

    /// Eases the effect toward `target`, in step with the display's refresh.
    /// A newer call supersedes an unfinished one (its completion never runs).
    func animate(to target: CGFloat, duration: Double = Veil.duration, completion: (() -> Void)? = nil) {
        halt()
        guard duration > 0, abs(target - progress) > 0.001 else {
            progress = target; render(); completion?(); return
        }
        animation = (progress, target, CACurrentMediaTime(), duration * Double(abs(target - progress)), completion)
        let l = displayLink(target: self, selector: #selector(step))
        l.add(to: .main, forMode: .common)
        link = l
    }

    func halt() {
        link?.invalidate()
        link = nil
        animation = nil
    }

    @objc private func step(_ link: CADisplayLink) {
        guard let a = animation else { return halt() }
        let x = min(1, (CACurrentMediaTime() - a.start) / a.span)
        let eased = 0.5 - cos(x * .pi) / 2 // sine ease-in-out: no hard start, no hard stop
        progress = a.from + (a.to - a.from) * CGFloat(eased)
        render()
        if x >= 1 {
            halt()
            a.done?()
        }
    }

    private func render() {
        let p = progress
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if let backdrop {
            backdrop.setValue(radius * p, forKeyPath: "filters.blur.inputRadius")
            backdrop.setValue(tint * p, forKeyPath: "filters.tint.inputAmount")
        } else {
            SkyLight.blur(self, radius: Int((radius * p).rounded()))
        }
        CATransaction.commit()
    }
}
