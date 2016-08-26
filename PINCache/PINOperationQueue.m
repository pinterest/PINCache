//
//  PINOperationQueue.m
//  Pods
//
//  Created by Garrett Moon on 8/23/16.
//
//

#import "PINOperationQueue.h"
#import <pthread.h>

@interface NSNumber (PINOperationQueue) <PINOperationReference>

@end

@interface PINOperationQueue () {
  pthread_mutex_t _lock;
  //increments with every operation to allow cancelation
  NSUInteger _operationReferenceCount;
  
  dispatch_queue_t _serialQueue;
  BOOL _serialQueueBusy;
  
  dispatch_semaphore_t _concurrentSemaphore;
  dispatch_queue_t _concurrentQueue;
  dispatch_queue_t _semaphoreQueue;
  
  NSMutableOrderedSet *_allOperations;
  NSMutableOrderedSet *_lowPriorityOperations;
  NSMutableOrderedSet *_defaultPriorityOperations;
  NSMutableOrderedSet *_highPriorityOperations;
  
  NSHashTable *_canceledOperations;
}

@end

@interface PINOperation : NSObject

@property (nonatomic, strong) dispatch_block_t block;
@property (nonatomic, strong) id <PINOperationReference> reference;

+ (instancetype)operationWithBlock:(dispatch_block_t)block reference:(id <PINOperationReference>)reference;

@end

@implementation PINOperation

+ (instancetype)operationWithBlock:(dispatch_block_t)block reference:(id<PINOperationReference>)reference
{
  PINOperation *operation = [[self alloc] init];
  operation.block = block;
  operation.reference = reference;

  return operation;
}

@end

@implementation PINOperationQueue

- (instancetype)initWithMaxConcurrentOperations:(NSUInteger)maxConcurrentOperations
{
  if (self = [super init]) {
    NSAssert(maxConcurrentOperations > 1, @"Max concurrent operations must be greater than 1. If it's one, just use a serial queue!");
    _operationReferenceCount = 0;
    
    pthread_mutexattr_t attr;
    pthread_mutexattr_init(&attr);
    pthread_mutexattr_settype(&attr, PTHREAD_MUTEX_RECURSIVE);
    pthread_mutex_init(&_lock, &attr);
    
    _serialQueue = dispatch_queue_create("PINOperationQueue Serial Queue", DISPATCH_QUEUE_SERIAL);
    
    _concurrentQueue = dispatch_queue_create("PINOperationQueue Unprioritized Serial Queue", DISPATCH_QUEUE_CONCURRENT);
    _concurrentSemaphore = dispatch_semaphore_create(maxConcurrentOperations - 1);
    _semaphoreQueue = dispatch_queue_create("PINOperationQueue Serial Semaphore Queue", DISPATCH_QUEUE_SERIAL);
    
    _allOperations = [[NSMutableOrderedSet alloc] init];
    _lowPriorityOperations = [[NSMutableOrderedSet alloc] init];
    _defaultPriorityOperations = [[NSMutableOrderedSet alloc] init];
    _highPriorityOperations = [[NSMutableOrderedSet alloc] init];
  }
  return self;
}

- (void)dealloc
{
  pthread_mutex_destroy(&_lock);
}

- (id <PINOperationReference>)nextOperationReference
{
  [self lock];
    id <PINOperationReference> reference = [NSNumber numberWithUnsignedInteger:++_operationReferenceCount];
  [self unlock];
  return reference;
}

- (id <PINOperationReference>)addOperation:(dispatch_block_t)block withPriority:(PINOperationQueuePriority)priority
{
  id <PINOperationReference> reference = [self nextOperationReference];
  
  NSMutableOrderedSet *queue;
  switch (priority) {
    case PINOperationQueuePriorityLow:
      queue = _lowPriorityOperations;
      break;
      
    case PINOperationQueuePriorityDefault:
      queue = _defaultPriorityOperations;
      break;
      
    case PINOperationQueuePriorityHigh:
      queue = _highPriorityOperations;
  }
  
  PINOperation *operation = [PINOperation operationWithBlock:block reference:reference];
  
  [self lock];
    [queue addObject:operation];
    [_allOperations addObject:operation];
  [self unlock];
  
  [self scheduleOperations:NO];
  
  return reference;
}

- (void)cancelOperation:(id <PINOperationReference>)operationReference
{
  [self lock];
    [_canceledOperations addObject:operationReference];
  [self unlock];
}

- (void)scheduleOperations:(BOOL)onlyCheckSerial
{
  [self lock];
    //get next available operation in order, ignoring priority and run it on the serial queue
    if (_serialQueueBusy == NO) {
      PINOperation *operation = [_allOperations firstObject];
      if (operation) {
        _serialQueueBusy = YES;
        [self removeOperation:operation];
        dispatch_async(_serialQueue, ^{
          operation.block();
          [self lock];
            _serialQueueBusy = NO;
          [self unlock];
          
          //see if there are any other operations
          [self scheduleOperations:YES];
        });
      }
    }
  [self unlock];
  
  if (onlyCheckSerial) {
    return;
  }
  
  dispatch_async(_semaphoreQueue, ^{
      dispatch_semaphore_wait(_concurrentSemaphore, DISPATCH_TIME_FOREVER);
      [self lock];
        PINOperation *operation = [self nextOperationByPriority];
        [self removeOperation:operation];
      [self unlock];
    
      if (operation) {
        dispatch_async(_concurrentQueue, ^{
          operation.block();
          dispatch_semaphore_signal(_concurrentSemaphore);
        });
      } else {
        dispatch_semaphore_signal(_concurrentSemaphore);
      }
  });
}

//Call with lock held
- (PINOperation *)nextOperationByPriority
{
  PINOperation *operation = [_highPriorityOperations firstObject];
  if (operation) {
    return operation;
  }
  operation = [_defaultPriorityOperations firstObject];
  if (operation) {
    return operation;
  }
  operation = [_lowPriorityOperations firstObject];
  return operation;
}

//Call with lock held
- (void)removeOperation:(PINOperation *)operation
{
  if (operation) {
    [_allOperations removeObject:operation];
    [_lowPriorityOperations removeObject:operation];
    [_defaultPriorityOperations removeObject:operation];
    [_highPriorityOperations removeObject:operation];
  }
}

- (void)lock
{
  pthread_mutex_lock(&_lock);
}

- (void)unlock
{
  pthread_mutex_unlock(&_lock);
}

@end
