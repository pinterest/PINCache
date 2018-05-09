#import "PINDiskCache+PINCacheTests.h"

@interface PINDiskCache ()
- (void)setTtlCache:(BOOL)ttlCache;
@end

@implementation PINDiskCache (PINCacheTests)

- (void)setTtlCacheSync:(BOOL)ttlCache
{
    [self setTtlCache:ttlCache];

    // Attempt to read from the cache. This will be put on the same queue as `setTtlCache`, but at a lower priority.
    // When the completion handler runs, we can be sure the property value has been set.
    dispatch_group_t group = dispatch_group_create();
    dispatch_group_enter(group);
    [self objectForKeyAsync:@"some bogus key" completion:^(PINDiskCache *cache, NSString *key, id<NSCoding> object) {
        dispatch_group_leave(group);
    }];
    dispatch_group_wait(group, DISPATCH_TIME_FOREVER);
}

@end
