import SwiftUI

struct BoardThemePickerView: View {
    @AppStorage("board.theme") private var selectedId = BoardTheme.defaultId

    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(BoardTheme.themes) { theme in
                    Button {
                        selectedId = theme.id
                    } label: {
                        BoardThemePreview(
                            light: theme.lightColor,
                            dark: theme.darkColor,
                            isSelected: theme.id == selectedId
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
        }
        .navigationTitle("Board Theme")
    }
}

private struct BoardThemePreview: View {
    let light: Color
    let dark: Color
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        lightSquare
                        darkSquare
                        lightSquare
                    }
                    HStack(spacing: 0) {
                        darkSquare
                        lightSquare
                        darkSquare
                    }
                    HStack(spacing: 0) {
                        lightSquare
                        darkSquare
                        lightSquare
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
                )

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.blue)
                        .background(Color.white.opacity(0.9))
                        .clipShape(Circle())
                        .offset(x: 6, y: -6)
                }
            }
        }
    }

    private var lightSquare: some View {
        Rectangle()
            .fill(light)
            .frame(width: 32, height: 32)
    }

    private var darkSquare: some View {
        Rectangle()
            .fill(dark)
            .frame(width: 32, height: 32)
    }
}
