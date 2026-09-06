#import <AppKit/AppKit.h>

static void use_return_key(NSMenu *menu) {
    for (NSMenuItem *item in menu.itemArray) {
        // muda 0.17 maps Code::Enter to NSEnterCharacter (keypad Enter).
        // Drift's Command+Return action uses the ordinary keyboard Return key.
        if ([item.keyEquivalent isEqualToString:@"\003"])
            item.keyEquivalent = @"\r";
        if (item.submenu) use_return_key(item.submenu);
    }
}

void drift_use_return_key(void) {
    use_return_key(NSApp.mainMenu);
}
