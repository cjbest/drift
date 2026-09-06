#import <Foundation/Foundation.h>
#include <stdbool.h>
// Synchronous file-provider coordination shared with the iOS notebook.
bool drift_coordinate_write(const char *path, void (*operation)(void *), void *context) {
    @autoreleasepool {
        NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
        NSURL *url = [NSURL fileURLWithPath:[NSString stringWithUTF8String:path]];
        __block bool ran = false;
        NSError *error = nil;
        [coordinator coordinateWritingItemAtURL:url options:NSFileCoordinatorWritingForReplacing error:&error byAccessor:^(NSURL *coordinatedURL) {
            (void)coordinatedURL;
            operation(context);
            ran = true;
        }];
        return ran && error == nil;
    }
}
