#import <Foundation/Foundation.h>
#import <objc/runtime.h>

/// Boots the Dynamic Island as early as possible.
///
/// CapriCompanion starts its island from SwiftUI's launch path. CapriGram's
/// launch path is compiled into TelegramUIFramework, so the equivalent hook is
/// `+load`: it runs when this class is first loaded into the process, before
/// `UIApplicationMain` finishes, which is early enough to register the
/// background refresh task and subscribe to the lifecycle notifications.
///
/// The actual work lives in the Swift `CapriGramIslandLoader`. This file only
/// exists because `+load` is an Objective-C concept and Swift has no direct
/// equivalent that is guaranteed to run for a statically linked class.
@interface CapriGramIslandBootstrap : NSObject
@end

@implementation CapriGramIslandBootstrap

+ (void)load {
    // Resolve the Swift loader by its Objective-C name. It's looked up rather
    // than imported so this file doesn't need a bridging header.
    Class loaderClass = NSClassFromString(@"CapriGramIslandLoader");
    if (loaderClass == Nil) {
        return;
    }

    SEL sharedSelector = NSSelectorFromString(@"shared");
    if (![loaderClass respondsToSelector:sharedSelector]) {
        return;
    }

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    id loader = [loaderClass performSelector:sharedSelector];
    SEL installSelector = NSSelectorFromString(@"install");
    if ([loader respondsToSelector:installSelector]) {
        [loader performSelector:installSelector];
    }
#pragma clang diagnostic pop
}

@end
