//
//  PINOperationQueue.h
//  Pods
//
//  Created by Garrett Moon on 8/23/16.
//
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, PINOperationQueuePriority) {
  PINOperationQueuePriorityLow,
  PINOperationQueuePriorityDefault,
  PINOperationQueuePriorityHigh,
};

@protocol PINOperationReference;

@interface PINOperationQueue : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithMaxConcurrentOperations:(NSUInteger)maxConcurrentOperations;
- (instancetype)initWithMaxConcurrentOperations:(NSUInteger)maxConcurrentOperations concurrentQueue:(dispatch_queue_t)concurrentQueue NS_DESIGNATED_INITIALIZER;
- (id <PINOperationReference>)addOperation:(dispatch_block_t)operation withPriority:(PINOperationQueuePriority)priority;
- (void)cancelOperation:(id <PINOperationReference>)operationReference;
- (void)setOperationPriority:(PINOperationQueuePriority)priority withReference:(id <PINOperationReference>)reference;

@end

@protocol PINOperationReference <NSObject>

@end

NS_ASSUME_NONNULL_END
