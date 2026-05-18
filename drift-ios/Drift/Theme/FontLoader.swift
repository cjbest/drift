import CoreText
import Foundation

/// Registers bundled .ttf files with CoreText at process scope so they are
/// resolvable by PostScript name (`Newsreader16pt-Italic`, `JetBrainsMono-Regular`,
/// etc.) without needing UIAppFonts entries in Info.plist.
enum FontLoader {
    private static let files = [
        "Newsreader",
        "Newsreader-Italic",
        "JetBrainsMono",
        "JetBrainsMono-Italic",
    ]

    static func registerAll() {
        for name in files {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else {
                assertionFailure("Missing bundled font: \(name).ttf")
                continue
            }
            var error: Unmanaged<CFError>?
            if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
                let desc = error?.takeRetainedValue().localizedDescription ?? "unknown"
                // Already-registered isn't fatal; log and continue.
                print("FontLoader: \(name).ttf — \(desc)")
            }
        }
    }
}
