//
//  PINCacheConfigurationInternal.h
//  PINCache
//
//  Created by Vladimir Solomenchuk on 3/19/20.
//  Copyright © 2020 Pinterest. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "PINCacheConfiguration.h"

extern BOOL PINCacheHasActiveExperimentalFeature(PINCacheExperimentalFeatures option);

@interface PINCacheConfigurationManager : NSObject
// only for tests
+ (void) test_resetWithConfiguration:(PINCacheExperimentalFeatures) features;
@end
