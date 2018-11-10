//
//  RACSignal.m
//  ReactiveCocoa
//
//  Created by Josh Abernathy on 3/15/12.
//  Copyright (c) 2012 GitHub, Inc. All rights reserved.
//

#import "RACSignal.h"
#import "RACCompoundDisposable.h"
#import "RACDisposable.h"
#import "RACDynamicSignal.h"
#import "RACEmptySignal.h"
#import "RACErrorSignal.h"
#import "RACMulticastConnection.h"
#import "RACReplaySubject.h"
#import "RACReturnSignal.h"
#import "RACScheduler.h"
#import "RACSerialDisposable.h"
#import "RACSignal+Operations.h"
#import "RACSubject.h"
#import "RACSubscriber+Private.h"
#import "RACTuple.h"

@implementation RACSignal

#pragma mark Lifecycle

+ (RACSignal *)createSignal:(RACDisposable * (^)(id<RACSubscriber> subscriber))didSubscribe {
    // 创建一个子类对象，动态信号类型对象
	return [RACDynamicSignal createSignal:didSubscribe];
}

+ (RACSignal *)error:(NSError *)error {
	return [RACErrorSignal error:error];
}

+ (RACSignal *)never {
	return [[self createSignal:^ RACDisposable * (id<RACSubscriber> subscriber) {
		return nil;
	}] setNameWithFormat:@"+never"];
}

+ (RACSignal *)startEagerlyWithScheduler:(RACScheduler *)scheduler block:(void (^)(id<RACSubscriber> subscriber))block {
	NSCParameterAssert(scheduler != nil);
	NSCParameterAssert(block != NULL);

	RACSignal *signal = [self startLazilyWithScheduler:scheduler block:block];
	// Subscribe to force the lazy signal to call its block.
	[[signal publish] connect];
	return [signal setNameWithFormat:@"+startEagerlyWithScheduler: %@ block:", scheduler];
}

+ (RACSignal *)startLazilyWithScheduler:(RACScheduler *)scheduler block:(void (^)(id<RACSubscriber> subscriber))block {
	NSCParameterAssert(scheduler != nil);
	NSCParameterAssert(block != NULL);

	RACMulticastConnection *connection = [[RACSignal
		createSignal:^ id (id<RACSubscriber> subscriber) {
			block(subscriber);
			return nil;
		}]
		multicast:[RACReplaySubject subject]];
	
	return [[[RACSignal
		createSignal:^ id (id<RACSubscriber> subscriber) {
			[connection.signal subscribe:subscriber];
			[connection connect];
			return nil;
		}]
		subscribeOn:scheduler]
		setNameWithFormat:@"+startLazilyWithScheduler: %@ block:", scheduler];
}

#pragma mark NSObject

- (NSString *)description {
	return [NSString stringWithFormat:@"<%@: %p> name: %@", self.class, self, self.name];
}

@end

@implementation RACSignal (RACStream)

+ (RACSignal *)empty {
	return [RACEmptySignal empty];
}

+ (RACSignal *)return:(id)value {
	return [RACReturnSignal return:value];
}

- (RACSignal *)bind:(RACStreamBindBlock (^)(void))block {
	NSCParameterAssert(block != NULL);

	/*
	 * -bind: should:
	 * 
	 * 1. Subscribe to the original signal of values.
	 * 2. Any time the original signal sends a value, transform it using the binding block.
	 * 3. If the binding block returns a signal, subscribe to it, and pass all of its values through to the subscriber as they're received.
	 * 4. If the binding block asks the bind to terminate, complete the _original_ signal.
	 * 5. When _all_ signals complete, send completed to the subscriber.
	 * 
	 * If any signal sends an error at any point, send that to the subscriber.
	 */
    // 创建新的信号，用来被订阅获取新值
	return [[RACSignal createSignal:^(id<RACSubscriber> subscriber) {
        // 获取需要返回stream类型的绑定block
		RACStreamBindBlock bindingBlock = block();
        
        // 存储 方法调用者（self）、RACStreamBindBlock中返回的对值进行处理的信号
		NSMutableArray *signals = [NSMutableArray arrayWithObject:self];
        
        // 复合清理对象 新信号需要返回的清理对象
		RACCompoundDisposable *compoundDisposable = [RACCompoundDisposable compoundDisposable];

        // 信号功能完成
		void (^completeSignal)(RACSignal *, RACDisposable *) = ^(RACSignal *signal, RACDisposable *finishedDisposable) {
			BOOL removeDisposable = NO;

            // 对数组signals加同步锁
			@synchronized (signals) {
                // 从数组signals移除
				[signals removeObject:signal];

                // 如果数组signals中信号数量为0
				if (signals.count == 0) {
                    // 对新信号订阅者发送完成
					[subscriber sendCompleted];
                    // 对复合清理对象进行清理
					[compoundDisposable dispose];
				} else {
					removeDisposable = YES;
				}
			}
            
            // 若removeDisposable = YES 从复合信号中清理移除功能完成的信号对应的清理对象
			if (removeDisposable) [compoundDisposable removeDisposable:finishedDisposable];
		};

		void (^addSignal)(RACSignal *) = ^(RACSignal *signal) {
            // 对数组signals加同步锁
			@synchronized (signals) {
                // 数组添加RACStreamBindBlock中返回的信号
				[signals addObject:signal];
			}

			RACSerialDisposable *selfDisposable = [[RACSerialDisposable alloc] init];
			[compoundDisposable addDisposable:selfDisposable];

            // 对RACStreamBindBlock中返回的信号进行订阅
			RACDisposable *disposable = [signal subscribeNext:^(id x) {
                // 给新信号的订阅者发送signal中封装的值
				[subscriber sendNext:x];
			} error:^(NSError *error) {
                // 出现错误，对复合清理对象进行清理
				[compoundDisposable dispose];
                // 对新信号的订阅者发送错误信号
				[subscriber sendError:error];
			} completed:^{
				@autoreleasepool {
                    // 信号绑定功能完成
					completeSignal(signal, selfDisposable);
				}
			}];

			selfDisposable.disposable = disposable;
		};

		@autoreleasepool {
            //
			RACSerialDisposable *selfDisposable = [[RACSerialDisposable alloc] init];
			[compoundDisposable addDisposable:selfDisposable];

            // 对方法调用者(也就是消息接受者)进行订阅
			RACDisposable *bindingDisposable = [self subscribeNext:^(id x) {
				// Manually check disposal to handle synchronous errors.
				if (compoundDisposable.disposed) return;

				BOOL stop = NO;
                // 调用绑定block，返回对值进行处理后的信号
				id signal = bindingBlock(x, &stop);

				@autoreleasepool {
                    // 信号不为空，调用addSignal()这个block方法，添加绑定block中创建的信号
					if (signal != nil) addSignal(signal);
                    // 信号为空 或 stop为YES
					if (signal == nil || stop) {
                        // 对serial清理对象进行清理
						[selfDisposable dispose];
                        // 信号绑定功能完成
						completeSignal(self, selfDisposable);
					}
				}
			} error:^(NSError *error) {
                // 出现错误，对复合清理对象进行清理
				[compoundDisposable dispose];
                // 对新信号的订阅者发送错误信号
				[subscriber sendError:error];
			} completed:^{
				@autoreleasepool {
                    // 信号绑定功能完成
					completeSignal(self, selfDisposable);
				}
			}];

			selfDisposable.disposable = bindingDisposable;
		}
        // 新信号的RACStreamBindBlock返回清理对象
		return compoundDisposable;
	}] setNameWithFormat:@"[%@] -bind:", self.name];
}

- (RACSignal *)concat:(RACSignal *)signal {
	return [[RACSignal createSignal:^(id<RACSubscriber> subscriber) {
		RACSerialDisposable *serialDisposable = [[RACSerialDisposable alloc] init];

        // 订阅第一个信号
		RACDisposable *sourceDisposable = [self subscribeNext:^(id x) {
            // 发送第一个信号的值
			[subscriber sendNext:x];
		} error:^(NSError *error) {
            // 发送第一个信号的error
			[subscriber sendError:error];
		} completed:^{
            // 第一个信号发送完成，订阅第二个信号
			RACDisposable *concattedDisposable = [signal subscribe:subscriber];
			serialDisposable.disposable = concattedDisposable;
		}];

		serialDisposable.disposable = sourceDisposable;
		return serialDisposable;
	}] setNameWithFormat:@"[%@] -concat: %@", self.name, signal];
}

- (RACSignal *)zipWith:(RACSignal *)signal {
	NSCParameterAssert(signal != nil);

	return [[RACSignal createSignal:^(id<RACSubscriber> subscriber) {
        // 第一个信号是否完成
		__block BOOL selfCompleted = NO;
        // 存放第一个信号发送的值
		NSMutableArray *selfValues = [NSMutableArray array];

        // 第二个信号是否完成
		__block BOOL otherCompleted = NO;
        // 存放第二个信号发送的值
		NSMutableArray *otherValues = [NSMutableArray array];

		void (^sendCompletedIfNecessary)(void) = ^{
			@synchronized (selfValues) {
				BOOL selfEmpty = (selfCompleted && selfValues.count == 0);
				BOOL otherEmpty = (otherCompleted && otherValues.count == 0);
                // 两个信号中任意一个信号完成并且对应存放值的数组为空，那整个信号算完成
				if (selfEmpty || otherEmpty) [subscriber sendCompleted];
			}
		};

		void (^sendNext)(void) = ^{
			@synchronized (selfValues) {
                // 数组为空就返回
				if (selfValues.count == 0) return;
				if (otherValues.count == 0) return;

                // 每次都取两个数组的第0位的值，打包成元组
				RACTuple *tuple = RACTuplePack(selfValues[0], otherValues[0]);
				[selfValues removeObjectAtIndex:0];
				[otherValues removeObjectAtIndex:0];

                // 把元组发送出去
				[subscriber sendNext:tuple];
                // 判断整个信号是否完成
				sendCompletedIfNecessary();
			}
		};

        // 订阅第一个信号
		RACDisposable *selfDisposable = [self subscribeNext:^(id x) {
			@synchronized (selfValues) {
                // 把第一个信号的值加入到数组中
				[selfValues addObject:x ?: RACTupleNil.tupleNil];
				sendNext();
			}
		} error:^(NSError *error) {
			[subscriber sendError:error];
		} completed:^{
			@synchronized (selfValues) {
                // 第一个信号发送完成
				selfCompleted = YES;
                // 判断整个信号是否完成
				sendCompletedIfNecessary();
			}
		}];

        // 订阅第二个信号
		RACDisposable *otherDisposable = [signal subscribeNext:^(id x) {
			@synchronized (selfValues) {
                // 把第二个信号的值加入到数组中
				[otherValues addObject:x ?: RACTupleNil.tupleNil];
				sendNext();
			}
		} error:^(NSError *error) {
			[subscriber sendError:error];
		} completed:^{
			@synchronized (selfValues) {
                // 第二个信号发送完成
				otherCompleted = YES;
                // 判断整个信号是否完成
				sendCompletedIfNecessary();
			}
		}];

		return [RACDisposable disposableWithBlock:^{
            // 对两个信号的清理对象进行销毁
			[selfDisposable dispose];
			[otherDisposable dispose];
		}];
	}] setNameWithFormat:@"[%@] -zipWith: %@", self.name, signal];
}

@end

@implementation RACSignal (Subscription)

- (RACDisposable *)subscribe:(id<RACSubscriber>)subscriber {
	NSCAssert(NO, @"This method must be overridden by subclasses");
	return nil;
}

- (RACDisposable *)subscribeNext:(void (^)(id x))nextBlock {
	NSCParameterAssert(nextBlock != NULL);
	
	RACSubscriber *o = [RACSubscriber subscriberWithNext:nextBlock error:NULL completed:NULL];
	return [self subscribe:o];
}

- (RACDisposable *)subscribeNext:(void (^)(id x))nextBlock completed:(void (^)(void))completedBlock {
	NSCParameterAssert(nextBlock != NULL);
	NSCParameterAssert(completedBlock != NULL);
	
	RACSubscriber *o = [RACSubscriber subscriberWithNext:nextBlock error:NULL completed:completedBlock];
	return [self subscribe:o];
}

- (RACDisposable *)subscribeNext:(void (^)(id x))nextBlock error:(void (^)(NSError *error))errorBlock completed:(void (^)(void))completedBlock {
	NSCParameterAssert(nextBlock != NULL);
	NSCParameterAssert(errorBlock != NULL);
	NSCParameterAssert(completedBlock != NULL);
	
	RACSubscriber *o = [RACSubscriber subscriberWithNext:nextBlock error:errorBlock completed:completedBlock];
	return [self subscribe:o];
}

- (RACDisposable *)subscribeError:(void (^)(NSError *error))errorBlock {
	NSCParameterAssert(errorBlock != NULL);
	
	RACSubscriber *o = [RACSubscriber subscriberWithNext:NULL error:errorBlock completed:NULL];
	return [self subscribe:o];
}

- (RACDisposable *)subscribeCompleted:(void (^)(void))completedBlock {
	NSCParameterAssert(completedBlock != NULL);
	
	RACSubscriber *o = [RACSubscriber subscriberWithNext:NULL error:NULL completed:completedBlock];
	return [self subscribe:o];
}

- (RACDisposable *)subscribeNext:(void (^)(id x))nextBlock error:(void (^)(NSError *error))errorBlock {
	NSCParameterAssert(nextBlock != NULL);
	NSCParameterAssert(errorBlock != NULL);
	
	RACSubscriber *o = [RACSubscriber subscriberWithNext:nextBlock error:errorBlock completed:NULL];
	return [self subscribe:o];
}

- (RACDisposable *)subscribeError:(void (^)(NSError *))errorBlock completed:(void (^)(void))completedBlock {
	NSCParameterAssert(completedBlock != NULL);
	NSCParameterAssert(errorBlock != NULL);
	
	RACSubscriber *o = [RACSubscriber subscriberWithNext:NULL error:errorBlock completed:completedBlock];
	return [self subscribe:o];
}

@end

@implementation RACSignal (Debugging)

- (RACSignal *)logAll {
	return [[[self logNext] logError] logCompleted];
}

- (RACSignal *)logNext {
	return [[self doNext:^(id x) {
		NSLog(@"%@ next: %@", self, x);
	}] setNameWithFormat:@"%@", self.name];
}

- (RACSignal *)logError {
	return [[self doError:^(NSError *error) {
		NSLog(@"%@ error: %@", self, error);
	}] setNameWithFormat:@"%@", self.name];
}

- (RACSignal *)logCompleted {
	return [[self doCompleted:^{
		NSLog(@"%@ completed", self);
	}] setNameWithFormat:@"%@", self.name];
}

@end

@implementation RACSignal (Testing)

static const NSTimeInterval RACSignalAsynchronousWaitTimeout = 10;

- (id)asynchronousFirstOrDefault:(id)defaultValue success:(BOOL *)success error:(NSError **)error {
	NSCAssert([NSThread isMainThread], @"%s should only be used from the main thread", __func__);

	__block id result = defaultValue;
	__block BOOL done = NO;

	// Ensures that we don't pass values across thread boundaries by reference.
	__block NSError *localError;
	__block BOOL localSuccess = YES;

	[[[[self
		take:1]
		timeout:RACSignalAsynchronousWaitTimeout onScheduler:[RACScheduler scheduler]]
		deliverOn:RACScheduler.mainThreadScheduler]
		subscribeNext:^(id x) {
			result = x;
			done = YES;
		} error:^(NSError *e) {
			if (!done) {
				localSuccess = NO;
				localError = e;
				done = YES;
			}
		} completed:^{
			done = YES;
		}];
	
	do {
		[NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
	} while (!done);

	if (success != NULL) *success = localSuccess;
	if (error != NULL) *error = localError;

	return result;
}

- (BOOL)asynchronouslyWaitUntilCompleted:(NSError **)error {
	BOOL success = NO;
	[[self ignoreValues] asynchronousFirstOrDefault:nil success:&success error:error];
	return success;
}

@end

@implementation RACSignal (Deprecated)

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-implementations"

+ (RACSignal *)startWithScheduler:(RACScheduler *)scheduler subjectBlock:(void (^)(RACSubject *subject))block {
	NSCParameterAssert(block != NULL);

	RACReplaySubject *subject = [[RACReplaySubject subject] setNameWithFormat:@"+startWithScheduler:subjectBlock:"];

	[scheduler schedule:^{
		block(subject);
	}];

	return subject;
}

+ (RACSignal *)start:(id (^)(BOOL *success, NSError **error))block {
	return [[self startWithScheduler:[RACScheduler scheduler] block:block] setNameWithFormat:@"+start:"];
}

+ (RACSignal *)startWithScheduler:(RACScheduler *)scheduler block:(id (^)(BOOL *success, NSError **error))block {
	return [[self startWithScheduler:scheduler subjectBlock:^(id<RACSubscriber> subscriber) {
		BOOL success = YES;
		NSError *error = nil;
		id returned = block(&success, &error);

		if (!success) {
			[subscriber sendError:error];
		} else {
			[subscriber sendNext:returned];
			[subscriber sendCompleted];
		}
	}] setNameWithFormat:@"+startWithScheduler:block:"];
}

#pragma clang diagnostic pop

@end
