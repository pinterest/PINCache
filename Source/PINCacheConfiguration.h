//
//  PINCacheConfiguration.h
//  PINCache
//
//  Created by Vladimir Solomenchuk on 3/19/20.
//  Copyright © 2020 Pinterest. All rights reserved.
//

#import <Foundation/Foundation.h>

/**
 * A bit mask of features.
 */
typedef NS_OPTIONS(NSUInteger, PINCacheExperimentalFeatures) {
    PINCacheExperimentalFeaturesNone,
    PINCacheExperimentalFeaturesAll = 0xFFFFFFFF
};

@interface PINCacheConfiguration: NSObject
@end

/**
 * Implement this method in a category to make your
 * configuration available to PINCache. It will be read
 * only once and copied.
 */
@interface PINCacheConfiguration (UserProvided)
+ (PINCacheExperimentalFeatures)cacheConfiguration;
@end
