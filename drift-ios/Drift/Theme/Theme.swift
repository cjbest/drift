import SwiftUI
import UIKit

/// Manuscript v1 design tokens.
/// Wordmark + app icon are placeholders — branding round to follow.
enum Theme {
    // MARK: Colors
    //
    // Each base color is defined as a UIColor with a dynamic provider so the
    // entire palette adapts to the system colorScheme. The SwiftUI `Color`
    // values bridge through `Color(uiColor:)`. Light is "manuscript on cream";
    // dark is "manuscript at night" — warm dark background, warm light ink,
    // brighter sepia accent so contrast holds.

    static let inkUIColor: UIColor = UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0xF0/255, green: 0xE8/255, blue: 0xDC/255, alpha: 1)
            : UIColor(red: 0x1A/255, green: 0x14/255, blue: 0x10/255, alpha: 1)
    }

    static let paperUIColor: UIColor = UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0x18/255, green: 0x14/255, blue: 0x12/255, alpha: 1)
            : UIColor(red: 0xF7/255, green: 0xF3/255, blue: 0xE9/255, alpha: 1)
    }

    static let accentUIColor: UIColor = UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0xC8/255, green: 0x91/255, blue: 0x67/255, alpha: 1)
            : UIColor(red: 0x6B/255, green: 0x3F/255, blue: 0x1A/255, alpha: 1)
    }

    static var ink:    Color { Color(uiColor: inkUIColor) }
    static var paper:  Color { Color(uiColor: paperUIColor) }
    static var accent: Color { Color(uiColor: accentUIColor) }

    /// 0.5pt row dividers — accent at 15% alpha.
    static var hairline: Color { accent.opacity(0.15) }

    /// Background for the tinted nav circle buttons.
    static var tintBg: Color { accent.opacity(0.10) }

    /// Background for the search field.
    static var fieldBg: Color { accent.opacity(0.06) }

    /// Stroke for the editor's hairline-outlined back button.
    static var backOutline: Color { accent.opacity(0.30) }

    // MARK: Font names (PostScript)

    private static let displayItalicName = "Newsreader16pt-Italic"
    private static let displayRomanName  = "Newsreader16pt-Regular"
    private static let monoName          = "JetBrainsMono-Regular"
    private static let monoItalicName    = "JetBrainsMono-Italic"

    // MARK: Type ramp (iOS pt)

    static func navTitle() -> Font {
        .custom(displayItalicName, size: 22)
    }

    static func editorTitle() -> Font {
        .custom(displayItalicName, size: 34)
    }

    static func rowTitle() -> Font {
        .custom(monoName, size: 16).weight(.medium)
    }

    static func rowSub() -> Font {
        .custom(monoName, size: 13).weight(.light)
    }

    static func searchPlaceholder() -> Font {
        .custom(monoName, size: 15)
    }

    static func body() -> Font {
        .custom(monoName, size: 16)
    }

    static func bodyItalic() -> Font {
        .custom(monoItalicName, size: 16)
    }

    // MARK: UIKit bridges (nav bar / search bar appearance, UITextView fonts)

    static func navTitleUIFont() -> UIFont {
        UIFont(name: displayItalicName, size: 22) ?? UIFont.systemFont(ofSize: 22)
    }

    static func bodyUIFont() -> UIFont {
        UIFont(name: monoName, size: 16) ?? UIFont.monospacedSystemFont(ofSize: 16, weight: .regular)
    }

    static func editorTitleUIFont() -> UIFont {
        UIFont(name: displayItalicName, size: 34) ?? UIFont.systemFont(ofSize: 34, weight: .semibold)
    }

}
