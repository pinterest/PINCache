#import "PINCache.h"

NSString * const PINCachePrefix = @"com.pinterest.PINCache";
NSString * const PINCacheSharedName = @"PINCacheShared";

@interface PINCache ()
#if OS_OBJECT_USE_OBJC
@property (strong, nonatomic) dispatch_queue_t concurrentQueue;
#else
@property (assign, nonatomic) dispatch_queue_t concurrentQueue;
#endif
@end

@implementation PINCache

#pragma mark - Initialization -

#if !OS_OBJECT_USE_OBJC
- (void)dealloc
{
    dispatch_release(_concurrentQueue);
    _concurrentQueue = nil;
}
#endif

- (instancetype)initWithName:(NSString *)name
{
    return [self initWithName:name rootPath:[NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) firstObject]];
}

- (instancetype)initWithName:(NSString *)name rootPath:(NSString *)rootPath
{
    return [self initWithName:name rootPath:rootPath timeout:DISPATCH_TIME_FOREVER];
}

- (instancetype)initWithName:(NSString *)name rootPath:(NSString *)rootPath timeout:(dispatch_time_t)timeout
{
    if (!name)
        return nil;
    
    if (self = [super init]) {
        _name = [name copy];
        _timeout = timeout;
        
        NSString *queueName = [[NSString alloc] initWithFormat:@"%@.%p", PINCachePrefix, self];
        _concurrentQueue = dispatch_queue_create([[NSString stringWithFormat:@"%@ Asynchronous Queue", queueName] UTF8String], DISPATCH_QUEUE_CONCURRENT);
        
        _diskCache = [[PINDiskCache alloc] initWithName:_name rootPath:rootPath];
        _memoryCache = [[PINMemoryCache alloc] init];
    }
    return self;
}

- (NSString *)description
{
    return [[NSString alloc] initWithFormat:@"%@.%@.%p", PINCachePrefix, _name, self];
}

+ (instancetype)sharedCache
{
    static id cache;
    static dispatch_once_t predicate;
    
    dispatch_once(&predicate, ^{
        cache = [[self alloc] initWithName:PINCacheSharedName];
    });
    
    return cache;
}

#pragma mark - Public Asynchronous Methods -

- (void)objectForKey:(NSString *)key block:(PINCacheObjectBlock)block
{
    if (!key || !block)
        return;
    
    __weak PINCache *weakSelf = self;
    dispatch_async(_concurrentQueue, ^{
        PINCache *strongSelf = weakSelf;
        id object = [strongSelf objectForKey:key];
        
        if (block)
            block(strongSelf, key, object);
    });
}

- (void)setObject:(id <NSCoding>)object forKey:(NSString *)key block:(PINCacheObjectBlock)block
{
    if (!key || !object)
        return;
    
    __weak PINCache *weakSelf = self;
    dispatch_async(_concurrentQueue, ^{
        PINCache *strongSelf = weakSelf;
        [strongSelf setObject:object forKey:key];
        
        if (block)
            block(strongSelf, key, object);
    });
}

- (void)removeObjectForKey:(NSString *)key block:(PINCacheObjectBlock)block
{
    if (!key)
        return;
    
    __weak PINCache *weakSelf = self;
    dispatch_async(_concurrentQueue, ^{
        PINCache *strongSelf = weakSelf;
        [strongSelf removeObjectForKey:key];
        
        if (block)
            block(strongSelf, key, nil);
    });
}

- (void)removeAllObjects:(PINCacheBlock)block
{
    __weak PINCache *weakSelf = self;
    dispatch_async(_concurrentQueue, ^{
        PINCache *strongSelf = weakSelf;
        [strongSelf removeAllObjects];
        
        if (block)
            block(strongSelf);
    });
}

- (void)trimToDate:(NSDate *)date block:(PINCacheBlock)block
{
    if (!date)
        return;

    __weak PINCache *weakSelf = self;
    dispatch_async(_concurrentQueue, ^{
        PINCache *strongSelf = weakSelf;
        [strongSelf trimToDate:date];
        
        if (block)
            block(strongSelf);
    });
}

#pragma mark - Public Synchronous Accessors -

- (NSUInteger)diskByteCount
{
    __block NSUInteger byteCount = 0;
    
    dispatch_sync([PINDiskCache sharedQueue], ^{
        byteCount = self.diskCache.byteCount;
    });
    
    return byteCount;
}

- (id)objectForKey:(NSString *)key
{
    if (!key)
        return nil;
    
    __block id object = nil;

    object = [_memoryCache objectForKey:key];
    
    if (object) {
        // update the access time on disk
        [_diskCache fileURLForKey:key block:NULL];
    } else {
        dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
        [_diskCache objectForKey:key block:^(PINDiskCache *cache, NSString *key, id<NSCoding> diskObject, NSURL *fileURL) {
            object = diskObject;
            dispatch_semaphore_signal(semaphore);
        }];
        dispatch_semaphore_wait(semaphore, self.timeout);
#if !OS_OBJECT_USE_OBJC
        dispatch_release(semaphore);
#endif
        
        [_memoryCache setObject:object forKey:key];
    }
    
    return object;
}

- (void)setObject:(id <NSCoding>)object forKey:(NSString *)key
{
    if (!key || !object)
        return;
    
    [_memoryCache setObject:object forKey:key];
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    [_diskCache setObject:object forKey:key block:^(PINDiskCache *cache, NSString *key, id<NSCoding> object, NSURL *fileURL) {
        dispatch_semaphore_signal(semaphore);
    }];
    dispatch_semaphore_wait(semaphore, self.timeout);
#if !OS_OBJECT_USE_OBJC
    dispatch_release(semaphore);
#endif
}

- (void)removeObjectForKey:(NSString *)key
{
    if (!key)
        return;
    
    [_memoryCache removeObjectForKey:key];
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    [_diskCache removeObjectForKey:key block:^(PINDiskCache *cache, NSString *key, id<NSCoding> object, NSURL *fileURL) {
        dispatch_semaphore_signal(semaphore);
    }];
    dispatch_semaphore_wait(semaphore, self.timeout);
#if !OS_OBJECT_USE_OBJC
    dispatch_release(semaphore);
#endif
}

- (void)trimToDate:(NSDate *)date
{
    if (!date)
        return;
    
    [_memoryCache trimToDate:date];
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    [_diskCache trimToDate:date block:^(PINDiskCache *cache) {
        dispatch_semaphore_signal(semaphore);
    }];
    dispatch_semaphore_wait(semaphore, self.timeout);
#if !OS_OBJECT_USE_OBJC
    dispatch_release(semaphore);
#endif
}

- (void)removeAllObjects
{
    [_memoryCache removeAllObjects];
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    [_diskCache removeAllObjects:^(PINDiskCache *cache) {
        dispatch_semaphore_signal(semaphore);
    }];
    dispatch_semaphore_wait(semaphore, self.timeout);
#if !OS_OBJECT_USE_OBJC
    dispatch_release(semaphore);
#endif
}

@end

// HC SVNT DRACONES
