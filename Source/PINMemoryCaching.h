//
//  PINMemoryCaching.m
//  PINCache
//
//  Created by Rahul Malik on 6/12/19.
//  Copyright © 2019 Pinterest. All rights reserved.
//

#import <Foundation/Foundation.h>

#import <PINCache/PINCacheMacros.h>
#import <PINCache/PINCaching.h>
#import <PINCache/PINCacheObjectSubscripting.h>

NS_ASSUME_NONNULL_BEGIN

@protocol PINMemoryCaching <PINCaching, PINCacheObjectSubscripting>


#pragma mark - Properties
/// @name Core

/**
 The total accumulated cost.
 */
@property (readonly) NSUInteger totalCost;

/**
 The maximum cost allowed to accumulate before objects begin to be removed with <trimToCostByDate:>.
 */
@property (assign) NSUInteger costLimit;

/**
 The maximum number of seconds an object is allowed to exist in the cache. Setting this to a value
 greater than `0.0` will start a recurring GCD timer with the same period that calls <trimToDate:>.
 Setting it back to `0.0` will stop the timer. Defaults to `0.0`.
 */
@property (assign) NSTimeInterval ageLimit;

/**
 If ttlCache is YES, the cache behaves like a ttlCache. This means that once an object enters the
 cache, it only lives as long as self.ageLimit. This has the following implications:
 - Accessing an object in the cache does not extend that object's lifetime in the cache
 - When attempting to access an object in the cache that has lived longer than self.ageLimit,
 the cache will behave as if the object does not exist

 @note If an object-level age limit is set via one of the @c -setObject:forKey:withAgeLimit methods,
 that age limit overrides self.ageLimit. The overridden object age limit could be greater or
 less than self.agelimit but must be greater than zero.
 */
@property (nonatomic, readonly, getter=isTTLCache) BOOL ttlCache;

/**
 When `YES` on iOS the cache will remove all objects when the app receives a memory warning.
 Defaults to `YES`.
 */
@property (assign) BOOL removeAllObjectsOnMemoryWarning;

/**
 When `YES` on iOS the cache will remove all objects when the app enters the background.
 Defaults to `YES`.
 */
@property (assign) BOOL removeAllObjectsOnEnteringBackground;

#pragma mark - Event Blocks
/// @name Event Blocks

/**
 A block to be executed just before an object is added to the cache. This block will be excuted within
 a lock, i.e. all reads and writes are suspended for the duration of the block.
 Calling synchronous methods on the cache within this callback will likely cause a deadlock.
 */
@property (nullable, copy) PINCacheObjectBlock willAddObjectBlock;

/**
 A block to be executed just before an object is removed from the cache. This block will be excuted
 within a lock, i.e. all reads and writes are suspended for the duration of the block.
 Calling synchronous methods on the cache within this callback will likely cause a deadlock.
 */
@property (nullable, copy) PINCacheObjectBlock willRemoveObjectBlock;

/**
 A block to be executed just before all objects are removed from the cache as a result of <removeAllObjects:>.
 This block will be excuted within a lock, i.e. all reads and writes are suspended for the duration of the block.
 Calling synchronous methods on the cache within this callback will likely cause a deadlock.
 */
@property (nullable, copy) PINCacheBlock willRemoveAllObjectsBlock;

/**
 A block to be executed just after an object is added to the cache. This block will be excuted within
 a lock, i.e. all reads and writes are suspended for the duration of the block.
 Calling synchronous methods on the cache within this callback will likely cause a deadlock.
 */
@property (nullable, copy) PINCacheObjectBlock didAddObjectBlock;

/**
 A block to be executed just after an object is removed from the cache. This block will be excuted
 within a lock, i.e. all reads and writes are suspended for the duration of the block.
 Calling synchronous methods on the cache within this callback will likely cause a deadlock.
 */
@property (nullable, copy) PINCacheObjectBlock didRemoveObjectBlock;

/**
 A block to be executed just after all objects are removed from the cache as a result of <removeAllObjects:>.
 This block will be excuted within a lock, i.e. all reads and writes are suspended for the duration of the block.
 Calling synchronous methods on the cache within this callback will likely cause a deadlock.
 */
@property (nullable, copy) PINCacheBlock didRemoveAllObjectsBlock;

/**
 A block to be executed upon receiving a memory warning (iOS only) potentially in parallel with other blocks on the <queue>.
 This block will be executed regardless of the value of <removeAllObjectsOnMemoryWarning>. Defaults to `nil`.
 */
@property (nullable, copy) PINCacheBlock didReceiveMemoryWarningBlock;

/**
 A block to be executed when the app enters the background (iOS only) potentially in parallel with other blocks on the <concurrentQueue>.
 This block will be executed regardless of the value of <removeAllObjectsOnEnteringBackground>. Defaults to `nil`.
 */
@property (nullable, copy) PINCacheBlock didEnterBackgroundBlock;

#pragma mark - Asynchronous Methods
/// @name Asynchronous Methods

/**
 Removes objects from the cache, costliest objects first, until the <totalCost> is below the specified
 value. This method returns immediately and executes the passed block after the cache has been trimmed,
 potentially in parallel with other blocks on the <concurrentQueue>.

 @param cost The total accumulation allowed to remain after the cache has been trimmed.
 @param block A block to be executed concurrently after the cache has been trimmed, or nil.
 */
- (void)trimToCostAsync:(NSUInteger)cost completion:(nullable PINCacheBlock)block;

/**
 Removes objects from the cache, ordered by date (least recently used first), until the <totalCost> is below
 the specified value. This method returns immediately and executes the passed block after the cache has been
 trimmed, potentially in parallel with other blocks on the <concurrentQueue>.

 @param cost The total accumulation allowed to remain after the cache has been trimmed.
 @param block A block to be executed concurrently after the cache has been trimmed, or nil.
 */
- (void)trimToCostByDateAsync:(NSUInteger)cost completion:(nullable PINCacheBlock)block;

/**
 Loops through all objects in the cache with reads and writes suspended. Calling serial methods which
 write to the cache inside block may be unsafe and may result in a deadlock. This method returns immediately.

 @param block A block to be executed for every object in the cache.
 @param completionBlock An optional block to be executed concurrently when the enumeration is complete.
 */
- (void)enumerateObjectsWithBlockAsync:(PINCacheObjectEnumerationBlock)block completionBlock:(nullable PINCacheBlock)completionBlock;

#pragma mark - Synchronous Methods
/// @name Synchronous Methods

/**
 Removes objects from the cache, costliest objects first, until the <totalCost> is below the specified
 value. This method blocks the calling thread until the cache has been trimmed.

 @see trimToCostAsync:
 @param cost The total accumulation allowed to remain after the cache has been trimmed.
 */
- (void)trimToCost:(NSUInteger)cost;

/**
 Removes objects from the cache, ordered by date (least recently used first), until the <totalCost> is below
 the specified value. This method blocks the calling thread until the cache has been trimmed.

 @see trimToCostByDateAsync:
 @param cost The total accumulation allowed to remain after the cache has been trimmed.
 */
- (void)trimToCostByDate:(NSUInteger)cost;

/**
 Loops through all objects in the cache within a memory lock (reads and writes are suspended during the enumeration).
 This method blocks the calling thread until all objects have been enumerated.
 Calling synchronous methods on the cache within this callback will likely cause a deadlock.

 @see enumerateObjectsWithBlockAsync:completionBlock:
 @param block A block to be executed for every object in the cache.

 @warning Do not call this method within the event blocks (<didReceiveMemoryWarningBlock>, etc.)
 Instead use the asynchronous version, <enumerateObjectsWithBlock:completionBlock:>.

 */
- (void)enumerateObjectsWithBlock:(PIN_NOESCAPE PINCacheObjectEnumerationBlock)block;

- (void)setTtlCache:(BOOL)ttlCache DEPRECATED_MSG_ATTRIBUTE("ttlCache is no longer a settable property and must now be set via initializer.");


@end

NS_ASSUME_NONNULL_END
