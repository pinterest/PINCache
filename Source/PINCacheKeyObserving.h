//
//  PINCacheKeyObserving.h
//  PINCache
//
//  Created by Rocir Santiago on 11/16/17.
//  Copyright © 2017 Pinterest. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@protocol PINCacheKeyObserving <NSObject>

@required

/**
 * Adds an observer for every time the value of a given key has been added, changed or removed from
 * the cache.
 *
 * @param observer The object that will act as the observer.
 * @param selector The callback for when a key/value is changed or removed.
 * @param key The key for which changes are being observed.
 */
- (void)addObserver:(id)observer selector:(SEL)selector forKey:(NSString *)key;

/**
 * Removes an object as an observer from key/value changes.
 *
 * @param observer The object to stop acting as an observer for a given key.
 * @param key The key to which the object shouldn't observe to changes anymore.
 */
- (void)removeObserver:(id)observer forKey:(NSString *)key;

@end

NS_ASSUME_NONNULL_END
