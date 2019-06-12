//
//  PINPurgeableMemoryCache.h
//  PINCache
//
//  Created by Rahul Malik on 6/12/19.
//  Copyright © 2019 Pinterest. All rights reserved.
//

#import <Foundation/Foundation.h>

#import <PINCache/PINMemoryCaching.h>

NS_ASSUME_NONNULL_BEGIN

@class PINOperationQueue;

@interface PINPurgeableMemoryCache : NSObject<PINMemoryCaching>
- (instancetype)initWithOperationQueue:(PINOperationQueue *)operationQueue;
- (instancetype)initWithName:(NSString *)name operationQueue:(PINOperationQueue *)operationQueue;
@end

NS_ASSUME_NONNULL_END
