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

- (void)testWaitUntilAllOperationsFinished
{
  const NSUInteger operationCount = 100;
  __block NSInteger runnedOperations = 0;;
  for (NSUInteger count = 0; count < operationCount; count++) {
    [self.queue addOperation:^{
      runnedOperations += 1;
    } withPriority:PINOperationQueuePriorityDefault];
  }
  
  //
  [self.queue waitUntilAllOperationsAreFinished];
  
  XCTAssert(operationCount == runnedOperations, @"Timed out before completing 100 operations");
}

- (void)testWaitUntilAllOperationsFinishedWithNestedOperations
{
  const NSUInteger operationCount = 100;
    
  __block NSInteger runnedOperations = 0;;
  for (NSUInteger count = 0; count < operationCount; count++) {
    __weak PINOperationQueueTests *weakSelf = self;
    [self.queue addOperation:^{
      __strong PINOperationQueueTests *strongSelf = weakSelf;
      runnedOperations += 1;
      [strongSelf.queue addOperation:^{
          runnedOperations += 1;
      } withPriority:PINOperationQueuePriorityHigh];
    } withPriority:PINOperationQueuePriorityDefault];
  }

  //
  [self.queue waitUntilAllOperationsAreFinished];

  XCTAssert(runnedOperations == (operationCount*2), @"Timed out before completing 100 operations");
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
  
  //This is actually a pretty annoying unit test to write. Because multiple operations are allowed to be concurrent, lower priority operations can potentially repeatidly
  //obtain the lock while higher priority operations wait… So I'm attempting to make the operations less about lock contention and more about the length of time they take
  //to execute and adding a sleep before they obtain the lock to hopefully improve reliability.
  
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-retain-cycles"
  for (NSUInteger count = 0; count < highOperationCount; count++) {
    dispatch_group_enter(group);
    [self.queue addOperation:^{
      usleep(10000);
      @synchronized (self) {
        ++highOperationComplete;
        XCTAssert(defaultOperationComplete <= PINOperationQueueTestsMaxOperations, @"Running default operations before high. Default operations complete: %lu", (unsigned long)defaultOperationComplete);
        XCTAssert(lowOperationComplete <= PINOperationQueueTestsMaxOperations, @"Running low operations before high. Low operations complete: %lu", (unsigned long)lowOperationComplete);
      }
      dispatch_group_leave(group);
    } withPriority:PINOperationQueuePriorityHigh];
  }
  
  for (NSUInteger count = 0; count < defaultOperationCount; count++) {
    dispatch_group_enter(group);
    [self.queue addOperation:^{
      usleep(10000);
      @synchronized (self) {
        ++defaultOperationComplete;
        XCTAssert(lowOperationComplete <= PINOperationQueueTestsMaxOperations, @"Running low operations before default. Low operations complete: %lu", (unsigned long)lowOperationComplete);
        XCTAssert(highOperationComplete > highOperationCount - PINOperationQueueTestsMaxOperations, @"Running high operations after default. High operations complete: %lu", (unsigned long)highOperationComplete);
      }
      dispatch_group_leave(group);
    } withPriority:PINOperationQueuePriorityDefault];
  }
  
  for (NSUInteger count = 0; count < lowOperationCount; count++) {
    dispatch_group_enter(group);
    [self.queue addOperation:^{
      usleep(10000);
      @synchronized (self) {
        ++lowOperationComplete;
        XCTAssert(defaultOperationComplete > defaultOperationCount - PINOperationQueueTestsMaxOperations, @"Running default operations after low. Default operations complete: %lu", (unsigned long)defaultOperationComplete);
        XCTAssert(highOperationComplete > highOperationCount - PINOperationQueueTestsMaxOperations, @"Running high operations after low. High operations complete: %lu", (unsigned long)highOperationComplete);
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

- (void)testCancelation
{
  const NSUInteger sleepTime = 100000;
  for (NSUInteger count = 0; count < PINOperationQueueTestsMaxOperations + 1; count++) {
    [self.queue addOperation:^{
      usleep(sleepTime);
    } withPriority:PINOperationQueuePriorityDefault];
  }
  
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-retain-cycles"
  id <PINOperationReference> operation = [self.queue addOperation:^{
    XCTAssertTrue(NO, @"operation should have been canceled");
  } withPriority:PINOperationQueuePriorityDefault];
#pragma clang diagnostics pop
  
  [self.queue cancelOperation:operation];
  
  usleep(sleepTime * (PINOperationQueueTestsMaxOperations + 1));
}

- (void)testChangingPriority
{
  const NSUInteger defaultOperationCount = 100;
  
  __block NSUInteger defaultOperationComplete = 0;
  
  dispatch_group_t group = dispatch_group_create();
  
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-retain-cycles"
  for (NSUInteger count = 0; count < defaultOperationCount; count++) {
    dispatch_group_enter(group);
    [self.queue addOperation:^{
      usleep(100);
      @synchronized (self) {
        ++defaultOperationComplete;
      }
      dispatch_group_leave(group);
    } withPriority:PINOperationQueuePriorityDefault];
  }
  
  dispatch_group_enter(group);
  id <PINOperationReference> operation = [self.queue addOperation:^{
    @synchronized (self) {
      //Make sure we're less than defaultOperationCount - PINOperationQueueTestsMaxOperations because this operation could start even while the others are running even
      //if started last.
      XCTAssert(defaultOperationComplete < defaultOperationCount - PINOperationQueueTestsMaxOperations, @"operation was not completed before default operations even though reprioritized.");
    }
    dispatch_group_leave(group);
  } withPriority:PINOperationQueuePriorityLow];
#pragma clang diagnostic pop
  [self.queue setOperationPriority:PINOperationQueuePriorityHigh withReference:operation];
  
  NSUInteger success = dispatch_group_wait(group, [self timeout]);
  XCTAssert(success == 0, @"Timed out");
}

@end
