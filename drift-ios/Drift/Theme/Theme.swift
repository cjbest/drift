import SwiftUI

/// Manuscript v1 design tokens. Mirrors `drift-design/spec.md` in the cb workspace.
/// Wordmark + app icon are placeholders — branding round to follow.
enum Theme {
    // MARK: Colors

    static let ink     = Color(red: 0x1A/255, green: 0x14/255, blue: 0x10/255)
    static let paper   = Color(red: 0xF7/255, green: 0xF3/255, blue: 0xE9/255)
    static let accent  = Color(red: 0x6B/255, green: 0x3F/255, blue: 0x1A/255)

    /// 0.5pt row dividers — accent at 15% alpha.
    static let hairline = accent.opacity(0.15)

    /// Background for the tinted nav circle buttons.
    static let tintBg = accent.opacity(0.10)

    /// Background for the search field.
    static let fieldBg = accent.opacity(0.06)

    /// Stroke for the editor's hairline-outlined back button.
    static let backOutline = accent.opacity(0.30)

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

    static var inkUIColor: UIColor    { UIColor(ink) }
    static var paperUIColor: UIColor  { UIColor(paper) }
    static var accentUIColor: UIColor { UIColor(accent) }
}
