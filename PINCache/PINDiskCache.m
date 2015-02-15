//  PINCache is a modified version of TMCache
//  Modifications by Garrett Moon
//  Copyright (c) 2015 Pinterest. All rights reserved.

#import "PINDiskCache.h"

#if __IPHONE_OS_VERSION_MIN_REQUIRED >= __IPHONE_4_0
#import <UIKit/UIKit.h>
#endif

#define PINDiskCacheError(error) if (error) { NSLog(@"%@ (%d) ERROR: %@", \
[[NSString stringWithUTF8String:__FILE__] lastPathComponent], \
__LINE__, [error localizedDescription]); }

#if __IPHONE_OS_VERSION_MIN_REQUIRED >= __IPHONE_4_0
#define PINCacheStartBackgroundTask() UIBackgroundTaskIdentifier taskID = UIBackgroundTaskInvalid; \
taskID = [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:^{ \
[[UIApplication sharedApplication] endBackgroundTask:taskID]; }];
#define PINCacheEndBackgroundTask() [[UIApplication sharedApplication] endBackgroundTask:taskID];
#else
#define PINCacheStartBackgroundTask()
#define PINCacheEndBackgroundTask()
#endif

NSString * const PINDiskCachePrefix = @"com.tumblr.PINDiskCache";
NSString * const PINDiskCacheSharedName = @"PINDiskCacheShared";

@interface PINDiskCache () {
    PINDiskCacheObjectBlock _willAddObjectBlock;
    PINDiskCacheObjectBlock _willRemoveObjectBlock;
    PINDiskCacheBlock _willRemoveAllObjectsBlock;
    PINDiskCacheObjectBlock _didAddObjectBlock;
    PINDiskCacheObjectBlock _didRemoveObjectBlock;
    PINDiskCacheBlock _didRemoveAllObjectsBlock;
    NSUInteger _byteLimit;
    NSTimeInterval _ageLimit;
}
@property (assign) NSUInteger byteCount;
@property (strong, nonatomic) NSURL *cacheURL;
@property (assign, nonatomic) dispatch_queue_t queue;
@property (strong, nonatomic) NSMutableDictionary *dates;
@property (strong, nonatomic) NSMutableDictionary *sizes;
@end

@implementation PINDiskCache

#pragma mark - Initialization -

- (instancetype)initWithName:(NSString *)name
{
    return [self initWithName:name rootPath:[NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) firstObject]];
}

- (instancetype)initWithName:(NSString *)name rootPath:(NSString *)rootPath
{
    if (!name)
        return nil;
    
    if (self = [super init]) {
        _name = [name copy];
        _queue = [PINDiskCache sharedQueue];
        
        _willAddObjectBlock = nil;
        _willRemoveObjectBlock = nil;
        _willRemoveAllObjectsBlock = nil;
        _didAddObjectBlock = nil;
        _didRemoveObjectBlock = nil;
        _didRemoveAllObjectsBlock = nil;
        
        _byteCount = 0;
        _byteLimit = 0;
        _ageLimit = 0.0;
        
        _dates = [[NSMutableDictionary alloc] init];
        _sizes = [[NSMutableDictionary alloc] init];
        
        NSString *pathComponent = [[NSString alloc] initWithFormat:@"%@.%@", PINDiskCachePrefix, _name];
        _cacheURL = [NSURL fileURLWithPathComponents:@[ rootPath, pathComponent ]];
        
        __weak PINDiskCache *weakSelf = self;
        
        dispatch_async(_queue, ^{
            PINDiskCache *strongSelf = weakSelf;
            [strongSelf createCacheDirectory];
            [strongSelf initializeDiskProperties];
        });
    }
    return self;
}

- (NSString *)description
{
    return [[NSString alloc] initWithFormat:@"%@.%@.%p", PINDiskCachePrefix, _name, self];
}

+ (instancetype)sharedCache
{
    static id cache;
    static dispatch_once_t predicate;
    
    dispatch_once(&predicate, ^{
        cache = [[self alloc] initWithName:PINDiskCacheSharedName];
    });
    
    return cache;
}

+ (dispatch_queue_t)sharedQueue
{
    static dispatch_queue_t queue;
    static dispatch_once_t predicate;
    
    dispatch_once(&predicate, ^{
        queue = dispatch_queue_create([PINDiskCachePrefix UTF8String], DISPATCH_QUEUE_SERIAL);
    });
    
    return queue;
}

#pragma mark - Private Methods -

- (NSURL *)encodedFileURLForKey:(NSString *)key
{
    if (![key length])
        return nil;
    
    return [_cacheURL URLByAppendingPathComponent:[self encodedString:key]];
}

- (NSString *)keyForEncodedFileURL:(NSURL *)url
{
    NSString *fileName = [url lastPathComponent];
    if (!fileName)
        return nil;
    
    return [self decodedString:fileName];
}

- (NSString *)encodedString:(NSString *)string
{
    if (![string length])
        return @"";
    
    CFStringRef static const charsToEscape = CFSTR(".:/");
    CFStringRef escapedString = CFURLCreateStringByAddingPercentEscapes(kCFAllocatorDefault,
                                                                        (__bridge CFStringRef)string,
                                                                        NULL,
                                                                        charsToEscape,
                                                                        kCFStringEncodingUTF8);
    return (__bridge_transfer NSString *)escapedString;
}

- (NSString *)decodedString:(NSString *)string
{
    if (![string length])
        return @"";
    
    CFStringRef unescapedString = CFURLCreateStringByReplacingPercentEscapesUsingEncoding(kCFAllocatorDefault,
                                                                                          (__bridge CFStringRef)string,
                                                                                          CFSTR(""),
                                                                                          kCFStringEncodingUTF8);
    return (__bridge_transfer NSString *)unescapedString;
}

#pragma mark - Private Trash Methods -

+ (dispatch_queue_t)sharedTrashQueue
{
    static dispatch_queue_t trashQueue;
    static dispatch_once_t predicate;
    
    dispatch_once(&predicate, ^{
        NSString *queueName = [[NSString alloc] initWithFormat:@"%@.trash", PINDiskCachePrefix];
        trashQueue = dispatch_queue_create([queueName UTF8String], DISPATCH_QUEUE_SERIAL);
        dispatch_set_target_queue(trashQueue, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0));
    });
    
    return trashQueue;
}

+ (NSURL *)sharedTrashURL
{
    static NSURL *sharedTrashURL;
    static dispatch_once_t predicate;
    
    dispatch_once(&predicate, ^{
        sharedTrashURL = [[[NSURL alloc] initFileURLWithPath:NSTemporaryDirectory()] URLByAppendingPathComponent:PINDiskCachePrefix isDirectory:YES];
        
        if (![[NSFileManager defaultManager] fileExistsAtPath:[sharedTrashURL path]]) {
            NSError *error = nil;
            [[NSFileManager defaultManager] createDirectoryAtURL:sharedTrashURL
                                     withIntermediateDirectories:YES
                                                      attributes:nil
                                                           error:&error];
            PINDiskCacheError(error);
        }
    });
    
    return sharedTrashURL;
}

+(BOOL)moveItemAtURLToTrash:(NSURL *)itemURL
{
    if (![[NSFileManager defaultManager] fileExistsAtPath:[itemURL path]])
        return NO;
    
    NSError *error = nil;
    NSString *uniqueString = [[NSProcessInfo processInfo] globallyUniqueString];
    NSURL *uniqueTrashURL = [[PINDiskCache sharedTrashURL] URLByAppendingPathComponent:uniqueString];
    BOOL moved = [[NSFileManager defaultManager] moveItemAtURL:itemURL toURL:uniqueTrashURL error:&error];
    PINDiskCacheError(error);
    return moved;
}

+ (void)emptyTrash
{
    PINCacheStartBackgroundTask();
    
    dispatch_async([self sharedTrashQueue], ^{
        NSError *error = nil;
        NSArray *trashedItems = [[NSFileManager defaultManager] contentsOfDirectoryAtURL:[self sharedTrashURL]
                                                              includingPropertiesForKeys:nil
                                                                                 options:0
                                                                                   error:&error];
        PINDiskCacheError(error);
        
        for (NSURL *trashedItemURL in trashedItems) {
            NSError *error = nil;
            [[NSFileManager defaultManager] removeItemAtURL:trashedItemURL error:&error];
            PINDiskCacheError(error);
        }
        
        PINCacheEndBackgroundTask();
    });
}

#pragma mark - Private Queue Methods -

- (BOOL)createCacheDirectory
{
    if ([[NSFileManager defaultManager] fileExistsAtPath:[_cacheURL path]])
        return NO;
    
    NSError *error = nil;
    BOOL success = [[NSFileManager defaultManager] createDirectoryAtURL:_cacheURL
                                            withIntermediateDirectories:YES
                                                             attributes:nil
                                                                  error:&error];
    PINDiskCacheError(error);
    
    return success;
}

- (void)initializeDiskProperties
{
    NSUInteger byteCount = 0;
    NSArray *keys = @[ NSURLContentModificationDateKey, NSURLTotalFileAllocatedSizeKey ];
    
    NSError *error = nil;
    NSArray *files = [[NSFileManager defaultManager] contentsOfDirectoryAtURL:_cacheURL
                                                   includingPropertiesForKeys:keys
                                                                      options:NSDirectoryEnumerationSkipsHiddenFiles
                                                                        error:&error];
    PINDiskCacheError(error);
    
    for (NSURL *fileURL in files) {
        NSString *key = [self keyForEncodedFileURL:fileURL];
        
        error = nil;
        NSDictionary *dictionary = [fileURL resourceValuesForKeys:keys error:&error];
        PINDiskCacheError(error);
        
        NSDate *date = dictionary[NSURLContentModificationDateKey];
        if (date && key)
            _dates[key] = date;
        
        NSNumber *fileSize = dictionary[NSURLTotalFileAllocatedSizeKey];
        if (fileSize) {
            _sizes[key] = fileSize;
            byteCount += [fileSize unsignedIntegerValue];
        }
    }
    
    if (byteCount > 0)
        self.byteCount = byteCount; // atomic
}

- (BOOL)setFileModificationDate:(NSDate *)date forURL:(NSURL *)fileURL
{
    if (!date || !fileURL) {
        return NO;
    }
    
    NSError *error = nil;
    BOOL success = [[NSFileManager defaultManager] setAttributes:@{ NSFileModificationDate: date }
                                                    ofItemAtPath:[fileURL path]
                                                           error:&error];
    PINDiskCacheError(error);
    
    if (success) {
        NSString *key = [self keyForEncodedFileURL:fileURL];
        if (key) {
            _dates[key] = date;
        }
    }
    
    return success;
}

- (BOOL)removeFileAndExecuteBlocksForKey:(NSString *)key
{
    NSURL *fileURL = [self encodedFileURLForKey:key];
    if (!fileURL || ![[NSFileManager defaultManager] fileExistsAtPath:[fileURL path]])
        return NO;
    
    if (_willRemoveObjectBlock)
        _willRemoveObjectBlock(self, key, nil, fileURL);
    
    BOOL trashed = [PINDiskCache moveItemAtURLToTrash:fileURL];
    if (!trashed)
        return NO;
    
    [PINDiskCache emptyTrash];
    
    NSNumber *byteSize = _sizes[key];
    if (byteSize)
        self.byteCount = _byteCount - [byteSize unsignedIntegerValue]; // atomic
    
    [_sizes removeObjectForKey:key];
    [_dates removeObjectForKey:key];
    
    if (_didRemoveObjectBlock)
        _didRemoveObjectBlock(self, key, nil, fileURL);
    
    return YES;
}

- (void)trimDiskToSize:(NSUInteger)trimByteCount
{
    if (_byteCount <= trimByteCount)
        return;
    
    NSArray *keysSortedBySize = [_sizes keysSortedByValueUsingSelector:@selector(compare:)];
    
    for (NSString *key in [keysSortedBySize reverseObjectEnumerator]) { // largest objects first
        [self removeFileAndExecuteBlocksForKey:key];
        
        if (_byteCount <= trimByteCount)
            break;
    }
}

- (void)trimDiskToSizeByDate:(NSUInteger)trimByteCount
{
    if (_byteCount <= trimByteCount)
        return;
    
    NSArray *keysSortedByDate = [_dates keysSortedByValueUsingSelector:@selector(compare:)];
    
    for (NSString *key in keysSortedByDate) { // oldest objects first
        [self removeFileAndExecuteBlocksForKey:key];
        
        if (_byteCount <= trimByteCount)
            break;
    }
}

- (void)trimDiskToDate:(NSDate *)trimDate
{
    NSArray *keysSortedByDate = [_dates keysSortedByValueUsingSelector:@selector(compare:)];
    
    for (NSString *key in keysSortedByDate) { // oldest files first
        NSDate *accessDate = _dates[key];
        if (!accessDate)
            continue;
        
        if ([accessDate compare:trimDate] == NSOrderedAscending) { // older than trim date
            [self removeFileAndExecuteBlocksForKey:key];
        } else {
            break;
        }
    }
}

- (void)trimToAgeLimitRecursively
{
    if (_ageLimit == 0.0)
        return;
    
    NSDate *date = [[NSDate alloc] initWithTimeIntervalSinceNow:-_ageLimit];
    [self trimDiskToDate:date];
    
    __weak PINDiskCache *weakSelf = self;
    
    dispatch_time_t time = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(_ageLimit * NSEC_PER_SEC));
    dispatch_after(time, _queue, ^(void) {
        PINDiskCache *strongSelf = weakSelf;
        [strongSelf trimToAgeLimitRecursively];
    });
}

#pragma mark - Public Asynchronous Methods -

- (void)objectForKey:(NSString *)key block:(PINDiskCacheObjectBlock)block
{
    NSDate *now = [[NSDate alloc] init];
    
    if (!key || !block)
        return;
    
    __weak PINDiskCache *weakSelf = self;
    
    dispatch_async(_queue, ^{
        PINDiskCache *strongSelf = weakSelf;
        if (!strongSelf)
            return;
        
        NSURL *fileURL = [strongSelf encodedFileURLForKey:key];
        id <NSCoding> object = nil;
        
        if ([[NSFileManager defaultManager] fileExistsAtPath:[fileURL path]]) {
            @try {
                object = [NSKeyedUnarchiver unarchiveObjectWithFile:[fileURL path]];
            }
            @catch (NSException *exception) {
                NSError *error = nil;
                [[NSFileManager defaultManager] removeItemAtPath:[fileURL path] error:&error];
                PINDiskCacheError(error);
            }
            
            [strongSelf setFileModificationDate:now forURL:fileURL];
        }
        
        block(strongSelf, key, object, fileURL);
    });
}

- (void)fileURLForKey:(NSString *)key block:(PINDiskCacheObjectBlock)block
{
    NSDate *now = [[NSDate alloc] init];
    
    if (!key || !block)
        return;
    
    __weak PINDiskCache *weakSelf = self;
    
    dispatch_async(_queue, ^{
        PINDiskCache *strongSelf = weakSelf;
        if (!strongSelf)
            return;
        
        NSURL *fileURL = [strongSelf encodedFileURLForKey:key];
        
        if ([[NSFileManager defaultManager] fileExistsAtPath:[fileURL path]]) {
            [strongSelf setFileModificationDate:now forURL:fileURL];
        } else {
            fileURL = nil;
        }
        
        block(strongSelf, key, nil, fileURL);
    });
}

- (void)setObject:(id <NSCoding>)object forKey:(NSString *)key block:(PINDiskCacheObjectBlock)block
{
    NSDate *now = [[NSDate alloc] init];
    
    if (!key || !object)
        return;
    
    PINCacheStartBackgroundTask();
    
    __weak PINDiskCache *weakSelf = self;
    
    dispatch_async(_queue, ^{
        PINDiskCache *strongSelf = weakSelf;
        if (!strongSelf) {
            PINCacheEndBackgroundTask();
            return;
        }
        
        NSURL *fileURL = [strongSelf encodedFileURLForKey:key];
        
        if (strongSelf->_willAddObjectBlock)
            strongSelf->_willAddObjectBlock(strongSelf, key, object, fileURL);
        
        BOOL written = [NSKeyedArchiver archiveRootObject:object toFile:[fileURL path]];
        
        if (written) {
            [strongSelf setFileModificationDate:now forURL:fileURL];
            
            NSError *error = nil;
            NSDictionary *values = [fileURL resourceValuesForKeys:@[ NSURLTotalFileAllocatedSizeKey ] error:&error];
            PINDiskCacheError(error);
            
            NSNumber *diskFileSize = values[NSURLTotalFileAllocatedSizeKey];
            if (diskFileSize) {
                strongSelf->_sizes[key] = diskFileSize;
                strongSelf.byteCount = strongSelf->_byteCount + [diskFileSize unsignedIntegerValue]; // atomic
            }
            
            if (strongSelf->_byteLimit > 0 && strongSelf->_byteCount > strongSelf->_byteLimit)
                [strongSelf trimToSizeByDate:strongSelf->_byteLimit block:nil];
        } else {
            fileURL = nil;
        }
        
        if (strongSelf->_didAddObjectBlock)
            strongSelf->_didAddObjectBlock(strongSelf, key, object, written ? fileURL : nil);
        
        if (block)
            block(strongSelf, key, object, fileURL);
        
        PINCacheEndBackgroundTask();
    });
}

- (void)removeObjectForKey:(NSString *)key block:(PINDiskCacheObjectBlock)block
{
    if (!key)
        return;
    
    PINCacheStartBackgroundTask();
    
    __weak PINDiskCache *weakSelf = self;
    
    dispatch_async(_queue, ^{
        PINDiskCache *strongSelf = weakSelf;
        if (!strongSelf) {
            PINCacheEndBackgroundTask();
            return;
        }
        
        NSURL *fileURL = [strongSelf encodedFileURLForKey:key];
        [strongSelf removeFileAndExecuteBlocksForKey:key];
        
        if (block)
            block(strongSelf, key, nil, fileURL);
        
        PINCacheEndBackgroundTask();
    });
}

- (void)trimToSize:(NSUInteger)trimByteCount block:(PINDiskCacheBlock)block
{
    if (trimByteCount == 0) {
        [self removeAllObjects:block];
        return;
    }
    
    PINCacheStartBackgroundTask();
    
    __weak PINDiskCache *weakSelf = self;
    
    dispatch_async(_queue, ^{
        PINDiskCache *strongSelf = weakSelf;
        if (!strongSelf) {
            PINCacheEndBackgroundTask();
            return;
        }
        
        [strongSelf trimDiskToSize:trimByteCount];
        
        if (block)
            block(strongSelf);
        
        PINCacheEndBackgroundTask();
    });
}

- (void)trimToDate:(NSDate *)trimDate block:(PINDiskCacheBlock)block
{
    if (!trimDate)
        return;
    
    if ([trimDate isEqualToDate:[NSDate distantPast]]) {
        [self removeAllObjects:block];
        return;
    }
    
    PINCacheStartBackgroundTask();
    
    __weak PINDiskCache *weakSelf = self;
    
    dispatch_async(_queue, ^{
        PINDiskCache *strongSelf = weakSelf;
        if (!strongSelf) {
            PINCacheEndBackgroundTask();
            return;
        }
        
        [strongSelf trimDiskToDate:trimDate];
        
        if (block)
            block(strongSelf);
        
        PINCacheEndBackgroundTask();
    });
}

- (void)trimToSizeByDate:(NSUInteger)trimByteCount block:(PINDiskCacheBlock)block
{
    if (trimByteCount == 0) {
        [self removeAllObjects:block];
        return;
    }
    
    PINCacheStartBackgroundTask();
    
    __weak PINDiskCache *weakSelf = self;
    
    dispatch_async(_queue, ^{
        PINDiskCache *strongSelf = weakSelf;
        if (!strongSelf) {
            PINCacheEndBackgroundTask();
            return;
        }
        
        [strongSelf trimDiskToSizeByDate:trimByteCount];
        
        if (block)
            block(strongSelf);
        
        PINCacheEndBackgroundTask();
    });
}

- (void)removeAllObjects:(PINDiskCacheBlock)block
{
    PINCacheStartBackgroundTask();
    
    __weak PINDiskCache *weakSelf = self;
    
    dispatch_async(_queue, ^{
        PINDiskCache *strongSelf = weakSelf;
        if (!strongSelf) {
            PINCacheEndBackgroundTask();
            return;
        }
        
        if (strongSelf->_willRemoveAllObjectsBlock)
            strongSelf->_willRemoveAllObjectsBlock(strongSelf);
        
        [PINDiskCache moveItemAtURLToTrash:strongSelf->_cacheURL];
        [PINDiskCache emptyTrash];
        
        [strongSelf createCacheDirectory];
        
        [strongSelf->_dates removeAllObjects];
        [strongSelf->_sizes removeAllObjects];
        strongSelf.byteCount = 0; // atomic
        
        if (strongSelf->_didRemoveAllObjectsBlock)
            strongSelf->_didRemoveAllObjectsBlock(strongSelf);
        
        if (block)
            block(strongSelf);
        
        PINCacheEndBackgroundTask();
    });
}

- (void)enumerateObjectsWithBlock:(PINDiskCacheObjectBlock)block completionBlock:(PINDiskCacheBlock)completionBlock
{
    if (!block)
        return;
    
    PINCacheStartBackgroundTask();
    
    __weak PINDiskCache *weakSelf = self;
    
    dispatch_async(_queue, ^{
        PINDiskCache *strongSelf = weakSelf;
        if (!strongSelf) {
            PINCacheEndBackgroundTask();
            return;
        }
        
        NSArray *keysSortedByDate = [strongSelf->_dates keysSortedByValueUsingSelector:@selector(compare:)];
        
        for (NSString *key in keysSortedByDate) {
            NSURL *fileURL = [strongSelf encodedFileURLForKey:key];
            block(strongSelf, key, nil, fileURL);
        }
        
        if (completionBlock)
            completionBlock(strongSelf);
        
        PINCacheEndBackgroundTask();
    });
}

#pragma mark - Public Synchronous Methods -

- (id <NSCoding>)objectForKey:(NSString *)key
{
    if (!key)
        return nil;
    
    __block id <NSCoding> objectForKey = nil;
    
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    
    [self objectForKey:key block:^(PINDiskCache *cache, NSString *key, id <NSCoding> object, NSURL *fileURL) {
        objectForKey = object;
        dispatch_semaphore_signal(semaphore);
    }];
    
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
    
#if !OS_OBJECT_USE_OBJC
    dispatch_release(semaphore);
#endif
    
    return objectForKey;
}

- (NSURL *)fileURLForKey:(NSString *)key
{
    if (!key)
        return nil;
    
    __block NSURL *fileURLForKey = nil;
    
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    
    [self fileURLForKey:key block:^(PINDiskCache *cache, NSString *key, id <NSCoding> object, NSURL *fileURL) {
        fileURLForKey = fileURL;
        dispatch_semaphore_signal(semaphore);
    }];
    
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
    
#if !OS_OBJECT_USE_OBJC
    dispatch_release(semaphore);
#endif
    
    return fileURLForKey;
}

- (void)setObject:(id <NSCoding>)object forKey:(NSString *)key
{
    if (!object || !key)
        return;
    
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    
    [self setObject:object forKey:key block:^(PINDiskCache *cache, NSString *key, id <NSCoding> object, NSURL *fileURL) {
        dispatch_semaphore_signal(semaphore);
    }];
    
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
    
#if !OS_OBJECT_USE_OBJC
    dispatch_release(semaphore);
#endif
}

- (void)removeObjectForKey:(NSString *)key
{
    if (!key)
        return;
    
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    
    [self removeObjectForKey:key block:^(PINDiskCache *cache, NSString *key, id <NSCoding> object, NSURL *fileURL) {
        dispatch_semaphore_signal(semaphore);
    }];
    
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
    
#if !OS_OBJECT_USE_OBJC
    dispatch_release(semaphore);
#endif
}

- (void)trimToSize:(NSUInteger)byteCount
{
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    
    [self trimToSize:byteCount block:^(PINDiskCache *cache) {
        dispatch_semaphore_signal(semaphore);
    }];
    
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
    
#if !OS_OBJECT_USE_OBJC
    dispatch_release(semaphore);
#endif
}

- (void)trimToDate:(NSDate *)date
{
    if (!date)
        return;
    
    if ([date isEqualToDate:[NSDate distantPast]]) {
        [self removeAllObjects];
        return;
    }
    
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    
    [self trimToDate:date block:^(PINDiskCache *cache) {
        dispatch_semaphore_signal(semaphore);
    }];
    
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
    
#if !OS_OBJECT_USE_OBJC
    dispatch_release(semaphore);
#endif
}

- (void)trimToSizeByDate:(NSUInteger)byteCount
{
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    
    [self trimToSizeByDate:byteCount block:^(PINDiskCache *cache) {
        dispatch_semaphore_signal(semaphore);
    }];
    
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
    
#if !OS_OBJECT_USE_OBJC
    dispatch_release(semaphore);
#endif
}

- (void)removeAllObjects
{
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    
    [self removeAllObjects:^(PINDiskCache *cache) {
        dispatch_semaphore_signal(semaphore);
    }];
    
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
    
#if !OS_OBJECT_USE_OBJC
    dispatch_release(semaphore);
#endif
}

- (void)enumerateObjectsWithBlock:(PINDiskCacheObjectBlock)block
{
    if (!block)
        return;
    
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    
    [self enumerateObjectsWithBlock:block completionBlock:^(PINDiskCache *cache) {
        dispatch_semaphore_signal(semaphore);
    }];
    
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
    
#if !OS_OBJECT_USE_OBJC
    dispatch_release(semaphore);
#endif
}

#pragma mark - Public Thread Safe Accessors -

- (void)setWillAddObjectBlock:(PINDiskCacheObjectBlock)block
{
    __weak PINDiskCache *weakSelf = self;
    
    dispatch_async(_queue, ^{
        PINDiskCache *strongSelf = weakSelf;
        if (!strongSelf)
            return;
        
        strongSelf->_willAddObjectBlock = [block copy];
    });
}

- (void)setWillRemoveObjectBlock:(PINDiskCacheObjectBlock)block
{
    __weak PINDiskCache *weakSelf = self;
    
    dispatch_async(_queue, ^{
        PINDiskCache *strongSelf = weakSelf;
        if (!strongSelf)
            return;
        
        strongSelf->_willRemoveObjectBlock = [block copy];
    });
}

- (void)setWillRemoveAllObjectsBlock:(PINDiskCacheBlock)block
{
    __weak PINDiskCache *weakSelf = self;
    
    dispatch_async(_queue, ^{
        PINDiskCache *strongSelf = weakSelf;
        if (!strongSelf)
            return;
        
        strongSelf->_willRemoveAllObjectsBlock = [block copy];
    });
}

- (void)setDidAddObjectBlock:(PINDiskCacheObjectBlock)block
{
    __weak PINDiskCache *weakSelf = self;
    
    dispatch_async(_queue, ^{
        PINDiskCache *strongSelf = weakSelf;
        if (!strongSelf)
            return;
        
        strongSelf->_didAddObjectBlock = [block copy];
    });
}

- (void)setDidRemoveObjectBlock:(PINDiskCacheObjectBlock)block
{
    __weak PINDiskCache *weakSelf = self;
    
    dispatch_async(_queue, ^{
        PINDiskCache *strongSelf = weakSelf;
        if (!strongSelf)
            return;
        
        strongSelf->_didRemoveObjectBlock = [block copy];
    });
}

- (void)setDidRemoveAllObjectsBlock:(PINDiskCacheBlock)block
{
    __weak PINDiskCache *weakSelf = self;
    
    dispatch_async(_queue, ^{
        PINDiskCache *strongSelf = weakSelf;
        if (!strongSelf)
            return;
        
        strongSelf->_didRemoveAllObjectsBlock = [block copy];
    });
}

- (void)setByteLimit:(NSUInteger)byteLimit
{
    __weak PINDiskCache *weakSelf = self;
    
    dispatch_barrier_async(_queue, ^{
        PINDiskCache *strongSelf = weakSelf;
        if (!strongSelf)
            return;
        
        strongSelf->_byteLimit = byteLimit;
        
        if (byteLimit > 0)
            [strongSelf trimDiskToSizeByDate:byteLimit];
    });
}

- (void)setAgeLimit:(NSTimeInterval)ageLimit
{
    __weak PINDiskCache *weakSelf = self;
    
    dispatch_barrier_async(_queue, ^{
        PINDiskCache *strongSelf = weakSelf;
        if (!strongSelf)
            return;
        
        strongSelf->_ageLimit = ageLimit;
        
        [strongSelf trimToAgeLimitRecursively];
    });
}

@end
