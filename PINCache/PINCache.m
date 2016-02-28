//  PINCache is a modified version of PINCache
//  Modifications by Garrett Moon
//  Copyright (c) 2015 Pinterest. All rights reserved.

#import "PINCache.h"

static NSString * const PINCachePrefix = @"com.pinterest.PINCache";
static NSString * const PINCacheSharedName = @"PINCacheShared";

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

- (instancetype)init
{
    @throw [NSException exceptionWithName:@"Must initialize with a name" reason:@"PINCache must be initialized with a name. Call initWithName: instead." userInfo:nil];
    return [self initWithName:@""];
}

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
        
        NSString *queueName = [[NSString alloc] initWithFormat:@"%@.%p", PINCachePrefix, self];
        _concurrentQueue = dispatch_queue_create([[NSString stringWithFormat:@"%@ Asynchronous Queue", queueName] UTF8String], DISPATCH_QUEUE_CONCURRENT);
        
        _diskCache = [[PINDiskCache alloc] initWithName:_name rootPath:rootPath];
        _memoryCache = [[PINMemoryCache alloc] init];
    }
    return self;
}

- (instancetype)initForExtensionsWithName:(NSString *)name rootPath:(NSString *)rootPath
{
    if (!name) {
        return nil;
    }
    if (self = [super init]) {
        _name = [name copy];

        NSString *queueName = [[NSString alloc] initWithFormat:@"%@.%p", PINCachePrefix, self];
        _concurrentQueue = dispatch_queue_create([[NSString stringWithFormat:@"%@ Asynchronous Queue", queueName] UTF8String], DISPATCH_QUEUE_CONCURRENT);

        _diskCache = [[PINDiskCache alloc] initForExtensionsWithName:_name rootPath:rootPath];
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

+ (instancetype)sharedCacheForExtensions
{
    static id cache;
    static dispatch_once_t predicate;
    
    dispatch_once(&predicate, ^{
        cache = [[self alloc] initForExtensionsWithName:PINCacheSharedName rootPath:[NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) firstObject]];
    });
    
    return cache;
}

#pragma mark - Public Asynchronous Methods -

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wshadow"

- (void)objectForKey:(NSString *)key block:(PINCacheObjectBlock)block
{
    if (!key || !block)
        return;
    
    __weak PINCache *weakSelf = self;
    
    dispatch_async(_concurrentQueue, ^{
        PINCache *strongSelf = weakSelf;
        if (!strongSelf)
            return;
        
        __weak PINCache *weakSelf = strongSelf;
        
        [strongSelf->_memoryCache objectForKey:key block:^(PINMemoryCache *memoryCache, NSString *memoryCacheKey, id memoryCacheObject) {
            PINCache *strongSelf = weakSelf;
            if (!strongSelf)
                return;
            
            if (memoryCacheObject) {
                [strongSelf->_diskCache fileURLForKey:memoryCacheKey block:^(PINDiskCache *diskCache, NSString *diskCacheKey, id <NSCoding> diskCacheObject, NSURL *fileURL) {
                    // update the access time on disk
                }];
                
                __weak PINCache *weakSelf = strongSelf;
                
                dispatch_async(strongSelf->_concurrentQueue, ^{
                    PINCache *strongSelf = weakSelf;
                    if (strongSelf)
                        block(strongSelf, memoryCacheKey, memoryCacheObject);
                });
            } else {
                __weak PINCache *weakSelf = strongSelf;
                
                [strongSelf->_diskCache objectForKey:memoryCacheKey block:^(PINDiskCache *diskCache, NSString *diskCacheKey, id <NSCoding> diskCacheObject, NSURL *fileURL) {
                    PINCache *strongSelf = weakSelf;
                    if (!strongSelf)
                        return;
                    
                    [strongSelf->_memoryCache setObject:diskCacheObject forKey:diskCacheKey block:nil];
                    
                    __weak PINCache *weakSelf = strongSelf;
                    
                    dispatch_async(strongSelf->_concurrentQueue, ^{
                        PINCache *strongSelf = weakSelf;
                        if (strongSelf)
                            block(strongSelf, diskCacheKey, diskCacheObject);
                    });
                }];
            }
        }];
    });
}

#pragma clang diagnostic pop

- (void)setObject:(id <NSCoding>)object forKey:(NSString *)key block:(PINCacheObjectBlock)block
{
    if (!key || !object)
        return;
    
    dispatch_group_t group = nil;
    PINMemoryCacheObjectBlock memBlock = nil;
    PINDiskCacheObjectBlock diskBlock = nil;
    
    if (block) {
        group = dispatch_group_create();
        dispatch_group_enter(group);
        dispatch_group_enter(group);
        
        memBlock = ^(PINMemoryCache *memoryCache, NSString *memoryCacheKey, id memoryCacheObject) {
            dispatch_group_leave(group);
        };
        
        diskBlock = ^(PINDiskCache *diskCache, NSString *diskCacheKey, id <NSCoding> memoryCacheObject, NSURL *memoryCacheFileURL) {
            dispatch_group_leave(group);
        };
    }
    
    [_memoryCache setObject:object forKey:key block:memBlock];
    [_diskCache setObject:object forKey:key block:diskBlock];
    
    if (group) {
        __weak PINCache *weakSelf = self;
        dispatch_group_notify(group, _concurrentQueue, ^{
            PINCache *strongSelf = weakSelf;
            if (strongSelf)
                block(strongSelf, key, object);
        });
        
#if !OS_OBJECT_USE_OBJC
        dispatch_release(group);
#endif
    }
}

- (void)removeObjectForKey:(NSString *)key block:(PINCacheObjectBlock)block
{
    if (!key)
        return;
    
    dispatch_group_t group = nil;
    PINMemoryCacheObjectBlock memBlock = nil;
    PINDiskCacheObjectBlock diskBlock = nil;
    
    if (block) {
        group = dispatch_group_create();
        dispatch_group_enter(group);
        dispatch_group_enter(group);
        
        memBlock = ^(PINMemoryCache *memoryCache, NSString *memoryCacheKey, id memoryCacheObject) {
            dispatch_group_leave(group);
        };
        
        diskBlock = ^(PINDiskCache *diskCache, NSString *diskCacheKey, id <NSCoding> memoryCacheObject, NSURL *memoryCacheFileURL) {
            dispatch_group_leave(group);
        };
    }
    
    [_memoryCache removeObjectForKey:key block:memBlock];
    [_diskCache removeObjectForKey:key block:diskBlock];
    
    if (group) {
        __weak PINCache *weakSelf = self;
        dispatch_group_notify(group, _concurrentQueue, ^{
            PINCache *strongSelf = weakSelf;
            if (strongSelf)
                block(strongSelf, key, nil);
        });
        
#if !OS_OBJECT_USE_OBJC
        dispatch_release(group);
#endif
    }
}

- (void)removeAllObjects:(PINCacheBlock)block
{
    dispatch_group_t group = nil;
    PINMemoryCacheBlock memBlock = nil;
    PINDiskCacheBlock diskBlock = nil;
    
    if (block) {
        group = dispatch_group_create();
        dispatch_group_enter(group);
        dispatch_group_enter(group);
        
        memBlock = ^(PINMemoryCache *cache) {
            dispatch_group_leave(group);
        };
        
        diskBlock = ^(PINDiskCache *cache) {
            dispatch_group_leave(group);
        };
    }
    
    [_memoryCache removeAllObjects:memBlock];
    [_diskCache removeAllObjects:diskBlock];
    
    if (group) {
        __weak PINCache *weakSelf = self;
        dispatch_group_notify(group, _concurrentQueue, ^{
            PINCache *strongSelf = weakSelf;
            if (strongSelf)
                block(strongSelf);
        });
        
#if !OS_OBJECT_USE_OBJC
        dispatch_release(group);
#endif
    }
}

- (void)trimToDate:(NSDate *)date block:(PINCacheBlock)block
{
    if (!date)
        return;
    
    dispatch_group_t group = nil;
    PINMemoryCacheBlock memBlock = nil;
    PINDiskCacheBlock diskBlock = nil;
    
    if (block) {
        group = dispatch_group_create();
        dispatch_group_enter(group);
        dispatch_group_enter(group);
        
        memBlock = ^(PINMemoryCache *cache) {
            dispatch_group_leave(group);
        };
        
        diskBlock = ^(PINDiskCache *cache) {
            dispatch_group_leave(group);
        };
    }
    
    [_memoryCache trimToDate:date block:memBlock];
    [_diskCache trimToDate:date block:diskBlock];
    
    if (group) {
        __weak PINCache *weakSelf = self;
        dispatch_group_notify(group, _concurrentQueue, ^{
            PINCache *strongSelf = weakSelf;
            if (strongSelf)
                block(strongSelf);
        });
        
#if !OS_OBJECT_USE_OBJC
        dispatch_release(group);
#endif
    }
}

#pragma mark - Public Synchronous Accessors -

- (NSUInteger)diskByteCount
{
    __block NSUInteger byteCount = 0;
    
    [_diskCache synchronouslyLockFileAccessWhileExecutingBlock:^(PINDiskCache *diskCache) {
        byteCount = diskCache.byteCount;
    }];
    
    return byteCount;
}

- (__nullable id)objectForKey:(NSString *)key
{
    if (!key)
        return nil;
    
    __block id object = nil;

    object = [_memoryCache objectForKey:key];
    
    if (object) {
        // update the access time on disk
        [_diskCache fileURLForKey:key block:NULL];
    } else {
        object = [_diskCache objectForKey:key];
        [_memoryCache setObject:object forKey:key];
    }
    
    return object;
}

- (void)setObject:(id <NSCoding>)object forKey:(NSString *)key
{
    if (!key || !object)
        return;
    
    [_memoryCache setObject:object forKey:key];
    [_diskCache setObject:object forKey:key];
}

- (void)removeObjectForKey:(NSString *)key
{
    if (!key)
        return;
    
    [_memoryCache removeObjectForKey:key];
    [_diskCache removeObjectForKey:key];
}

- (void)trimToDate:(NSDate *)date
{
    if (!date)
        return;
    
    [_memoryCache trimToDate:date];
    [_diskCache trimToDate:date];
}

- (void)removeAllObjects
{
    [_memoryCache removeAllObjects];
    [_diskCache removeAllObjects];
}

@end
