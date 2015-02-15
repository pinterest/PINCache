//  PINCache is a modified version of TMCache
//  Modifications by Garrett Moon
//  Copyright (c) 2015 Pinterest. All rights reserved.

#import "PINExampleView.h"
#import "PINCache.h"

@implementation PINExampleView

- (void)setImageURL:(NSURL *)url
{
    _imageURL = url;

    [[PINCache sharedCache] objectForKey:[url absoluteString]
                                  block:^(PINCache *cache, NSString *key, id object) {
                                      if (object) {
                                          [self setImageOnMainThread:(UIImage *)object];
                                          return;
                                      }
                                    
                                      NSLog(@"cache miss, requesting %@", url);
                                      
                                      NSURLResponse *response = nil;
                                      NSURLRequest *request = [NSURLRequest requestWithURL:url];
                                      NSData *data = [NSURLConnection sendSynchronousRequest:request returningResponse:&response error:nil];
                                      
                                      UIImage *image = [[UIImage alloc] initWithData:data scale:[[UIScreen mainScreen] scale]];
                                      [self setImageOnMainThread:image];

                                      [[PINCache sharedCache] setObject:image forKey:[url absoluteString]];
    }];   
}

- (void)setImageOnMainThread:(UIImage *)image
{
    if (!image)
        return;
    
    NSLog(@"setting view image %@", NSStringFromCGSize(image.size));

    dispatch_async(dispatch_get_main_queue(), ^{
        self.image = image;
    });
}

@end
