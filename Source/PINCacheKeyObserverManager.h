//
//  PINCacheKeyObserverManager.h
//  PINCache
//
//  Created by Rocir Santiago on 11/16/17.
//  Copyright © 2017 Pinterest. All rights reserved.
//

#import <Foundation/Foundation.h>

#import <PINCache/PINCacheKeyObserving.h>
#import <PINCache/PINCaching.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString * const PINCacheKeyChangedName;
extern NSString * const PINCacheKeyChangedValue;
extern NSString * const PINCacheKeyChangedCache;

/**
 * `PINCacheKeyObserverManager` is a class designed for handling key observing with PINCache. It can
 * be used with any class conforming to `PINCaching`. By default, `PINCache`, `PINMemoryCache` and
 * `PINDiskCache` already use it.
 */
@interface PINCacheKeyObserverManager : NSObject <PINCacheKeyObserving>

- (instancetype)init NS_UNAVAILABLE;

/**
 * Creates a new instance of `PINCacheObserverManager`.
 *
 * @param cache The cache instance to which the manager will handle key/value changes.
 */
- (instancetype)initWithCache:(id<PINCaching>)cache NS_DESIGNATED_INITIALIZER;

/**
 * Should be called when a value for a key in the cache has been added or updated.
 *
 * @param key The key which value has been updated.
 * @param value The new value associated with the key.
 */
- (void)updatedKey:(NSString *)key withValue:(nullable id)value;

/**
 * Should be called when a given value for a key has been removed from the cache.
 *
 * @param key The key which value has been removed from the cache.
 */
- (void)deletedValueForKey:(NSString *)key;

/**
 * Should be called when all the values in the cache have been removed.
 */
- (void)deletedAllValues;

@end

NS_ASSUME_NONNULL_END
