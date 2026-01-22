import SwiftUI

struct BoardTheme: Identifiable {
    let id: String
    let lightHex: String
    let darkHex: String

    var lightColor: Color { Color(hex: lightHex) }
    var darkColor: Color { Color(hex: darkHex) }

    static let themes: [BoardTheme] = [
        BoardTheme(id: "theme-0", lightHex: "EBECD0", darkHex: "789957"),
        BoardTheme(id: "theme-1", lightHex: "697281", darkHex: "252C39"),
        BoardTheme(id: "theme-2", lightHex: "EDD6B0", darkHex: "B88762"),
        BoardTheme(id: "theme-3", lightHex: "D8E3E7", darkHex: "7094A9"),
        BoardTheme(id: "theme-4", lightHex: "F0F1F0", darkHex: "C4D8E4"),
        BoardTheme(id: "theme-5", lightHex: "F5D2A9", darkHex: "B15A2B"),
        BoardTheme(id: "theme-6", lightHex: "F3F3F4", darkHex: "6A9B41"),
        BoardTheme(id: "theme-7", lightHex: "C6C1AA", darkHex: "595652"),
        BoardTheme(id: "theme-8", lightHex: "F0F1F0", darkHex: "8476BA"),
        BoardTheme(id: "theme-9", lightHex: "8B8A89", darkHex: "696867"),
        BoardTheme(id: "theme-10", lightHex: "D5D5D5", darkHex: "797979"),
        BoardTheme(id: "theme-11", lightHex: "DFDED9", darkHex: "2F6347"),
        BoardTheme(id: "theme-12", lightHex: "B98B4E", darkHex: "5D301F"),
        BoardTheme(id: "theme-13", lightHex: "EAE9D2", darkHex: "4B7399"),
        BoardTheme(id: "theme-14", lightHex: "FEFFFE", darkHex: "FBD9E1"),
        BoardTheme(id: "theme-15", lightHex: "C74C51", darkHex: "303030"),
        BoardTheme(id: "theme-16", lightHex: "D8D9D8", darkHex: "A8A9A8"),
        BoardTheme(id: "theme-17", lightHex: "FAE4AE", darkHex: "D18815"),
        BoardTheme(id: "theme-18", lightHex: "8B8A89", darkHex: "696867"),
        BoardTheme(id: "theme-19", lightHex: "F4DAC2", darkHex: "BB5746"),
        BoardTheme(id: "theme-20", lightHex: "EDCBA5", darkHex: "D8A46D"),
        BoardTheme(id: "theme-21", lightHex: "F2F6FA", darkHex: "5596F2"),
        BoardTheme(id: "theme-22", lightHex: "F5F0F1", darkHex: "EC94A4"),
        BoardTheme(id: "theme-23", lightHex: "D7D4D4", darkHex: "807B76")
    ]

    static let defaultId = themes.first?.id ?? "theme-0"

    static func theme(for id: String) -> BoardTheme {
        themes.first(where: { $0.id == id }) ?? themes[0]
    }
}
