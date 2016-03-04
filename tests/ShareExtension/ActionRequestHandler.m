//
//  ActionRequestHandler.m
//  ShareExtension
//
//  Created by Michael Schneider on 3/3/16.
//  Copyright © 2016 Pinterest. All rights reserved.
//

#import "ActionRequestHandler.h"
#import <MobileCoreServices/MobileCoreServices.h>
#import "PINCache.h"

@interface ActionRequestHandler ()

@property (nonatomic, strong) NSExtensionContext *extensionContext;

@end

@implementation ActionRequestHandler

- (void)beginRequestWithExtensionContext:(NSExtensionContext *)context {
    // Do not call super in an Action extension with no user interface
    self.extensionContext = context;
    
    BOOL found = NO;
    
    // Find the item containing the results from the JavaScript preprocessing.
    for (NSExtensionItem *item in self.extensionContext.inputItems) {
        for (NSItemProvider *itemProvider in item.attachments) {
            if ([itemProvider hasItemConformingToTypeIdentifier:(NSString *)kUTTypePropertyList]) {
                [itemProvider loadItemForTypeIdentifier:(NSString *)kUTTypePropertyList options:nil completionHandler:^(NSDictionary *dictionary, NSError *error) {
                    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                        [self itemLoadCompletedWithPreprocessingResults:dictionary[NSExtensionJavaScriptPreprocessingResultsKey]];
                    }];
                }];
                found = YES;
            }
            break;
        }
        if (found) {
            break;
        }
    }
    
    if (!found) {
        // We did not find anything
        [self doneWithResults:nil];
    }
}

- (void)itemLoadCompletedWithPreprocessingResults:(NSDictionary *)javaScriptPreprocessingResults {
    // Here, do something, potentially asynchronously, with the preprocessing
    // results.
    
    // Test PINCache usage in extension
    PINCache *cache = [[PINCache alloc] initWithName:[[NSUUID UUID] UUIDString]];
    // Call trimToDate that uses a background task but in an extension context not really do anything
    [cache trimToDate:[NSDate date]];
    
    // In this very simple example, the JavaScript will have passed us the
    // current background color style, if there is one. We will construct a
    // dictionary to send back with a desired new background color style.
    if ([javaScriptPreprocessingResults[@"currentBackgroundColor"] length] == 0) {
        // No specific background color? Request setting the background to red.
        [self doneWithResults:@{ @"newBackgroundColor": @"red" }];
    } else {
        // Specific background color is set? Request replacing it with green.
        [self doneWithResults:@{ @"newBackgroundColor": @"green" }];
    }
}

- (void)doneWithResults:(NSDictionary *)resultsForJavaScriptFinalize {
    if (resultsForJavaScriptFinalize) {
        // Construct an NSExtensionItem of the appropriate type to return our
        // results dictionary in.
        
        // These will be used as the arguments to the JavaScript finalize()
        // method.
        
        NSDictionary *resultsDictionary = @{ NSExtensionJavaScriptFinalizeArgumentKey: resultsForJavaScriptFinalize };
        
        NSItemProvider *resultsProvider = [[NSItemProvider alloc] initWithItem:resultsDictionary typeIdentifier:(NSString *)kUTTypePropertyList];
        
        NSExtensionItem *resultsItem = [[NSExtensionItem alloc] init];
        resultsItem.attachments = @[resultsProvider];
        
        // Signal that we're complete, returning our results.
        [self.extensionContext completeRequestReturningItems:@[resultsItem] completionHandler:nil];
    } else {
        // We still need to signal that we're done even if we have nothing to
        // pass back.
        [self.extensionContext completeRequestReturningItems:@[] completionHandler:nil];
    }
    
    // Don't hold on to this after we finished with it.
    self.extensionContext = nil;
}

@end
