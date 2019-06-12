//
//  PINPurgeableMemoryCache.m
//  PINCache
//
//  Created by Rahul Malik on 6/12/19.
//  Copyright © 2019 Pinterest. All rights reserved.
//

#import "PINPurgeableMemoryCache.h"
#import <PINOperation/PINOperation.h>

static NSString * const PINPurgeableMemoryCacheSharedName = @"PINPurgeableMemoryCacheSharedName";


@implementation PINPurgeableMemoryCache
{
    NSString *_name;
    NSCache *_internalCache;
    PINOperationQueue *_operationQueue;
}

@synthesize name = _name;
@synthesize ageLimit = _ageLimit;
@synthesize costLimit = _costLimit;
@synthesize totalCost = _totalCost;
@synthesize ttlCache = _ttlCache;
@synthesize willAddObjectBlock = _willAddObjectBlock;
@synthesize willRemoveObjectBlock = _willRemoveObjectBlock;
@synthesize willRemoveAllObjectsBlock = _willRemoveAllObjectsBlock;
@synthesize didAddObjectBlock = _didAddObjectBlock;
@synthesize didRemoveObjectBlock = _didRemoveObjectBlock;
@synthesize didRemoveAllObjectsBlock = _didRemoveAllObjectsBlock;
@synthesize didReceiveMemoryWarningBlock = _didReceiveMemoryWarningBlock;
@synthesize didEnterBackgroundBlock = _didEnterBackgroundBlock;
@synthesize removeAllObjectsOnMemoryWarning = _removeAllObjectsOnMemoryWarning;
@synthesize removeAllObjectsOnEnteringBackground = _removeAllObjectsOnEnteringBackground;


- (instancetype)init
{
    return [self initWithOperationQueue:[PINOperationQueue sharedOperationQueue]];
}

- (instancetype)initWithOperationQueue:(PINOperationQueue *)operationQueue
{
    return [self initWithName:PINPurgeableMemoryCacheSharedName
               operationQueue:operationQueue];
}


- (instancetype)initWithName:(NSString *)name operationQueue:(PINOperationQueue *)operationQueue
{
    if (self = [super init]) {
        _name = [name copy];
        _operationQueue = operationQueue;
        _internalCache = [[NSCache alloc] init];
        _willAddObjectBlock = nil;
        _willRemoveObjectBlock = nil;
        _willRemoveAllObjectsBlock = nil;
        _didAddObjectBlock = nil;
        _didRemoveObjectBlock = nil;
        _didRemoveAllObjectsBlock = nil;
        _didReceiveMemoryWarningBlock = nil;
        _didEnterBackgroundBlock = nil;
//        _removeAllObjectsOnMemoryWarning = YES;
//        _removeAllObjectsOnEnteringBackground = YES;

//#if __IPHONE_OS_VERSION_MIN_REQUIRED >= __IPHONE_4_0 && !TARGET_OS_WATCH
//        [[NSNotificationCenter defaultCenter] addObserver:self
//                                                 selector:@selector(didReceiveEnterBackgroundNotification:)
//                                                     name:UIApplicationDidEnterBackgroundNotification
//                                                   object:nil];
//        [[NSNotificationCenter defaultCenter] addObserver:self
//                                                 selector:@selector(didReceiveMemoryWarningNotification:)
//                                                     name:UIApplicationDidReceiveMemoryWarningNotification
//                                                   object:nil];
//
//#endif
    }
    return self;
}


- (BOOL)containsObjectForKey:(nonnull NSString *)key {
    return [_internalCache objectForKey:key];
}

- (void)containsObjectForKeyAsync:(nonnull NSString *)key completion:(nonnull PINCacheObjectContainmentBlock)block {
    [_operationQueue scheduleOperation:^{
        return block([self->_internalCache objectForKey:key] != nil);
    }];
}

- (nullable id)objectForKey:(nonnull NSString *)key {
    return [_internalCache objectForKey:key];
}

- (void)objectForKeyAsync:(nonnull NSString *)key completion:(nonnull PINCacheObjectBlock)block {
    [_operationQueue scheduleOperation:^{
        block(self, key, [self->_internalCache objectForKey:key]);
    }];
}

- (void)removeAllObjects {
    [_internalCache removeAllObjects];
}

- (void)removeAllObjectsAsync:(nullable PINCacheBlock)block {
    [_operationQueue scheduleOperation:^{
        [self->_internalCache removeAllObjects];
    }];
}

- (void)removeExpiredObjects {
    // NO-OP
}

- (void)removeExpiredObjectsAsync:(nullable PINCacheBlock)block {
    // NO-OP

}

- (void)removeObjectForKey:(nonnull NSString *)key {
    [_internalCache removeObjectForKey:key];
}

- (void)removeObjectForKeyAsync:(nonnull NSString *)key completion:(nullable PINCacheObjectBlock)block {
    [_operationQueue scheduleOperation:^{
        [self->_internalCache removeObjectForKey:key];
    }];
}

- (void)setObject:(nullable id)object forKey:(nonnull NSString *)key {
    [_internalCache setObject:object forKey:key];
}

- (void)setObject:(nullable id)object forKey:(nonnull NSString *)key withAgeLimit:(NSTimeInterval)ageLimit {
    // Same as setObject:forKey:
    // Look into removing this API
    [self setObject:object forKey:key];
}

- (void)setObject:(nullable id)object forKey:(nonnull NSString *)key withCost:(NSUInteger)cost {
    [_internalCache setObject:object forKey:key cost:cost];
}

- (void)setObject:(nullable id)object forKey:(nonnull NSString *)key withCost:(NSUInteger)cost ageLimit:(NSTimeInterval)ageLimit {
    // Same as setObject:forKey:cost:
    // Look into removing this API
    [self setObject:object forKey:key withCost:cost];
}

- (void)setObjectAsync:(nonnull id)object forKey:(nonnull NSString *)key completion:(nullable PINCacheObjectBlock)block {
    [_operationQueue scheduleOperation:^{
        [self->_internalCache setObject:object forKey:key];
        if (block) {
            block(self, key, object);
        }

    }];
}

- (void)setObjectAsync:(nonnull id)object forKey:(nonnull NSString *)key withAgeLimit:(NSTimeInterval)ageLimit completion:(nullable PINCacheObjectBlock)block {
    [self setObjectAsync:object forKey:key completion:block];
}

- (void)setObjectAsync:(nonnull id)object forKey:(nonnull NSString *)key withCost:(NSUInteger)cost ageLimit:(NSTimeInterval)ageLimit completion:(nullable PINCacheObjectBlock)block {
    [self setObjectAsync:object forKey:key withCost:cost  completion:block];
}

- (void)setObjectAsync:(nonnull id)object forKey:(nonnull NSString *)key withCost:(NSUInteger)cost completion:(nullable PINCacheObjectBlock)block {
    [_operationQueue scheduleOperation:^{
        [self->_internalCache setObject:object forKey:key cost:cost];
    }];
}

- (void)trimToDate:(nonnull NSDate *)date {
    // NO-OP
}

- (void)trimToDateAsync:(nonnull NSDate *)date completion:(nullable PINCacheBlock)block {
    // NO-OP
    block(self);
}

- (void)enumerateObjectsWithBlock:(PIN_NOESCAPE PINCacheObjectEnumerationBlock)block {
    // NO-OP - Should we assert here?
}

- (void)enumerateObjectsWithBlockAsync:(PINCacheObjectEnumerationBlock)block completionBlock:(nullable PINCacheBlock)completionBlock {
    // NO-OP
    completionBlock(self);
}

- (void)trimToCost:(NSUInteger)cost {
    // NO-OP (nscache handles this internally)
}

- (void)trimToCostAsync:(NSUInteger)cost completion:(nullable PINCacheBlock)block {
    // NO-OP (nscache handles this internally)
    block(self);
}

- (void)trimToCostByDate:(NSUInteger)cost {
    // NO-OP (nscache handles this internally)
}

- (void)trimToCostByDateAsync:(NSUInteger)cost completion:(nullable PINCacheBlock)block {
    // NO-OP (nscache handles this internally)
    block(self);
}

#pragma mark PINCacheObjectSubscripting

- (nullable id)objectForKeyedSubscript:(NSString *)key
{
    return [self objectForKey:key];
}

- (void)setObject:(nullable id)object forKeyedSubscript:(NSString *)key
{
    [self setObject:object forKey:key];
}

@end
