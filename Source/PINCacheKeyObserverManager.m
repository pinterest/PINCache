//
//  PINCacheKeyObserverManager.m
//  PINCache
//
//  Created by Rocir Santiago on 11/16/17.
//  Copyright © 2017 Pinterest. All rights reserved.
//

#import "PINCacheKeyObserverManager.h"

#import <PINCache/PINCache.h>

NSString * const PINCacheKeyChangedName = @"PINCacheKeyChangedName";
NSString * const PINCacheKeyChangedValue = @"PINCacheKeyChangedValue";
NSString * const PINCacheKeyChangedCache = @"PINCacheKeyChangedCache";

static NSString * const PINCacheKeyChangedNotificationFormat = @"PINCacheKeyChanged.%@";

@interface PINCacheKeyObserverManager ()
@property (weak, nonatomic) id<PINCaching> cache;
@property (strong, nonatomic) NSMutableDictionary<NSString *, NSMutableSet<id> *> *keysToObserversMapping;
@property (strong, nonatomic) dispatch_queue_t queue;
// We have our own notification center instead of the default one so removing them from the center doesn't conflict with anything non PINCache related.
@property (strong, nonatomic) NSNotificationCenter *observersNotificationCenter;
@end

@implementation PINCacheKeyObserverManager

#pragma mark - Initialization

- (instancetype)initWithCache:(id<PINCaching>)cache
{
    self = [super init];
    if (self) {
        _cache = cache;
        _keysToObserversMapping = [[NSMutableDictionary alloc] init];
        NSString *queueName = [NSString stringWithFormat:@"%@.key_observer_manager", PINDiskCachePrefix];
        _queue = dispatch_queue_create([queueName UTF8String], DISPATCH_QUEUE_SERIAL);
        _observersNotificationCenter = [[NSNotificationCenter alloc] init];
    }
    return self;
}

#pragma mark - Public methods

- (void)updatedKey:(NSString *)key withValue:(id)value
{
    dispatch_async(_queue, ^{
        if (key.length == 0 || ![self isTrackingKey:key]) {
            return;
        }
        
        NSDictionary *userInfo = [self userInfoForKey:key withValue:value];
        [_observersNotificationCenter postNotificationName:[self notificationNameForKey:key]
                                                    object:nil
                                                  userInfo:userInfo];
    });
}

- (void)deletedValueForKey:(NSString *)key
{
    dispatch_async(_queue, ^{
        if (key.length == 0 || ![self isTrackingKey:key]) {
            return;
        }
        
        NSDictionary *userInfo = [self userInfoForKey:key withValue:nil];
        [_observersNotificationCenter postNotificationName:[self notificationNameForKey:key]
                                                    object:nil
                                                  userInfo:userInfo];
    });
}

- (void)deletedAllValues
{
    for (NSString *key in [_keysToObserversMapping allKeys]) {
        [self deletedValueForKey:key];
    }
}

#pragma mark - PINCacheKeyObserving

- (void)addObserver:(id)observer selector:(SEL)selector forKey:(NSString *)key
{
    if (key.length == 0) {
        return;
    }
    
    dispatch_async(_queue, ^{
        [_observersNotificationCenter addObserver:observer
                                         selector:selector
                                             name:[self notificationNameForKey:key]
                                           object:nil];
        
        NSMutableSet<id> *observers = _keysToObserversMapping[key];
        if (observers == nil) {
            observers = [[NSMutableSet alloc] init];
            _keysToObserversMapping[key] = observers;
        }
        [observers addObject:observer];
        
    });
}

- (void)removeObserver:(id)observer forKey:(NSString *)key
{
    if (key.length == 0) {
        return;
    }
    
    dispatch_async(_queue, ^{
        [_observersNotificationCenter removeObserver:observer
                                                name:[self notificationNameForKey:key]
                                              object:nil];
        
        NSMutableSet<id> *observers = _keysToObserversMapping[key];
        [observers removeObject:observer];
    });
}

#pragma mark - Private

- (BOOL)isTrackingKey:(NSString *)key
{
    NSSet<id> *set = _keysToObserversMapping[key];
    return set.count > 0;
}

- (NSString *)notificationNameForKey:(NSString *)key
{
    return [NSString stringWithFormat:PINCacheKeyChangedNotificationFormat, key];
}

- (NSDictionary *)userInfoForKey:(NSString *)key withValue:(id)value
{
    NSMutableDictionary *userInfo = [[NSMutableDictionary alloc] init];
    userInfo[PINCacheKeyChangedName] = key;
    if (value != nil) {
        userInfo[PINCacheKeyChangedValue] = value;
    }
    if (self.cache) {
        userInfo[PINCacheKeyChangedCache] = self.cache;
    }
    return userInfo;
}

@end
