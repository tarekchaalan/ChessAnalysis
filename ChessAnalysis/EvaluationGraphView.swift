import SwiftUI

struct EvaluationGraphView: View {
    let evals: [Int]

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let clamped = evals.isEmpty ? [0] : evals
            let maxEval = 600
            let stepX = width / max(CGFloat(clamped.count - 1), 1)
            let centerY = height / 2

            ZStack {
                Path { path in
                    path.move(to: CGPoint(x: 0, y: centerY))
                    path.addLine(to: CGPoint(x: width, y: centerY))
                }
                .stroke(Color.white.opacity(0.2), lineWidth: 1)

                let points = clamped.indices.map { index -> CGPoint in
                    let eval = min(max(clamped[index], -maxEval), maxEval)
                    let y = centerY - (CGFloat(eval) / CGFloat(maxEval)) * (centerY - 4)
                    let x = CGFloat(index) * stepX
                    return CGPoint(x: x, y: y)
                }

                Path { path in
                    addSmoothedPath(points: points, to: &path)
                    path.addLine(to: CGPoint(x: width, y: height))
                    path.addLine(to: CGPoint(x: 0, y: height))
                    path.closeSubpath()
                }
                .fill(Color.white.opacity(0.25))

                Path { path in
                    addSmoothedPath(points: points, to: &path)
                }
                .stroke(Color.white, lineWidth: 2)
            }
        }
        .frame(height: 120)
        .background(Color.black.opacity(0.25))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func addSmoothedPath(points: [CGPoint], to path: inout Path) {
        guard !points.isEmpty else { return }
        if points.count == 1 {
            path.move(to: points[0])
            return
        }
        path.move(to: points[0])
        for index in 1..<points.count {
            let prev = points[index - 1]
            let current = points[index]
            let mid = CGPoint(x: (prev.x + current.x) / 2, y: (prev.y + current.y) / 2)
            path.addQuadCurve(to: mid, control: prev)
            if index == points.count - 1 {
                path.addQuadCurve(to: current, control: mid)
            }
        }
    }
}
