#import <AppKit/AppKit.h>
#include <stdlib.h>
#include <string.h>

// User selection grants this unsandboxed, consistently signed app access to
// the folder, including when reselecting the current folder to restore access.
char *drift_choose_notebook(const char *path) {
    @autoreleasepool {
        NSCAssert(NSThread.isMainThread, @"Notebook selection must be on the main thread");
        NSOpenPanel *panel = [NSOpenPanel openPanel];
        panel.title = @"Change Folder";
        panel.message = @"Choose which folder to keep your notes in";
        panel.prompt = @"Use Folder";
        panel.canChooseDirectories = YES;
        panel.canChooseFiles = NO;
        panel.canCreateDirectories = YES;
        panel.allowsMultipleSelection = NO;
        panel.directoryURL = [NSURL fileURLWithPath:[NSString stringWithUTF8String:path] isDirectory:YES];
        if ([panel runModal] != NSModalResponseOK) return NULL;
        return strdup(panel.URL.path.fileSystemRepresentation);
    }
}

void drift_free_notebook_path(char *path) {
    free(path);
}
