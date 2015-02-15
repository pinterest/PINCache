//  PINCache is a modified version of TMCache
//  Modifications by Garrett Moon
//  Copyright (c) 2015 Pinterest. All rights reserved.

#import "PINAppDelegate.h"
#import "PINCache.h"
#import "PINExampleView.h"

@implementation PINAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    self.window.rootViewController = [[UIViewController alloc] initWithNibName:nil bundle:nil];
    
    PINExampleView *view = [[PINExampleView alloc] initWithFrame:self.window.rootViewController.view.bounds];
    view.imageURL = [[NSURL alloc] initWithString:@"http://upload.wikimedia.org/wikipedia/commons/6/62/Sts114_033.jpg"];
    view.contentMode = UIViewContentModeScaleAspectFill;
    
    [self.window.rootViewController.view addSubview:view];
    [self.window makeKeyAndVisible];
    
    return YES;
}

@end
