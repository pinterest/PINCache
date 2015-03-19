//
//  nullability.h
//  PINCache
//
//  Created by CHEN Xian’an on 3/19/15.
//  Copyright (c) 2015 Tumblr. All rights reserved.
//

#ifndef PINCache_nullability_h
#define PINCache_nullability_h

#if !__has_feature(nullability)
#define NS_ASSUME_NONNULL_BEGIN
#define NS_ASSUME_NONNULL_END
#define nullable
#define nonnull
#define null_unspecified
#define null_resettable
#define __nullable
#define __nonnull
#define __null_unspecified
#endif

#endif
