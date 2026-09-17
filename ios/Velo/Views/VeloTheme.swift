import SwiftUI

enum VeloTheme {
    static let background = Color(red: 242/255, green: 243/255, blue: 245/255)
    static let surface = Color.white
    static let foreground = Color(red: 21/255, green: 26/255, blue: 35/255)
    static let accent = Color(red: 37/255, green: 99/255, blue: 235/255)
    static let onAccent = Color.white
    static let secondary = Color(red: 99/255, green: 112/255, blue: 131/255)
    static let border = Color(red: 220/255, green: 225/255, blue: 233/255)
    static let track = Color(red: 231/255, green: 235/255, blue: 242/255)
    static let tick = Color(red: 153/255, green: 164/255, blue: 181/255)
    static let warning = Color(red: 194/255, green: 65/255, blue: 12/255)
}

struct Panel: ViewModifier {
    func body(content: Content) -> some View {
        content.padding(20)
            .background(VeloTheme.surface, in: RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(VeloTheme.border, lineWidth: 1))
    }
}

extension View {
    func veloPanel() -> some View { modifier(Panel()) }
}
