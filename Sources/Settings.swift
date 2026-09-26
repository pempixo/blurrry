import Foundation

final class Settings: ObservableObject {
    static let shared = Settings()
    private let d = UserDefaults.standard
    var onChange: (() -> Void)?

    @Published var enabled: Bool { didSet { d.set(enabled, forKey: "enabled"); onChange?() } }
    @Published var blur: Double { didSet { d.set(blur, forKey: "strength"); onChange?() } }
    @Published var tint: Double { didSet { d.set(tint, forKey: "tintAmount"); onChange?() } }
    @Published var focusBeneath: Bool { didSet { d.set(focusBeneath, forKey: "focusBeneath"); onChange?() } }

    private init() {
        d.register(defaults: ["enabled": true, "strength": 0.5, "focusBeneath": true, "tintAmount": 0.0])
        enabled = d.bool(forKey: "enabled")
        blur = min(1, max(0, d.double(forKey: "strength")))
        tint = min(1, max(0, d.double(forKey: "tintAmount")))
        focusBeneath = d.bool(forKey: "focusBeneath")
    }
}
