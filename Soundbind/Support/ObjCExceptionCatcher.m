#import "ObjCExceptionCatcher.h"

@implementation ObjCExceptionCatcher

+ (BOOL)performBlock:(NS_NOESCAPE void (^)(void))block error:(NSError **)error {
    @try {
        block();
        return YES;
    } @catch (NSException *exception) {
        if (error) {
            *error = [NSError errorWithDomain:@"Soundbind.ObjCException"
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey: exception.reason ?: exception.name}];
        }
        return NO;
    }
}

@end
