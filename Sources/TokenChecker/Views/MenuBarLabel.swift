import SwiftUI
import AppKit

/// メニューバーに表示する「Claude + 各 Codex アカウントのドーナツ」。
///
/// SwiftUI ビューを `ImageRenderer` で NSImage に焼いて、
/// `Image(nsImage:)` でメニューバーに渡す。
/// `MenuBarExtra` の label に SwiftUI ビューを直接渡すとフォント等が制限されるため。
struct MenuBarLabel: View {
    let viewModel: UsageViewModel

    var body: some View {
        if let image = renderedImage {
            Image(nsImage: image)
        } else {
            Text("TC ⏳")
        }
    }

    private var renderedImage: NSImage? {
        let showClaude = viewModel.isVisibleInMenuBar("claude")
        let visibleCodex = viewModel.snapshot.codexAccounts.filter {
            viewModel.isVisibleInMenuBar($0.label)
        }

        let content = HStack(spacing: 6) {
            if showClaude {
                let claude = utilization(from: viewModel.snapshot.claude)
                HStack(spacing: 3) {
                    DonutChartView(
                        value: claude ?? 0,
                        size: 20,
                        lineWidth: 3,
                        center: .sfSymbol("sparkles", scale: 0.48)
                    )
                    Text(percentLabel(claude))
                        .font(.system(size: 11, weight: .semibold))
                }
            }

            ForEach(visibleCodex, id: \.label) { account in
                let value: Double? = {
                    guard case .success(let usage) = account.result else { return nil }
                    return usage.fiveHour?.utilization
                }()
                HStack(spacing: 3) {
                    DonutChartView(
                        value: value ?? 0,
                        size: 20,
                        lineWidth: 3,
                        center: .sfSymbol("terminal.fill", scale: 0.48)
                    )
                    Text(percentLabel(value))
                        .font(.system(size: 11, weight: .semibold))
                }
            }
        }
        .padding(.horizontal, 2)
        .foregroundStyle(Color.primary)

        let renderer = ImageRenderer(content: content)
        let maxScale = NSScreen.screens.map(\.backingScaleFactor).max() ?? 2
        renderer.scale = max(maxScale, 3)
        guard let image = renderer.nsImage else { return nil }
        image.isTemplate = false
        return image
    }

    private func utilization(from result: Result<ServiceUsage, DomainError>?) -> Double? {
        guard case .success(let usage) = result else { return nil }
        return usage.fiveHour?.utilization
    }

    private func percentLabel(_ value: Double?) -> String {
        guard let v = value else { return "--%" }
        if v > 1.0 { return "100%+" }
        let clamped = max(0, v)
        return "\(Int((clamped * 100).rounded()))%"
    }
}
