import SwiftUI

struct EvalBarView: View {
    let evalCp: Int
    let overrideText: String?
    let winnerColor: PieceColor?
    let forceWinnerFill: Bool

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let clamped = min(max(evalCp, -1000), 1000)
            let percent: Double = {
                if forceWinnerFill, let winnerColor {
                    return winnerColor == .white ? 1.0 : 0.0
                }
                return (Double(clamped) + 1000) / 2000
            }()
            let filledWidth = width * CGFloat(percent)

            ZStack {
                RoundedRectangle(cornerRadius: height / 2)
                    .fill(Color.black.opacity(0.6))
                RoundedRectangle(cornerRadius: height / 2)
                    .fill(Color.white.opacity(0.85))
                    .frame(width: filledWidth)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .animation(.easeInOut(duration: 0.25), value: filledWidth)
            }
            .overlay(
                Text(overrideText ?? formattedEval())
                    .font(.headline)
                    .foregroundColor(.white)
                    .blendMode(.difference)
            )
        }
        .frame(height: 32)
    }

    private func formattedEval() -> String {
        let mateBase = 100000
        if abs(evalCp) >= mateBase {
            let mateIn = abs(evalCp) - mateBase
            let prefix = evalCp >= 0 ? "M" : "-M"
            return "\(prefix)\(mateIn)"
        }
        let value = Double(evalCp) / 100.0
        let sign = value >= 0 ? "+" : ""
        return "\(sign)\(String(format: "%.1f", value))"
    }
}
