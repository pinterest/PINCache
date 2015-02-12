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

NSString * const PINDiskCachePrefix = @"com.pinterest.PINDiskCache";
NSString * const PINDiskCacheSharedName = @"PINDiskCacheShared";

@interface PINDiskCache ()
@property (assign) NSUInteger byteCount;
@property (strong, nonatomic) NSURL *cacheURL;
@property (assign, nonatomic) dispatch_queue_t queue;
@property (strong, nonatomic) NSMutableDictionary *dates;
@property (strong, nonatomic) NSMutableDictionary *sizes;
#if OS_OBJECT_USE_OBJC
@property (strong, nonatomic) dispatch_queue_t asyncQueue;
#else
@property (assign, nonatomic) dispatch_queue_t asyncQueue;
#endif
@end

@implementation PINDiskCache

@synthesize willAddObjectBlock = _willAddObjectBlock;
@synthesize willRemoveObjectBlock = _willRemoveObjectBlock;
@synthesize willRemoveAllObjectsBlock = _willRemoveAllObjectsBlock;
@synthesize didAddObjectBlock = _didAddObjectBlock;
@synthesize didRemoveObjectBlock = _didRemoveObjectBlock;
@synthesize didRemoveAllObjectsBlock = _didRemoveAllObjectsBlock;
@synthesize byteLimit = _byteLimit;
@synthesize ageLimit = _ageLimit;

#pragma mark - Initialization -

- (void)dealloc
{
#if !OS_OBJECT_USE_OBJC
    dispatch_release(_asyncQueue);
    _asyncQueue = nil;
#endif
}

- (instancetype)initWithName:(NSString *)name
{
    return [self initWithName:name rootPath:[NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) objectAtIndex:0]];
}

- (instancetype)initWithName:(NSString *)name rootPath:(NSString *)rootPath
{
    if (!name)
        return nil;

    if (self = [super init]) {
        _name = [name copy];
        _queue = [PINDiskCache sharedQueue];
        _asyncQueue = dispatch_queue_create([[NSString stringWithFormat:@"%@ Asynchronous Queue", PINDiskCachePrefix] UTF8String], DISPATCH_QUEUE_CONCURRENT);

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

        NSDate *date = [dictionary objectForKey:NSURLContentModificationDateKey];
        if (date && key)
            [_dates setObject:date forKey:key];

        NSNumber *fileSize = [dictionary objectForKey:NSURLTotalFileAllocatedSizeKey];
        if (fileSize) {
            [_sizes setObject:fileSize forKey:key];
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
            [_dates setObject:date forKey:key];
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

    NSNumber *byteSize = [_sizes objectForKey:key];
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
        NSDate *accessDate = [_dates objectForKey:key];
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
    __weak PINDiskCache *weakSelf = self;

    dispatch_async(_asyncQueue, ^{
        PINDiskCache *strongSelf = weakSelf;
        NSURL *fileURL = nil;
        id <NSCoding> object = [strongSelf objectForKey:key fileURL:&fileURL];

        if (block)
            block(strongSelf, key, object, fileURL);
    });
}

- (void)fileURLForKey:(NSString *)key block:(PINDiskCacheObjectBlock)block
{
    __weak PINDiskCache *weakSelf = self;
    
    dispatch_async(_asyncQueue, ^{
        PINDiskCache *strongSelf = weakSelf;
        NSURL *fileURL = [strongSelf fileURLForKey:key];
        
        if (block)
            block(strongSelf, key, nil, fileURL);
    });
}

- (void)setObject:(id <NSCoding>)object forKey:(NSString *)key block:(PINDiskCacheObjectBlock)block
{
    __weak PINDiskCache *weakSelf = self;
    
    dispatch_async(_asyncQueue, ^{
        PINDiskCache *strongSelf = weakSelf;
        NSURL *fileURL = nil;
        [strongSelf setObject:object forKey:key fileURL:&fileURL];
        
        if (block)
            block(strongSelf, key, object, fileURL);
    });
}

- (void)removeObjectForKey:(NSString *)key block:(PINDiskCacheObjectBlock)block
{
    __weak PINDiskCache *weakSelf = self;
    
    dispatch_async(_asyncQueue, ^{
        PINDiskCache *strongSelf = weakSelf;
        NSURL *fileURL = nil;
        [strongSelf removeObjectForKey:key fileURL:&fileURL];
        
        if (block)
            block(strongSelf, key, nil, fileURL);
    });
}

- (void)trimToSize:(NSUInteger)trimByteCount block:(PINDiskCacheBlock)block
{
    __weak PINDiskCache *weakSelf = self;
    
    dispatch_async(_asyncQueue, ^{
        PINDiskCache *strongSelf = weakSelf;
        [strongSelf trimToSize:trimByteCount];
        
        if (block)
            block(strongSelf);
    });
}

- (void)trimToDate:(NSDate *)trimDate block:(PINDiskCacheBlock)block
{
    __weak PINDiskCache *weakSelf = self;
    
    dispatch_async(_asyncQueue, ^{
        PINDiskCache *strongSelf = weakSelf;
        [strongSelf trimToDate:trimDate];
        
        if (block)
            block(strongSelf);
    });
}

- (void)trimToSizeByDate:(NSUInteger)trimByteCount block:(PINDiskCacheBlock)block
{
    __weak PINDiskCache *weakSelf = self;
    
    dispatch_async(_asyncQueue, ^{
        PINDiskCache *strongSelf = weakSelf;
        [strongSelf trimToSizeByDate:trimByteCount];
        
        if (block)
            block(strongSelf);
    });
}

- (void)removeAllObjects:(PINDiskCacheBlock)block
{
    __weak PINDiskCache *weakSelf = self;
    
    dispatch_async(_asyncQueue, ^{
        PINDiskCache *strongSelf = weakSelf;
        [strongSelf removeAllObjects];
        
        if (block)
            block(strongSelf);
    });
}

- (void)enumerateObjectsWithBlock:(PINDiskCacheObjectBlock)block completionBlock:(PINDiskCacheBlock)completionBlock
{
    __weak PINDiskCache *weakSelf = self;
    
    dispatch_async(_asyncQueue, ^{
        PINDiskCache *strongSelf = weakSelf;
        [strongSelf enumerateObjectsWithBlock:block];
        
        if (completionBlock)
            completionBlock(strongSelf);
    });
}

#pragma mark - Public Synchronous Methods -

- (id <NSCoding>)objectForKey:(NSString *)key
{
    return [self objectForKey:key fileURL:nil];
}

- (id <NSCoding>)objectForKey:(NSString *)key fileURL:(NSURL **)outFileURL
{
    NSDate *now = [[NSDate alloc] init];
    
    if (!key)
        return nil;
    
    __weak PINDiskCache *weakSelf = self;
    __block id <NSCoding> object = nil;
    __block NSURL *fileURL = nil;
    
    dispatch_sync(_queue, ^{
        PINDiskCache *strongSelf = weakSelf;
        if (!strongSelf)
            return;
        
        fileURL = [strongSelf encodedFileURLForKey:key];
        object = nil;
        
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
    });
    
    if (outFileURL) {
        *outFileURL = fileURL;
    }
    
    return object;
}

- (NSURL *)fileURLForKey:(NSString *)key
{
    NSDate *now = [[NSDate alloc] init];
    
    if (!key)
        return nil;
    
    __weak PINDiskCache *weakSelf = self;
    __block NSURL *fileURL = nil;
    
    dispatch_sync(_queue, ^{
        PINDiskCache *strongSelf = weakSelf;
        if (!strongSelf)
            return;
        
        fileURL = [strongSelf encodedFileURLForKey:key];
        
        if ([[NSFileManager defaultManager] fileExistsAtPath:[fileURL path]]) {
            [strongSelf setFileModificationDate:now forURL:fileURL];
        } else {
            fileURL = nil;
        }
    });
    return fileURL;
}

- (void)setObject:(id <NSCoding>)object forKey:(NSString *)key
{
    [self setObject:object forKey:key fileURL:nil];
}

- (void)setObject:(id <NSCoding>)object forKey:(NSString *)key fileURL:(NSURL **)outFileURL
{
    NSDate *now = [[NSDate alloc] init];
    
    if (!key || !object)
        return;
    
    PINCacheStartBackgroundTask();
    
    __weak PINDiskCache *weakSelf = self;
    __block NSURL *fileURL = nil;
    
    dispatch_sync(_queue, ^{
        PINDiskCache *strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        
        fileURL = [strongSelf encodedFileURLForKey:key];
        
        if (strongSelf->_willAddObjectBlock)
            strongSelf->_willAddObjectBlock(strongSelf, key, object, fileURL);
        
        BOOL written = [NSKeyedArchiver archiveRootObject:object toFile:[fileURL path]];
        
        if (written) {
            [strongSelf setFileModificationDate:now forURL:fileURL];
            
            NSError *error = nil;
            NSDictionary *values = [fileURL resourceValuesForKeys:@[ NSURLTotalFileAllocatedSizeKey ] error:&error];
            PINDiskCacheError(error);
            
            NSNumber *diskFileSize = [values objectForKey:NSURLTotalFileAllocatedSizeKey];
            if (diskFileSize) {
                [strongSelf->_sizes setObject:diskFileSize forKey:key];
                strongSelf.byteCount = strongSelf->_byteCount + [diskFileSize unsignedIntegerValue]; // atomic
            }
            
            if (strongSelf->_byteLimit > 0 && strongSelf->_byteCount > strongSelf->_byteLimit)
                [strongSelf trimToSizeByDate:strongSelf->_byteLimit block:nil];
        } else {
            fileURL = nil;
        }
        
        if (strongSelf->_didAddObjectBlock)
            strongSelf->_didAddObjectBlock(strongSelf, key, object, written ? fileURL : nil);
    });
    
    if (outFileURL) {
        *outFileURL = fileURL;
    }
    
    PINCacheEndBackgroundTask();
}

- (void)removeObjectForKey:(NSString *)key
{
    [self removeObjectForKey:key fileURL:nil];
}

- (void)removeObjectForKey:(NSString *)key fileURL:(NSURL **)outFileURL
{
    if (!key)
        return;
    
    PINCacheStartBackgroundTask();
    
    __weak PINDiskCache *weakSelf = self;
    __block NSURL *fileURL = nil;
    
    dispatch_sync(_queue, ^{
        PINDiskCache *strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        
        fileURL = [strongSelf encodedFileURLForKey:key];
        [strongSelf removeFileAndExecuteBlocksForKey:key];
    });
    
    PINCacheEndBackgroundTask();
    
    if (outFileURL) {
        *outFileURL = fileURL;
    }
}

- (void)trimToSize:(NSUInteger)trimByteCount
{
    if (trimByteCount == 0) {
        [self removeAllObjects];
        return;
    }
    
    PINCacheStartBackgroundTask();
    
    __weak PINDiskCache *weakSelf = self;
    
    dispatch_sync(_queue, ^{
        PINDiskCache *strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        
        [strongSelf trimDiskToSize:trimByteCount];
    });
    
    PINCacheEndBackgroundTask();
}

- (void)trimToDate:(NSDate *)trimDate
{
    if (!trimDate)
        return;
    
    if ([trimDate isEqualToDate:[NSDate distantPast]]) {
        [self removeAllObjects];
        return;
    }
    
    PINCacheStartBackgroundTask();
    
    __weak PINDiskCache *weakSelf = self;
    
    dispatch_sync(_queue, ^{
        PINDiskCache *strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        
        [strongSelf trimDiskToDate:trimDate];
    });
    
    PINCacheEndBackgroundTask();
}

- (void)trimToSizeByDate:(NSUInteger)trimByteCount
{
    if (trimByteCount == 0) {
        [self removeAllObjects];
        return;
    }
    
    PINCacheStartBackgroundTask();
    
    __weak PINDiskCache *weakSelf = self;
    
    dispatch_sync(_queue, ^{
        PINDiskCache *strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        
        [strongSelf trimDiskToSizeByDate:trimByteCount];
    });
    
    PINCacheEndBackgroundTask();
}

- (void)removeAllObjects
{
    PINCacheStartBackgroundTask();
    
    __weak PINDiskCache *weakSelf = self;
    
    dispatch_sync(_queue, ^{
        PINDiskCache *strongSelf = weakSelf;
        if (!strongSelf) {
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
    });
    
    PINCacheEndBackgroundTask();
}

- (void)enumerateObjectsWithBlock:(PINDiskCacheObjectBlock)block
{
    if (!block)
        return;
    
    PINCacheStartBackgroundTask();
    
    __weak PINDiskCache *weakSelf = self;
    
    dispatch_sync(_queue, ^{
        PINDiskCache *strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        
        NSArray *keysSortedByDate = [strongSelf->_dates keysSortedByValueUsingSelector:@selector(compare:)];
        
        for (NSString *key in keysSortedByDate) {
            NSURL *fileURL = [strongSelf encodedFileURLForKey:key];
            block(strongSelf, key, nil, fileURL);
        }
    });
    
    PINCacheEndBackgroundTask();
}

#pragma mark - Public Thread Safe Accessors -

- (PINDiskCacheObjectBlock)willAddObjectBlock
{
    __block PINDiskCacheObjectBlock block = nil;

    dispatch_sync(_queue, ^{
        block = _willAddObjectBlock;
    });

    return block;
}

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

- (PINDiskCacheObjectBlock)willRemoveObjectBlock
{
    __block PINDiskCacheObjectBlock block = nil;

    dispatch_sync(_queue, ^{
        block = _willRemoveObjectBlock;
    });

    return block;
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

- (PINDiskCacheBlock)willRemoveAllObjectsBlock
{
    __block PINDiskCacheBlock block = nil;

    dispatch_sync(_queue, ^{
        block = _willRemoveAllObjectsBlock;
    });

    return block;
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

- (PINDiskCacheObjectBlock)didAddObjectBlock
{
    __block PINDiskCacheObjectBlock block = nil;

    dispatch_sync(_queue, ^{
        block = _didAddObjectBlock;
    });

    return block;
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

- (PINDiskCacheObjectBlock)didRemoveObjectBlock
{
    __block PINDiskCacheObjectBlock block = nil;

    dispatch_sync(_queue, ^{
        block = _didRemoveObjectBlock;
    });

    return block;
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

- (PINDiskCacheBlock)didRemoveAllObjectsBlock
{
    __block PINDiskCacheBlock block = nil;

    dispatch_sync(_queue, ^{
        block = _didRemoveAllObjectsBlock;
    });

    return block;
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

- (NSUInteger)byteLimit
{
    __block NSUInteger byteLimit = 0;
    
    dispatch_sync(_queue, ^{
        byteLimit = _byteLimit;
    });
    
    return byteLimit;
}

- (void)setByteLimit:(NSUInteger)byteLimit
{
    __weak PINDiskCache *weakSelf = self;
    
    dispatch_async(_queue, ^{
        PINDiskCache *strongSelf = weakSelf;
        if (!strongSelf)
            return;
        
        strongSelf->_byteLimit = byteLimit;

        if (byteLimit > 0)
            [strongSelf trimDiskToSizeByDate:byteLimit];
    });
}

- (NSTimeInterval)ageLimit
{
    __block NSTimeInterval ageLimit = 0.0;
    
    dispatch_sync(_queue, ^{
        ageLimit = _ageLimit;
    });
    
    return ageLimit;
}

- (void)setAgeLimit:(NSTimeInterval)ageLimit
{
    __weak PINDiskCache *weakSelf = self;
    
    dispatch_async(_queue, ^{
        PINDiskCache *strongSelf = weakSelf;
        if (!strongSelf)
            return;
        
        strongSelf->_ageLimit = ageLimit;
        
        [strongSelf trimToAgeLimitRecursively];
    });
}

@end
