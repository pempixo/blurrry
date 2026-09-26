import SwiftUI
import ServiceManagement

struct Panel: View {
    @ObservedObject var settings: Settings
    @State private var openAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("blurrry").font(.system(size: 13, weight: .semibold))
                Spacer()
                Toggle("", isOn: $settings.enabled.animation(.smooth)).toggleStyle(.switch).labelsHidden().controlSize(.mini)
            }

            VStack(spacing: 8) {
                Row(title: "Blur", value: $settings.blur, label: "\(Int(settings.blur * 100))%")
                Row(title: "Tint", value: $settings.tint, label: "\(Int(settings.tint * 100))%")
            }
            .opacity(settings.enabled ? 1 : 0.4)
            .disabled(!settings.enabled)

            Divider().opacity(0.5)

            VStack(alignment: .leading, spacing: 6) {
                Toggle("Focus the window beneath on close", isOn: $settings.focusBeneath)
                Toggle("Open at login", isOn: $openAtLogin)
                    .onChange(of: openAtLogin) { _, on in
                        try? on ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
                        openAtLogin = SMAppService.mainApp.status == .enabled
                    }
            }
            .toggleStyle(.checkbox)
            .font(.system(size: 12))
        }
        .padding(14)
        .frame(width: 260)
    }
}

private struct Row: View {
    let title: String
    @Binding var value: Double
    let label: String

    var body: some View {
        HStack(spacing: 8) {
            Text(title).frame(width: 30, alignment: .leading)
            Slider(value: $value, in: 0...1).controlSize(.mini)
            Text(label).monospacedDigit().foregroundStyle(.secondary).frame(width: 34, alignment: .trailing)
        }
        .font(.system(size: 12))
    }
}
