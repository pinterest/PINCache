//
//  PINApplicationBackgroundTask.h
//  PINCache
//
//  Created by Ben Asher on 2/11/16.
//  Copyright © 2016 Pinterest. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <Availability.h>
#import "PINBackgroundTask.h"

#if !TARGET_OS_WATCH
NS_EXTENSION_UNAVAILABLE_IOS("This is a concrete PINBackgroundTask that depends on UIApplication, which cannot be used in extensions")
@interface PINApplicationBackgroundTask : NSObject <PINBackgroundTask>

@end
#endif
