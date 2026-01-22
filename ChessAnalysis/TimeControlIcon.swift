import SwiftUI

enum TimeControlCategory: String {
    case bullet
    case blitz
    case rapid
}

struct TimeControlIcon: View {
    let timeClass: String?
    let timeControl: String?

    var body: some View {
        if let category = timeControlCategory(timeClass: timeClass, timeControl: timeControl) {
            Image(category.rawValue)
                .resizable()
                .renderingMode(.original)
                .scaledToFit()
                .frame(width: 22, height: 22)
                .accessibilityLabel(Text(category.rawValue.capitalized))
        }
    }
}

func timeControlCategory(timeClass: String?, timeControl: String?) -> TimeControlCategory? {
    if let timeClass {
        switch timeClass.lowercased() {
        case "bullet": return .bullet
        case "blitz": return .blitz
        case "rapid": return .rapid
        default: break
        }
    }

    guard let timeControl else { return nil }
    if timeControl.contains("/") {
        return .rapid
    }
    let parts = timeControl.split(separator: "+")
    let baseSeconds = Int(parts.first ?? "") ?? 0
    switch baseSeconds {
    case 0..<180: return .bullet
    case 180..<600: return .blitz
    case 600...: return .rapid
    default: return nil
    }
}
