//  PINCache is a modified version of TMCache
//  Modifications by Garrett Moon
//  Copyright (c) 2015 Pinterest. All rights reserved.

#import "PINMemoryCache.h"

#import <pthread.h>
#import <PINOperation/PINOperation.h>

#if __IPHONE_OS_VERSION_MIN_REQUIRED >= __IPHONE_4_0
#import <UIKit/UIKit.h>
#endif

static NSString * const PINMemoryCachePrefix = @"com.pinterest.PINMemoryCache";
static NSString * const PINMemoryCacheSharedName = @"PINMemoryCacheSharedName";

@interface PINMemoryCache ()
@property (copy, nonatomic) NSString *name;
@property (strong, nonatomic) PINOperationQueue *operationQueue;
@property (assign, nonatomic) pthread_mutex_t mutex;
@property (strong, nonatomic) NSMutableDictionary *dictionary;
@property (strong, nonatomic) NSMutableDictionary *dates;
@property (strong, nonatomic) NSMutableDictionary *costs;
@end

@implementation PINMemoryCache

@synthesize name = _name;
@synthesize ageLimit = _ageLimit;
@synthesize costLimit = _costLimit;
@synthesize totalCost = _totalCost;
@synthesize ttlCache = _ttlCache;
@synthesize willAddObjectBlock = _willAddObjectBlock;
@synthesize willRemoveObjectBlock = _willRemoveObjectBlock;
@synthesize willRemoveAllObjectsBlock = _willRemoveAllObjectsBlock;
@synthesize didAddObjectBlock = _didAddObjectBlock;
@synthesize didRemoveObjectBlock = _didRemoveObjectBlock;
@synthesize didRemoveAllObjectsBlock = _didRemoveAllObjectsBlock;
@synthesize didReceiveMemoryWarningBlock = _didReceiveMemoryWarningBlock;
@synthesize didEnterBackgroundBlock = _didEnterBackgroundBlock;

#pragma mark - Initialization -

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];

    __unused int result = pthread_mutex_destroy(&_mutex);
    NSCAssert(result == 0, @"Failed to destroy lock in PINMemoryCache %p. Code: %d", (void *)self, result);
}

- (instancetype)init
{
    return [self initWithOperationQueue:[PINOperationQueue sharedOperationQueue]];
}

- (instancetype)initWithOperationQueue:(PINOperationQueue *)operationQueue
{
    return [self initWithName:PINMemoryCacheSharedName operationQueue:operationQueue];
}

- (instancetype)initWithName:(NSString *)name operationQueue:(PINOperationQueue *)operationQueue
{
    if (self = [super init]) {
        __unused int result = pthread_mutex_init(&_mutex, NULL);
        NSAssert(result == 0, @"Failed to init lock in PINMemoryCache %@. Code: %d", self, result);
        
        _name = [name copy];
        _operationQueue = operationQueue;
        
        _dictionary = [[NSMutableDictionary alloc] init];
        _dates = [[NSMutableDictionary alloc] init];
        _costs = [[NSMutableDictionary alloc] init];
        
        _willAddObjectBlock = nil;
        _willRemoveObjectBlock = nil;
        _willRemoveAllObjectsBlock = nil;
        
        _didAddObjectBlock = nil;
        _didRemoveObjectBlock = nil;
        _didRemoveAllObjectsBlock = nil;
        
        _didReceiveMemoryWarningBlock = nil;
        _didEnterBackgroundBlock = nil;
        
        _ageLimit = 0.0;
        _costLimit = 0;
        _totalCost = 0;
        
        _removeAllObjectsOnMemoryWarning = YES;
        _removeAllObjectsOnEnteringBackground = YES;
        
#if __IPHONE_OS_VERSION_MIN_REQUIRED >= __IPHONE_4_0 && !TARGET_OS_WATCH
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(didReceiveEnterBackgroundNotification:)
                                                     name:UIApplicationDidEnterBackgroundNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(didReceiveMemoryWarningNotification:)
                                                     name:UIApplicationDidReceiveMemoryWarningNotification
                                                   object:nil];
        
#endif
    }
    return self;
}

+ (PINMemoryCache *)sharedCache
{
    static PINMemoryCache *cache;
    static dispatch_once_t predicate;

    dispatch_once(&predicate, ^{
        cache = [[PINMemoryCache alloc] init];
    });

    return cache;
}

#pragma mark - Private Methods -

- (void)didReceiveMemoryWarningNotification:(NSNotification *)notification {
    if (self.removeAllObjectsOnMemoryWarning)
        [self removeAllObjectsAsync:nil];

    __weak PINMemoryCache *weakSelf = self;

    [self.operationQueue addOperation:^{
        PINMemoryCache *strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        
        [strongSelf lock];
        PINCacheBlock didReceiveMemoryWarningBlock = strongSelf->_didReceiveMemoryWarningBlock;
        [strongSelf unlock];
        
        if (didReceiveMemoryWarningBlock)
            didReceiveMemoryWarningBlock(strongSelf);
    } withPriority:PINOperationQueuePriorityHigh];
}

- (void)didReceiveEnterBackgroundNotification:(NSNotification *)notification
{
    if (self.removeAllObjectsOnEnteringBackground)
        [self removeAllObjectsAsync:nil];

    __weak PINMemoryCache *weakSelf = self;

    [self.operationQueue addOperation:^{
        PINMemoryCache *strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }

        [strongSelf lock];
            PINCacheBlock didEnterBackgroundBlock = strongSelf->_didEnterBackgroundBlock;
        [strongSelf unlock];

        if (didEnterBackgroundBlock)
            didEnterBackgroundBlock(strongSelf);
    } withPriority:PINOperationQueuePriorityHigh];
}

- (void)removeObjectAndExecuteBlocksForKey:(NSString *)key
{
    [self lock];
        id object = _dictionary[key];
        NSNumber *cost = _costs[key];
        PINCacheObjectBlock willRemoveObjectBlock = _willRemoveObjectBlock;
        PINCacheObjectBlock didRemoveObjectBlock = _didRemoveObjectBlock;
    [self unlock];

    if (willRemoveObjectBlock)
        willRemoveObjectBlock(self, key, object);

    [self lock];
        if (cost)
            _totalCost -= [cost unsignedIntegerValue];

        [_dictionary removeObjectForKey:key];
        [_dates removeObjectForKey:key];
        [_costs removeObjectForKey:key];
    [self unlock];
    
    if (didRemoveObjectBlock)
        didRemoveObjectBlock(self, key, nil);
}

- (void)trimMemoryToDate:(NSDate *)trimDate
{
    [self lock];
        NSArray *keysSortedByDate = [_dates keysSortedByValueUsingSelector:@selector(compare:)];
        NSDictionary *dates = [_dates copy];
    [self unlock];
    
    for (NSString *key in keysSortedByDate) { // oldest objects first
        NSDate *accessDate = dates[key];
        if (!accessDate)
            continue;
        
        if ([accessDate compare:trimDate] == NSOrderedAscending) { // older than trim date
            [self removeObjectAndExecuteBlocksForKey:key];
        } else {
            break;
        }
    }
}

- (void)trimToCostLimit:(NSUInteger)limit
{
    NSUInteger totalCost = 0;
    
    [self lock];
        totalCost = _totalCost;
        NSArray *keysSortedByCost = [_costs keysSortedByValueUsingSelector:@selector(compare:)];
    [self unlock];
    
    if (totalCost <= limit) {
        return;
    }

    for (NSString *key in [keysSortedByCost reverseObjectEnumerator]) { // costliest objects first
        [self removeObjectAndExecuteBlocksForKey:key];

        [self lock];
            totalCost = _totalCost;
        [self unlock];
        
        if (totalCost <= limit)
            break;
    }
}

- (void)trimToCostLimitByDate:(NSUInteger)limit
{
    NSUInteger totalCost = 0;
    
    [self lock];
        totalCost = _totalCost;
        NSArray *keysSortedByDate = [_dates keysSortedByValueUsingSelector:@selector(compare:)];
    [self unlock];
    
    if (totalCost <= limit)
        return;

    for (NSString *key in keysSortedByDate) { // oldest objects first
        [self removeObjectAndExecuteBlocksForKey:key];

        [self lock];
            totalCost = _totalCost;
        [self unlock];
        if (totalCost <= limit)
            break;
    }
}

- (void)trimToAgeLimitRecursively
{
    [self lock];
        NSTimeInterval ageLimit = _ageLimit;
    [self unlock];
    
    if (ageLimit == 0.0)
        return;

    NSDate *date = [[NSDate alloc] initWithTimeIntervalSinceNow:-ageLimit];
    
    [self trimMemoryToDate:date];
    
    __weak PINMemoryCache *weakSelf = self;
    
    dispatch_time_t time = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(ageLimit * NSEC_PER_SEC));
    dispatch_after(time, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(void){
        PINMemoryCache *strongSelf = weakSelf;
        [strongSelf.operationQueue addOperation:^{
            PINMemoryCache *strongSelf = weakSelf;
            [strongSelf trimToAgeLimitRecursively];
        } withPriority:PINOperationQueuePriorityHigh];
    });
}

#pragma mark - Public Asynchronous Methods -

- (void)containsObjectForKeyAsync:(NSString *)key completion:(PINCacheObjectContainmentBlock)block
{
    if (!key || !block)
        return;
    
    __weak PINMemoryCache *weakSelf = self;
    
    [self.operationQueue addOperation:^{
        PINMemoryCache *strongSelf = weakSelf;
        BOOL containsObject = [strongSelf containsObjectForKey:key];
        
        block(containsObject);
    } withPriority:PINOperationQueuePriorityHigh];
}

- (void)objectForKeyAsync:(NSString *)key completion:(PINCacheObjectBlock)block
{
    if (block == nil) {
      return;
    }
    __weak PINMemoryCache *weakSelf = self;
    
    [self.operationQueue addOperation:^{
        PINMemoryCache *strongSelf = weakSelf;
        id object = [strongSelf objectForKey:key];
        
        block(strongSelf, key, object);
    } withPriority:PINOperationQueuePriorityHigh];
}

- (void)setObjectAsync:(id)object forKey:(NSString *)key completion:(PINCacheObjectBlock)block
{
    [self setObjectAsync:object forKey:key withCost:0 completion:block];
}

- (void)setObjectAsync:(id)object forKey:(NSString *)key withCost:(NSUInteger)cost completion:(PINCacheObjectBlock)block
{
    __weak PINMemoryCache *weakSelf = self;
    
    [self.operationQueue addOperation:^{
        PINMemoryCache *strongSelf = weakSelf;
        [strongSelf setObject:object forKey:key withCost:cost];
        
        if (block)
            block(strongSelf, key, object);
    } withPriority:PINOperationQueuePriorityHigh];
}

- (void)removeObjectForKeyAsync:(NSString *)key completion:(PINCacheObjectBlock)block
{
    __weak PINMemoryCache *weakSelf = self;
    
    [self.operationQueue addOperation:^{
        PINMemoryCache *strongSelf = weakSelf;
        [strongSelf removeObjectForKey:key];
        
        if (block)
            block(strongSelf, key, nil);
    } withPriority:PINOperationQueuePriorityHigh];
}

- (void)trimToDateAsync:(NSDate *)trimDate completion:(PINCacheBlock)block
{
    __weak PINMemoryCache *weakSelf = self;
    
    [self.operationQueue addOperation:^{
        PINMemoryCache *strongSelf = weakSelf;
        [strongSelf trimToDate:trimDate];
        
        if (block)
            block(strongSelf);
    } withPriority:PINOperationQueuePriorityHigh];
}

- (void)trimToCostAsync:(NSUInteger)cost completion:(PINCacheBlock)block
{
    __weak PINMemoryCache *weakSelf = self;
    
    [self.operationQueue addOperation:^{
        PINMemoryCache *strongSelf = weakSelf;
        [strongSelf trimToCost:cost];
        
        if (block)
            block(strongSelf);
    } withPriority:PINOperationQueuePriorityHigh];
}

- (void)trimToCostByDateAsync:(NSUInteger)cost completion:(PINCacheBlock)block
{
    __weak PINMemoryCache *weakSelf = self;
    
    [self.operationQueue addOperation:^{
        PINMemoryCache *strongSelf = weakSelf;
        [strongSelf trimToCostByDate:cost];
        
        if (block)
            block(strongSelf);
    } withPriority:PINOperationQueuePriorityHigh];
}

- (void)removeAllObjectsAsync:(PINCacheBlock)block
{
    __weak PINMemoryCache *weakSelf = self;
    
    [self.operationQueue addOperation:^{
        PINMemoryCache *strongSelf = weakSelf;
        [strongSelf removeAllObjects];
        
        if (block)
            block(strongSelf);
    } withPriority:PINOperationQueuePriorityHigh];
}

- (void)enumerateObjectsWithBlockAsync:(PINCacheObjectBlock)block completionBlock:(PINCacheBlock)completionBlock
{
    __weak PINMemoryCache *weakSelf = self;
    
    [self.operationQueue addOperation:^{
        PINMemoryCache *strongSelf = weakSelf;
        [strongSelf enumerateObjectsWithBlock:block];
        
        if (completionBlock)
            completionBlock(strongSelf);
    } withPriority:PINOperationQueuePriorityHigh];
}

#pragma mark - Public Synchronous Methods -

- (BOOL)containsObjectForKey:(NSString *)key
{
    if (!key)
        return NO;
    
    [self lock];
        BOOL containsObject = (_dictionary[key] != nil);
    [self unlock];
    return containsObject;
}

- (nullable id)objectForKey:(NSString *)key
{
    if (!key)
        return nil;
    
    NSDate *now = [[NSDate alloc] init];
    [self lock];
        id object = nil;
        // If the cache should behave like a TTL cache, then only fetch the object if there's a valid ageLimit and  the object is still alive
        if (!self->_ttlCache || self->_ageLimit <= 0 || fabs([[_dates objectForKey:key] timeIntervalSinceDate:now]) < self->_ageLimit) {
            object = _dictionary[key];
        }
    [self unlock];
        
    if (object) {
        [self lock];
            _dates[key] = now;
        [self unlock];
    }

    return object;
}

- (id)objectForKeyedSubscript:(NSString *)key
{
    return [self objectForKey:key];
}

- (void)setObject:(id)object forKey:(NSString *)key
{
    [self setObject:object forKey:key withCost:0];
}

- (void)setObject:(id)object forKeyedSubscript:(NSString *)key
{
    if (object == nil) {
        [self removeObjectForKey:key];
    } else {
        [self setObject:object forKey:key];
    }
}

- (void)setObject:(id)object forKey:(NSString *)key withCost:(NSUInteger)cost
{
    if (!key || !object)
        return;
    
    [self lock];
        PINCacheObjectBlock willAddObjectBlock = _willAddObjectBlock;
        PINCacheObjectBlock didAddObjectBlock = _didAddObjectBlock;
        NSUInteger costLimit = _costLimit;
    [self unlock];
    
    if (willAddObjectBlock)
        willAddObjectBlock(self, key, object);
    
    [self lock];
        NSNumber* oldCost = _costs[key];
        if (oldCost)
            _totalCost -= [oldCost unsignedIntegerValue];

        _dictionary[key] = object;
        _dates[key] = [[NSDate alloc] init];
        _costs[key] = @(cost);
        
        _totalCost += cost;
    [self unlock];
    
    if (didAddObjectBlock)
        didAddObjectBlock(self, key, object);
    
    if (costLimit > 0)
        [self trimToCostByDate:costLimit];
}

- (void)removeObjectForKey:(NSString *)key
{
    if (!key)
        return;
    
    [self removeObjectAndExecuteBlocksForKey:key];
}

- (void)trimToDate:(NSDate *)trimDate
{
    if (!trimDate)
        return;
    
    if ([trimDate isEqualToDate:[NSDate distantPast]]) {
        [self removeAllObjects];
        return;
    }
    
    [self trimMemoryToDate:trimDate];
}

- (void)trimToCost:(NSUInteger)cost
{
    [self trimToCostLimit:cost];
}

- (void)trimToCostByDate:(NSUInteger)cost
{
    [self trimToCostLimitByDate:cost];
}

- (void)removeAllObjects
{
    [self lock];
        PINCacheBlock willRemoveAllObjectsBlock = _willRemoveAllObjectsBlock;
        PINCacheBlock didRemoveAllObjectsBlock = _didRemoveAllObjectsBlock;
    [self unlock];
    
    if (willRemoveAllObjectsBlock)
        willRemoveAllObjectsBlock(self);
    
    [self lock];
        [_dictionary removeAllObjects];
        [_dates removeAllObjects];
        [_costs removeAllObjects];
    
        _totalCost = 0;
    [self unlock];
    
    if (didRemoveAllObjectsBlock)
        didRemoveAllObjectsBlock(self);
    
}

- (void)enumerateObjectsWithBlock:(PINCacheObjectBlock)block
{
    if (!block)
        return;
    
    [self lock];
        NSDate *now = [[NSDate alloc] init];
        NSArray *keysSortedByDate = [_dates keysSortedByValueUsingSelector:@selector(compare:)];
        
        for (NSString *key in keysSortedByDate) {
            // If the cache should behave like a TTL cache, then only fetch the object if there's a valid ageLimit and  the object is still alive
            if (!self->_ttlCache || self->_ageLimit <= 0 || fabs([[_dates objectForKey:key] timeIntervalSinceDate:now]) < self->_ageLimit) {
                block(self, key, _dictionary[key]);
            }
        }
    [self unlock];
}

#pragma mark - Public Thread Safe Accessors -

- (PINCacheObjectBlock)willAddObjectBlock
{
    [self lock];
        PINCacheObjectBlock block = _willAddObjectBlock;
    [self unlock];

    return block;
}

- (void)setWillAddObjectBlock:(PINCacheObjectBlock)block
{
    [self lock];
        _willAddObjectBlock = [block copy];
    [self unlock];
}

- (PINCacheObjectBlock)willRemoveObjectBlock
{
    [self lock];
        PINCacheObjectBlock block = _willRemoveObjectBlock;
    [self unlock];

    return block;
}

- (void)setWillRemoveObjectBlock:(PINCacheObjectBlock)block
{
    [self lock];
        _willRemoveObjectBlock = [block copy];
    [self unlock];
}

- (PINCacheBlock)willRemoveAllObjectsBlock
{
    [self lock];
        PINCacheBlock block = _willRemoveAllObjectsBlock;
    [self unlock];

    return block;
}

- (void)setWillRemoveAllObjectsBlock:(PINCacheBlock)block
{
    [self lock];
        _willRemoveAllObjectsBlock = [block copy];
    [self unlock];
}

- (PINCacheObjectBlock)didAddObjectBlock
{
    [self lock];
        PINCacheObjectBlock block = _didAddObjectBlock;
    [self unlock];

    return block;
}

- (void)setDidAddObjectBlock:(PINCacheObjectBlock)block
{
    [self lock];
        _didAddObjectBlock = [block copy];
    [self unlock];
}

- (PINCacheObjectBlock)didRemoveObjectBlock
{
    [self lock];
        PINCacheObjectBlock block = _didRemoveObjectBlock;
    [self unlock];

    return block;
}

- (void)setDidRemoveObjectBlock:(PINCacheObjectBlock)block
{
    [self lock];
        _didRemoveObjectBlock = [block copy];
    [self unlock];
}

- (PINCacheBlock)didRemoveAllObjectsBlock
{
    [self lock];
        PINCacheBlock block = _didRemoveAllObjectsBlock;
    [self unlock];

    return block;
}

- (void)setDidRemoveAllObjectsBlock:(PINCacheBlock)block
{
    [self lock];
        _didRemoveAllObjectsBlock = [block copy];
    [self unlock];
}

- (PINCacheBlock)didReceiveMemoryWarningBlock
{
    [self lock];
        PINCacheBlock block = _didReceiveMemoryWarningBlock;
    [self unlock];

    return block;
}

- (void)setDidReceiveMemoryWarningBlock:(PINCacheBlock)block
{
    [self lock];
        _didReceiveMemoryWarningBlock = [block copy];
    [self unlock];
}

- (PINCacheBlock)didEnterBackgroundBlock
{
    [self lock];
        PINCacheBlock block = _didEnterBackgroundBlock;
    [self unlock];

    return block;
}

- (void)setDidEnterBackgroundBlock:(PINCacheBlock)block
{
    [self lock];
        _didEnterBackgroundBlock = [block copy];
    [self unlock];
}

- (NSTimeInterval)ageLimit
{
    [self lock];
        NSTimeInterval ageLimit = _ageLimit;
    [self unlock];
    
    return ageLimit;
}

- (void)setAgeLimit:(NSTimeInterval)ageLimit
{
    [self lock];
        _ageLimit = ageLimit;
    [self unlock];
    
    [self trimToAgeLimitRecursively];
}

- (NSUInteger)costLimit
{
    [self lock];
        NSUInteger costLimit = _costLimit;
    [self unlock];

    return costLimit;
}

- (void)setCostLimit:(NSUInteger)costLimit
{
    [self lock];
        _costLimit = costLimit;
    [self unlock];

    if (costLimit > 0)
        [self trimToCostLimitByDate:costLimit];
}

- (NSUInteger)totalCost
{
    [self lock];
        NSUInteger cost = _totalCost;
    [self unlock];
    
    return cost;
}

- (BOOL)isTTLCache {
    BOOL isTTLCache;
    
    [self lock];
        isTTLCache = _ttlCache;
    [self unlock];
    
    return isTTLCache;
}

- (void)setTtlCache:(BOOL)ttlCache {
    [self lock];
        _ttlCache = ttlCache;
    [self unlock];
}


- (void)lock
{
    __unused int result = pthread_mutex_lock(&_mutex);
    NSAssert(result == 0, @"Failed to lock PINMemoryCache %@. Code: %d", self, result);
}

- (void)unlock
{
    __unused int result = pthread_mutex_unlock(&_mutex);
    NSAssert(result == 0, @"Failed to unlock PINMemoryCache %@. Code: %d", self, result);
}

@end


#pragma mark - Deprecated

@implementation PINMemoryCache (Deprecated)

- (void)containsObjectForKey:(NSString *)key block:(PINMemoryCacheContainmentBlock)block
{
    [self containsObjectForKeyAsync:key completion:block];
}

- (void)objectForKey:(NSString *)key block:(nullable PINMemoryCacheObjectBlock)block
{
    [self objectForKeyAsync:key completion:block];
}

- (void)setObject:(id)object forKey:(NSString *)key block:(nullable PINMemoryCacheObjectBlock)block
{
    [self setObjectAsync:object forKey:key completion:block];
}

- (void)setObject:(id)object forKey:(NSString *)key withCost:(NSUInteger)cost block:(nullable PINMemoryCacheObjectBlock)block
{
    [self setObjectAsync:object forKey:key withCost:cost completion:block];
}

- (void)removeObjectForKey:(NSString *)key block:(nullable PINMemoryCacheObjectBlock)block
{
    [self removeObjectForKeyAsync:key completion:block];
}

- (void)trimToDate:(NSDate *)date block:(nullable PINMemoryCacheBlock)block
{
    [self trimToDateAsync:date completion:block];
}

- (void)trimToCost:(NSUInteger)cost block:(nullable PINMemoryCacheBlock)block
{
    [self trimToCostAsync:cost completion:block];
}

- (void)trimToCostByDate:(NSUInteger)cost block:(nullable PINMemoryCacheBlock)block
{
    [self trimToCostByDateAsync:cost completion:block];
}

- (void)removeAllObjects:(nullable PINMemoryCacheBlock)block
{
    [self removeAllObjectsAsync:block];
}

- (void)enumerateObjectsWithBlock:(PINMemoryCacheObjectBlock)block completionBlock:(nullable PINMemoryCacheBlock)completionBlock
{
    [self enumerateObjectsWithBlockAsync:block completionBlock:completionBlock];
}

@end
