//
//  PINOperationQueue.h
//  Pods
//
//  Created by Garrett Moon on 8/23/16.
//
//

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSUInteger, PINOperationQueuePriority) {
  PINOperationQueuePriorityLow,
  PINOperationQueuePriorityDefault,
  PINOperationQueuePriorityHigh,
};

@protocol PINOperationReference;

@interface PINOperationQueue : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithMaxConcurrentOperations:(NSUInteger)maxConcurrentOperations NS_DESIGNATED_INITIALIZER;
- (id <PINOperationReference>)addOperation:(dispatch_block_t)operation withPriority:(PINOperationQueuePriority)priority;
- (void)cancelOperation:(id <PINOperationReference>)operationReference;

@end

@protocol PINOperationReference <NSObject>

@end
