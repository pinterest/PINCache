//
//  PINApplicationBackgroundTask.m
//  PINCache
//
//  Created by Ben Asher on 2/11/16.
//  Copyright © 2016 Pinterest. All rights reserved.
//

#if !TARGET_OS_WATCH
#if __IPHONE_OS_VERSION_MIN_REQUIRED >= __IPHONE_4_0
#import <UIKit/UIKit.h>
#endif

#import "PINApplicationBackgroundTask.h"

@interface PINApplicationBackgroundTask ()

#if __IPHONE_OS_VERSION_MIN_REQUIRED >= __IPHONE_4_0
@property (atomic, assign) UIBackgroundTaskIdentifier taskID;
#endif

@end

@implementation PINApplicationBackgroundTask

- (instancetype)init
{
  if (self = [super init]) {
#if __IPHONE_OS_VERSION_MIN_REQUIRED >= __IPHONE_4_0
    _taskID = UIBackgroundTaskInvalid;
#endif
  }
  return self;
}

+ (instancetype)start
{
  PINApplicationBackgroundTask *task = [[self alloc] init];
#if __IPHONE_OS_VERSION_MIN_REQUIRED >= __IPHONE_4_0
  // We have to declare this reference outside of the block, otherwise, the compiler complains about using [UIApplication sharedApplication] in a context that might be available from an extension
  UIApplication *sharedApplication = [UIApplication sharedApplication];
  task.taskID = [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:^{
    UIBackgroundTaskIdentifier taskID = task.taskID;
    task.taskID = UIBackgroundTaskInvalid;
    [sharedApplication endBackgroundTask:taskID];
  }];
#endif
  return task;
}

- (void)end
{
#if __IPHONE_OS_VERSION_MIN_REQUIRED >= __IPHONE_4_0
  UIBackgroundTaskIdentifier taskID = self.taskID;
  self.taskID = UIBackgroundTaskInvalid;
  [[UIApplication sharedApplication] endBackgroundTask:taskID];
#endif
}

@end
#endif