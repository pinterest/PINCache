//
//  PINBackgroundTask.h
//  PINCache
//
//  Created by Ben Asher on 2/11/16.
//  Copyright © 2016 Pinterest. All rights reserved.
//

//! Protocol to abstract background tasks across different platforms
@protocol PINBackgroundTask <NSObject>

/**
 Starts and returns a new background task instance.
 */
+ (instancetype)start;
/**
 Ends the in-progress background task.
 */
- (void)end;

@end
