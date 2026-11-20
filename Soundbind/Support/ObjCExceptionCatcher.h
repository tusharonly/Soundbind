#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// AVAudioEngine reports some failures (e.g. starting a player while the engine is
/// stopped mid route-change) as Objective-C exceptions, which Swift cannot catch.
@interface ObjCExceptionCatcher : NSObject
+ (BOOL)performBlock:(NS_NOESCAPE void (^)(void))block error:(NSError *_Nullable *_Nullable)error;
@end

NS_ASSUME_NONNULL_END
