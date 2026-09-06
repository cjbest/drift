#import <AppKit/AppKit.h>
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>

@interface DriftNotebookAccessValidator : NSObject <NSOpenSavePanelDelegate>
@property(nonatomic, strong) NSURL *notebookURL;
@end

@implementation DriftNotebookAccessValidator
- (BOOL)panel:(id)sender validateURL:(NSURL *)url error:(NSError **)outError {
    (void)sender;
    NSString *selected = url.URLByResolvingSymlinksInPath.URLByStandardizingPath.path;
    NSString *expected = self.notebookURL.URLByResolvingSymlinksInPath.URLByStandardizingPath.path;
    if ([selected isEqualToString:expected]) return YES;
    if (outError) {
        *outError = [NSError errorWithDomain:@"DriftNotebookAccess" code:1 userInfo:@{
            NSLocalizedDescriptionKey: @"Choose your existing Drift notebook.",
            NSLocalizedRecoverySuggestionErrorKey: [NSString stringWithFormat:@"Select %@ to allow access to your current notes.", expected]
        }];
    }
    return NO;
}
@end

// An ordinary user-selected folder grants this unsandboxed app access. This
// panel authorizes the existing notebook; it never changes or creates one.
bool drift_allow_notebook_access(const char *path) {
    @autoreleasepool {
        NSCAssert(NSThread.isMainThread, @"Notebook access must be requested on the main thread");
        NSURL *url = [NSURL fileURLWithPath:[NSString stringWithUTF8String:path] isDirectory:YES];
        NSOpenPanel *panel = [NSOpenPanel openPanel];
        panel.title = @"Allow Notebook Access";
        panel.message = @"Choose your existing Drift notebook to allow access to its notes.";
        panel.prompt = @"Allow Access";
        panel.canChooseDirectories = YES;
        panel.canChooseFiles = NO;
        panel.canCreateDirectories = NO;
        panel.allowsMultipleSelection = NO;
        panel.directoryURL = url;
        __attribute__((objc_precise_lifetime)) DriftNotebookAccessValidator *validator = [DriftNotebookAccessValidator new];
        validator.notebookURL = url;
        panel.delegate = validator;
        BOOL allowed = [panel runModal] == NSModalResponseOK;
        panel.delegate = nil;
        return allowed;
    }
}

// User selection grants this unsandboxed, consistently signed app access to
// the folder, just as the existing Allow Notebook Access panel does.
char *drift_choose_notebook(const char *path) {
    @autoreleasepool {
        NSCAssert(NSThread.isMainThread, @"Notebook selection must be on the main thread");
        NSOpenPanel *panel = [NSOpenPanel openPanel];
        panel.title = @"Choose Notebook Folder";
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
