//
//  PINCacheConfigurationInternal.m
//  PINCache
//
//  Created by Vladimir Solomenchuk on 3/19/20.
//  Copyright © 2020 Pinterest. All rights reserved.
//

#import "PINCacheConfigurationInternal.h"

@interface PINCacheConfiguration(PINCacheConfiguration)
+ (PINCacheExperimentalFeatures) defaultConfiguration;
@end

@implementation PINCacheConfiguration
+ (PINCacheExperimentalFeatures) defaultConfiguration {
    return PINCacheExperimentalFeaturesNone;
}
@end


static PINCacheConfigurationManager *PINCacheSharedConfigurationManager;
static dispatch_once_t PINCacheSharedConfigurationManagerOnceToken;

NS_INLINE PINCacheConfigurationManager *PINCacheConfigurationManagerGet() {
  dispatch_once(&PINCacheSharedConfigurationManagerOnceToken, ^{
    PINCacheSharedConfigurationManager = [[PINCacheConfigurationManager alloc] init];
  });
  return PINCacheSharedConfigurationManager;
}

@implementation PINCacheConfigurationManager {
  _Atomic(PINCacheExperimentalFeatures) _activatedExperiments;
}

- (instancetype)init
{
  if (self = [super init]) {
    if ([PINCacheConfiguration respondsToSelector:@selector(cacheConfiguration)]) {
      _activatedExperiments = [PINCacheConfiguration cacheConfiguration];
    } else {
      _activatedExperiments = [PINCacheConfiguration defaultConfiguration];
    }
  }
  return self;
}

- (BOOL)activateExperimentalFeature:(PINCacheExperimentalFeatures)requested
{
   PINCacheExperimentalFeatures enabled = requested & _activatedExperiments;
  
  return (enabled != 0);
}

+ (void) test_resetWithConfiguration:(PINCacheExperimentalFeatures) features {
    PINCacheConfigurationManager *inst = PINCacheConfigurationManagerGet();
    inst->_activatedExperiments = features;
}
@end

BOOL PINCacheHasActiveExperimentalFeature(PINCacheExperimentalFeatures feature){
    return [PINCacheConfigurationManagerGet() activateExperimentalFeature:feature];
}
