import SwiftUI

func classificationAssetName(_ classification: String) -> String? {
    switch classification.lowercased() {
    case "best": return "best"
    case "good": return "good"
    case "inaccuracy": return "inaccuracy"
    case "mistake": return "mistake"
    case "blunder": return "blunder"
    case "great": return "great"
    case "brilliant": return "brilliant"
    case "excellent": return "excellent"
    case "book": return "book"
    case "miss": return "miss"
    default: return nil
    }
}

func classificationColor(_ classification: String) -> Color {
    switch classification.lowercased() {
    case "brilliant": return Color(red: 0.2, green: 0.78, blue: 0.72)
    case "great": return Color(red: 0.43, green: 0.62, blue: 0.87)
    case "best": return Color(red: 0.49, green: 0.74, blue: 0.33)
    case "excellent": return Color(red: 0.56, green: 0.78, blue: 0.4)
    case "good": return Color(red: 0.65, green: 0.8, blue: 0.47)
    case "book": return Color(red: 0.71, green: 0.52, blue: 0.36)
    case "inaccuracy": return Color(red: 0.96, green: 0.78, blue: 0.27)
    case "mistake": return Color(red: 0.96, green: 0.6, blue: 0.26)
    case "miss": return Color(red: 0.92, green: 0.36, blue: 0.39)
    case "blunder": return Color(red: 0.86, green: 0.2, blue: 0.2)
    case "mateline": return Color(red: 0.98, green: 0.85, blue: 0.37)
    default: return Color(red: 0.98, green: 0.85, blue: 0.37) // Default to yellow
    }
}

func classificationHighlightColor(_ classification: String) -> Color {
    classificationColor(classification).opacity(0.35)
}
