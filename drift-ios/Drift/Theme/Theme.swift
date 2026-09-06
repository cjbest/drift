import SwiftUI
import UIKit

/// A quiet notebook: warm paper, soft ink, generous type.
enum Theme {
    static let paperUIColor = UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 0x18/255, green: 0x14/255, blue: 0x12/255, alpha: 1)
        : UIColor(red: 0xF7/255, green: 0xF3/255, blue: 0xE9/255, alpha: 1) }
    static let inkUIColor = UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 0xF0/255, green: 0xE8/255, blue: 0xDC/255, alpha: 1)
        : UIColor(red: 0x1A/255, green: 0x14/255, blue: 0x10/255, alpha: 1) }
    static let accentUIColor = UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 0xC8/255, green: 0x91/255, blue: 0x67/255, alpha: 1)
        : UIColor(red: 0x6B/255, green: 0x3F/255, blue: 0x1A/255, alpha: 1) }
    static var secondaryInkUIColor: UIColor { inkUIColor.withAlphaComponent(0.55) }
    static var hairlineUIColor: UIColor { accentUIColor.withAlphaComponent(0.15) }
    static var cardUIColor: UIColor { paperUIColor }

    static var paper: Color { Color(uiColor: paperUIColor) }
    static var ink: Color { Color(uiColor: inkUIColor) }
    static var accent: Color { Color(uiColor: accentUIColor) }
    static var hairline: Color { Color(uiColor: hairlineUIColor) }

    static func serif(_ size: CGFloat, style: UIFont.TextStyle = .title2, italic: Bool = false,
                      compatibleWith traits: UITraitCollection? = nil) -> UIFont {
        let name = italic ? "Newsreader16pt-Italic" : "Newsreader16pt-Regular"
        let base = UIFont(name: name, size: size) ?? UIFont.systemFont(ofSize: size, weight: .regular, width: .standard)
        return UIFontMetrics(forTextStyle: style).scaledFont(for: base, compatibleWith: traits)
    }
    static func mono(_ size: CGFloat, style: UIFont.TextStyle = .body) -> UIFont {
        UIFontMetrics(forTextStyle: style).scaledFont(for: UIFont(name: "JetBrainsMono-Regular", size: size) ?? UIFont.monospacedSystemFont(ofSize: size, weight: .regular))
    }
    static func bodyUIFont() -> UIFont { UIFont.preferredFont(forTextStyle: .body) }
    static func editorTitleUIFont() -> UIFont { serif(32, style: .title1) }
    static func navTitleUIFont() -> UIFont { serif(22, style: .headline, italic: true) }
    static func rowTitleUIFont(compatibleWith traits: UITraitCollection? = nil) -> UIFont {
        serif(22, compatibleWith: traits)
    }
    static func navTitle() -> Font { Font(navTitleUIFont()) }
    static func rowTitle() -> Font { Font(rowTitleUIFont()) }
    static func rowSub() -> Font { .subheadline }
    static func searchPlaceholder() -> Font { .body }
    static func body() -> Font { .body }
    static func bodyItalic() -> Font { .body.italic() }
    static func editorTitle() -> Font { Font(editorTitleUIFont()) }
}
