//  PINCache is a modified version of PINCache
//  Modifications by Garrett Moon
//  Copyright (c) 2015 Pinterest. All rights reserved.

#import "PINCache.h"

#import <PINOperation/PINOperation.h>

static NSString * const PINCachePrefix = @"com.pinterest.PINCache";
static NSString * const PINCacheSharedName = @"PINCacheShared";

@interface PINCache ()
@property (copy, nonatomic) NSString *name;
@property (strong, nonatomic) PINOperationQueue *operationQueue;
@end

@implementation PINCache

#pragma mark - Initialization -

- (instancetype)init
{
    @throw [NSException exceptionWithName:@"Must initialize with a name" reason:@"PINCache must be initialized with a name. Call initWithName: instead." userInfo:nil];
    return [self initWithName:@""];
}

- (instancetype)initWithName:(NSString *)name
{
    return [self initWithName:name fileExtension:nil];
}

- (instancetype)initWithName:(NSString *)name fileExtension:(NSString *)fileExtension
{
    return [self initWithName:name rootPath:[NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) firstObject] fileExtension:fileExtension];
}

- (instancetype)initWithName:(NSString *)name rootPath:(NSString *)rootPath fileExtension:(NSString *)fileExtension
{
    return [self initWithName:name rootPath:rootPath serializer:nil deserializer:nil fileExtension:fileExtension];
}

- (instancetype)initWithName:(NSString *)name rootPath:(NSString *)rootPath serializer:(PINDiskCacheSerializerBlock)serializer deserializer:(PINDiskCacheDeserializerBlock)deserializer fileExtension:(NSString *)fileExtension
{
    if (!name)
        return nil;
    
    if (self = [super init]) {
        _name = [name copy];
      
        //10 may actually be a bit high, but currently much of our threads are blocked on empyting the trash. Until we can resolve that, lets bump this up.
        _operationQueue = [[PINOperationQueue alloc] initWithMaxConcurrentOperations:10];
        _diskCache = [[PINDiskCache alloc] initWithName:_name prefix:PINDiskCachePrefix rootPath:rootPath serializer:serializer deserializer:deserializer fileExtension:fileExtension operationQueue:_operationQueue];
        _memoryCache = [[PINMemoryCache alloc] initWithOperationQueue:_operationQueue];
    }
    return self;
}

- (NSString *)description
{
    return [[NSString alloc] initWithFormat:@"%@.%@.%p", PINCachePrefix, _name, (void *)self];
}

+ (PINCache *)sharedCache
{
    static PINCache *cache;
    static dispatch_once_t predicate;
    
    dispatch_once(&predicate, ^{
        cache = [[PINCache alloc] initWithName:PINCacheSharedName];
    });
    
    return cache;
}

#pragma mark - Public Asynchronous Methods -

- (void)containsObjectForKeyAsync:(NSString *)key completion:(PINCacheObjectContainmentBlock)block
{
    if (!key || !block) {
        return;
    }
    
    __weak PINCache *weakSelf = self;
  
    [self.operationQueue addOperation:^{
        PINCache *strongSelf = weakSelf;
        
        BOOL containsObject = [strongSelf containsObjectForKey:key];
        block(containsObject);
    }];
}

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wshadow"

- (void)objectForKeyAsync:(NSString *)key completion:(PINCacheObjectBlock)block
{
    if (!key || !block)
        return;
    
    __weak PINCache *weakSelf = self;
    
    [self.operationQueue addOperation:^{
        PINCache *strongSelf = weakSelf;
        if (!strongSelf)
            return;
        [strongSelf->_memoryCache objectForKeyAsync:key completion:^(PINMemoryCache *memoryCache, NSString *memoryCacheKey, id memoryCacheObject) {
            PINCache *strongSelf = weakSelf;
            if (!strongSelf)
                return;
            
            if (memoryCacheObject) {
                // Update file modification date. TODO: make this a separate method?
                [strongSelf->_diskCache fileURLForKeyAsync:memoryCacheKey completion:^(NSString * _Nonnull key, NSURL * _Nullable fileURL) {}];
                [strongSelf->_operationQueue addOperation:^{
                    PINCache *strongSelf = weakSelf;
                    if (strongSelf)
                        block(strongSelf, memoryCacheKey, memoryCacheObject);
                }];
            } else {
                [strongSelf->_diskCache objectForKeyAsync:memoryCacheKey completion:^(PINDiskCache *diskCache, NSString *diskCacheKey, id <NSCoding> diskCacheObject) {
                    PINCache *strongSelf = weakSelf;
                    if (!strongSelf)
                        return;
                    
                    [strongSelf->_memoryCache setObjectAsync:diskCacheObject forKey:diskCacheKey completion:nil];
                    
                    [strongSelf->_operationQueue addOperation:^{
                        PINCache *strongSelf = weakSelf;
                        if (strongSelf)
                            block(strongSelf, diskCacheKey, diskCacheObject);
                    }];
                }];
            }
        }];
    }];
}

#pragma clang diagnostic pop

- (void)setObjectAsync:(id <NSCoding>)object forKey:(NSString *)key completion:(PINCacheObjectBlock)block
{
    [self setObjectAsync:object forKey:key withCost:0 completion:block];
}

- (void)setObjectAsync:(id <NSCoding>)object forKey:(NSString *)key withCost:(NSUInteger)cost completion:(PINCacheObjectBlock)block
{
    if (!key || !object)
        return;
  
    PINOperationGroup *group = [PINOperationGroup asyncOperationGroupWithQueue:_operationQueue];
    
    [group addOperation:^{
        [_memoryCache setObject:object forKey:key withCost:cost];
    }];
    [group addOperation:^{
        [_diskCache setObject:object forKey:key];
    }];
  
    if (block) {
        [group setCompletion:^{
            block(self, key, object);
        }];
    }
    
    [group start];
}

- (void)removeObjectForKeyAsync:(NSString *)key completion:(PINCacheObjectBlock)block
{
    if (!key)
        return;
    
    PINOperationGroup *group = [PINOperationGroup asyncOperationGroupWithQueue:_operationQueue];
    
    [group addOperation:^{
        [_memoryCache removeObjectForKey:key];
    }];
    [group addOperation:^{
        [_diskCache removeObjectForKey:key];
    }];

    if (block) {
        [group setCompletion:^{
            block(self, key, nil);
        }];
    }
    
    [group start];
}

- (void)removeAllObjectsAsync:(PINCacheBlock)block
{
    PINOperationGroup *group = [PINOperationGroup asyncOperationGroupWithQueue:_operationQueue];
    
    [group addOperation:^{
        [_memoryCache removeAllObjects];
    }];
    [group addOperation:^{
        [_diskCache removeAllObjects];
    }];

    if (block) {
        [group setCompletion:^{
            block(self);
        }];
    }
    
    [group start];
}

- (void)trimToDateAsync:(NSDate *)date completion:(PINCacheBlock)block
{
    if (!date)
        return;
    
    PINOperationGroup *group = [PINOperationGroup asyncOperationGroupWithQueue:_operationQueue];
    
    [group addOperation:^{
        [_memoryCache trimToDate:date];
    }];
    [group addOperation:^{
        [_diskCache trimToDate:date];
    }];
  
    if (block) {
        [group setCompletion:^{
            block(self);
        }];
    }
    
    [group start];
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

- (BOOL)containsObjectForKey:(NSString *)key
{
    if (!key)
        return NO;
    
    return [_memoryCache containsObjectForKey:key] || [_diskCache containsObjectForKey:key];
}

- (nullable id)objectForKey:(NSString *)key
{
    if (!key)
        return nil;
    
    __block id object = nil;

    object = [_memoryCache objectForKey:key];
    
    if (object) {
        // Update file modification date. TODO: make this a separate method?
        [_diskCache fileURLForKeyAsync:key completion:^(NSString * _Nonnull key, NSURL * _Nullable fileURL) {}];
    } else {
        object = [_diskCache objectForKey:key];
        [_memoryCache setObject:object forKey:key];
    }
    
    return object;
}

- (void)setObject:(id <NSCoding>)object forKey:(NSString *)key
{
    [self setObject:object forKey:key withCost:0];
}

- (void)setObject:(id <NSCoding>)object forKey:(NSString *)key withCost:(NSUInteger)cost
{
    if (!key || !object)
        return;
    
    [_memoryCache setObject:object forKey:key withCost:cost];
    [_diskCache setObject:object forKey:key];
}

- (nullable id)objectForKeyedSubscript:(NSString *)key
{
    return [self objectForKey:key];
}

- (void)setObject:(nullable id)obj forKeyedSubscript:(NSString *)key
{
    if (obj == nil) {
        [self removeObjectForKey:key];
    } else {
        [self setObject:obj forKey:key];
    }
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

@implementation PINCache (Deprecated)

- (void)containsObjectForKey:(NSString *)key block:(PINCacheObjectContainmentBlock)block
{
    [self containsObjectForKeyAsync:key completion:block];
}

- (void)objectForKey:(NSString *)key block:(PINCacheObjectBlock)block
{
    [self objectForKeyAsync:key completion:block];
}

- (void)setObject:(id <NSCoding>)object forKey:(NSString *)key block:(nullable PINCacheObjectBlock)block
{
    [self setObjectAsync:object forKey:key completion:block];
}

- (void)setObject:(id <NSCoding>)object forKey:(NSString *)key withCost:(NSUInteger)cost block:(nullable PINCacheObjectBlock)block
{
    [self setObjectAsync:object forKey:key withCost:cost completion:block];
}

- (void)removeObjectForKey:(NSString *)key block:(nullable PINCacheObjectBlock)block
{
    [self removeObjectForKeyAsync:key completion:block];
}

- (void)trimToDate:(NSDate *)date block:(nullable PINCacheBlock)block
{
    [self trimToDateAsync:date completion:block];
}

- (void)removeAllObjects:(nullable PINCacheBlock)block
{
    [self removeAllObjectsAsync:block];
}

@end
