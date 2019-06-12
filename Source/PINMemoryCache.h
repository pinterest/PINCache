//  PINCache is a modified version of TMCache
//  Modifications by Garrett Moon
//  Copyright (c) 2015 Pinterest. All rights reserved.

#import <Foundation/Foundation.h>

#import <PINCache/PINCacheMacros.h>
#import <PINCache/PINCaching.h>
#import <PINCache/PINCacheObjectSubscripting.h>
#import <PINCache/PINMemoryCaching.h>
NS_ASSUME_NONNULL_BEGIN

@class PINMemoryCache;
@class PINOperationQueue;

/**
 `PINMemoryCache` is a fast, thread safe key/value store similar to `NSCache`. On iOS it will clear itself
 automatically to reduce memory usage when the app receives a memory warning or goes into the background.
 
 Access is natively synchronous. Asynchronous variations are provided. Every asynchronous method accepts a
 callback block that runs on a concurrent <concurrentQueue>, with cache reads and writes protected by a lock.
 
 All access to the cache is dated so the that the least-used objects can be trimmed first. Setting an
 optional <ageLimit> will trigger a GCD timer to periodically to trim the cache to that age.
 
 Objects can optionally be set with a "cost", which could be a byte count or any other meaningful integer.
 Setting a <costLimit> will automatically keep the cache below that value with <trimToCostByDate:>.
 
 Values will not persist after application relaunch or returning from the background. See <PINCache> for
 a memory cache backed by a disk cache.
 */

PIN_SUBCLASSING_RESTRICTED
@interface PINMemoryCache : NSObject <PINMemoryCaching>

#pragma mark - Lifecycle
/// @name Shared Cache

/**
 A shared cache.

 @result The shared singleton cache instance.
 */
@property (class, strong, readonly) PINMemoryCache *sharedCache;

- (instancetype)initWithOperationQueue:(PINOperationQueue *)operationQueue;

- (instancetype)initWithName:(NSString *)name operationQueue:(PINOperationQueue *)operationQueue;

- (instancetype)initWithName:(NSString *)name operationQueue:(PINOperationQueue *)operationQueue ttlCache:(BOOL)ttlCache NS_DESIGNATED_INITIALIZER;

@end


#pragma mark - Deprecated

typedef void (^PINMemoryCacheBlock)(PINMemoryCache *cache);
typedef void (^PINMemoryCacheObjectBlock)(PINMemoryCache *cache, NSString *key, id _Nullable object);
typedef void (^PINMemoryCacheContainmentBlock)(BOOL containsObject);

@interface PINMemoryCache (Deprecated)
- (void)containsObjectForKey:(NSString *)key block:(PINMemoryCacheContainmentBlock)block __attribute__((deprecated));
- (void)objectForKey:(NSString *)key block:(nullable PINMemoryCacheObjectBlock)block __attribute__((deprecated));
- (void)setObject:(id)object forKey:(NSString *)key block:(nullable PINMemoryCacheObjectBlock)block __attribute__((deprecated));
- (void)setObject:(id)object forKey:(NSString *)key withCost:(NSUInteger)cost block:(nullable PINMemoryCacheObjectBlock)block __attribute__((deprecated));
- (void)removeObjectForKey:(NSString *)key block:(nullable PINMemoryCacheObjectBlock)block __attribute__((deprecated));
- (void)trimToDate:(NSDate *)date block:(nullable PINMemoryCacheBlock)block __attribute__((deprecated));
- (void)trimToCost:(NSUInteger)cost block:(nullable PINMemoryCacheBlock)block __attribute__((deprecated));
- (void)trimToCostByDate:(NSUInteger)cost block:(nullable PINMemoryCacheBlock)block __attribute__((deprecated));
- (void)removeAllObjects:(nullable PINMemoryCacheBlock)block __attribute__((deprecated));
- (void)enumerateObjectsWithBlock:(PINMemoryCacheObjectBlock)block completionBlock:(nullable PINMemoryCacheBlock)completionBlock __attribute__((deprecated));
- (void)setTtlCache:(BOOL)ttlCache DEPRECATED_MSG_ATTRIBUTE("ttlCache is no longer a settable property and must now be set via initializer.");
@end

NS_ASSUME_NONNULL_END
