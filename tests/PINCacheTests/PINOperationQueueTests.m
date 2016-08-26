//
//  PINOperationQueueTests.m
//  PINCache
//
//  Created by Garrett Moon on 8/28/16.
//  Copyright © 2016 Pinterest. All rights reserved.
//

#import <XCTest/XCTest.h>

#import <pthread.h>

#import "PINCacheTests.h"
#import "PINOperationQueue.h"

@interface PINOperationQueueTests : XCTestCase

@property (nonatomic, strong) PINOperationQueue *queue;

@end

static const NSUInteger PINOperationQueueTestsMaxOperations = 5;

@implementation PINOperationQueueTests

- (void)setUp
{
  [super setUp];
  self.queue = [[PINOperationQueue alloc] initWithMaxConcurrentOperations:PINOperationQueueTestsMaxOperations];
  // Put setup code here. This method is called before the invocation of each test method in the class.
}

- (void)tearDown
{
  // Put teardown code here. This method is called after the invocation of each test method in the class.
  self.queue = nil;
  [super tearDown];
}

- (dispatch_time_t)timeout
{
  return dispatch_time(DISPATCH_TIME_NOW, (int64_t)(PINCacheTestBlockTimeout * NSEC_PER_SEC));
}

- (void)testAllOperationsRun
{
  const NSUInteger operationCount = 100;
  dispatch_group_t group = dispatch_group_create();
  
  for (NSUInteger count = 0; count < operationCount; count++) {
    dispatch_group_enter(group);
    [self.queue addOperation:^{
      dispatch_group_leave(group);
    } withPriority:PINOperationQueuePriorityDefault];
  }
  
  NSUInteger success = dispatch_group_wait(group, [self timeout]);
  XCTAssert(success == 0, @"Timed out before completing 100 operations");
}

- (void)testMaximumNumberOfConcurrentOperations
{
  const NSUInteger operationCount = 100;
  dispatch_group_t group = dispatch_group_create();
  
  __block NSUInteger runningOperationCount = 0;
  
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-retain-cycles"
  for (NSUInteger count = 0; count < operationCount; count++) {
    dispatch_group_enter(group);
    [self.queue addOperation:^{
      @synchronized (self) {
        runningOperationCount++;
        XCTAssert(runningOperationCount <= PINOperationQueueTestsMaxOperations, @"Running too many operations at once.");
      }
      
      usleep(1000);
      
      @synchronized (self) {
        runningOperationCount--;
        XCTAssert(runningOperationCount <= PINOperationQueueTestsMaxOperations, @"Running too many operations at once.");
      }
      
      dispatch_group_leave(group);
    } withPriority:PINOperationQueuePriorityDefault];
  }
#pragma clang diagnostic pop
  
  NSUInteger success = dispatch_group_wait(group, [self timeout]);
  XCTAssert(success == 0, @"Timed out before completing 100 operations");
}

//We expect operations to run in priority order when added in that order as well
- (void)testPriority
{
  const NSUInteger highOperationCount = 100;
  const NSUInteger defaultOperationCount = 100;
  const NSUInteger lowOperationCount = 100;
  
  __block NSUInteger highOperationComplete = 0;
  __block NSUInteger defaultOperationComplete = 0;
  __block NSUInteger lowOperationComplete = 0;
  
  dispatch_group_t group = dispatch_group_create();
  
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-retain-cycles"
  for (NSUInteger count = 0; count < highOperationCount; count++) {
    dispatch_group_enter(group);
    [self.queue addOperation:^{
      @synchronized (self) {
        ++highOperationComplete;
        XCTAssert(defaultOperationComplete < PINOperationQueueTestsMaxOperations, @"Running default operations before high");
        XCTAssert(lowOperationComplete < PINOperationQueueTestsMaxOperations, @"Running low operations before high");
      }
      dispatch_group_leave(group);
    } withPriority:PINOperationQueuePriorityHigh];
  }
  
  for (NSUInteger count = 0; count < defaultOperationCount; count++) {
    dispatch_group_enter(group);
    [self.queue addOperation:^{
      @synchronized (self) {
        ++defaultOperationComplete;
        XCTAssert(lowOperationComplete < PINOperationQueueTestsMaxOperations, @"Running low operations before default");
        XCTAssert(highOperationComplete > highOperationCount - PINOperationQueueTestsMaxOperations, @"Running high operations after default");
      }
      dispatch_group_leave(group);
    } withPriority:PINOperationQueuePriorityDefault];
  }
  
  for (NSUInteger count = 0; count < lowOperationCount; count++) {
    dispatch_group_enter(group);
    [self.queue addOperation:^{
      @synchronized (self) {
        ++lowOperationComplete;
        XCTAssert(defaultOperationComplete > defaultOperationCount - PINOperationQueueTestsMaxOperations, @"Running default operations after low");
        XCTAssert(highOperationComplete > highOperationCount - PINOperationQueueTestsMaxOperations, @"Running high operations after low");
      }
      dispatch_group_leave(group);
    } withPriority:PINOperationQueuePriorityLow];
  }
#pragma clang diagnostic pop
  
  NSUInteger success = dispatch_group_wait(group, [self timeout]);
  XCTAssert(success == 0, @"Timed out");
}

//We expect low priority operations to eventually run even if the queue is continually kept full with higher priority operations
- (void)testOutOfOrderOperations
{
  const NSUInteger operationCount = 100;
  dispatch_group_t group = dispatch_group_create();
  
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-retain-cycles"
  for (NSUInteger count = 0; count < PINOperationQueueTestsMaxOperations + 1; count++) {
    [self.queue addOperation:^{
      [self recursivelyAddOperation];
    } withPriority:PINOperationQueuePriorityHigh];
  }
#pragma clang diagnostic pop
  
  for (NSUInteger count = 0; count < operationCount; count++) {
    dispatch_group_enter(group);
    [self.queue addOperation:^{
      dispatch_group_leave(group);
    } withPriority:PINOperationQueuePriorityLow];
  }
  
  NSUInteger success = dispatch_group_wait(group, [self timeout]);
  XCTAssert(success == 0, @"Timed out");
}

- (void)recursivelyAddOperation
{
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-retain-cycles"
  [self.queue addOperation:^{
    [self recursivelyAddOperation];
  } withPriority:PINOperationQueuePriorityHigh];
#pragma clang diagnostic pop
}

@end
