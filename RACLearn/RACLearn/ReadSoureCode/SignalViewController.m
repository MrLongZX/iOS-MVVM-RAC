//
//  ReadSourceCodeViewController.m
//  RACLearn
//
//  Created by guimi on 2018/10/24.
//  Copyright © 2018 Pulian. All rights reserved.
//

#import "SignalViewController.h"
#import <ReactiveCocoa/ReactiveCocoa.h>
#import <ReactiveCocoa/RACReturnSignal.h>
#import <ReactiveCocoa/RACEmptySignal.h>
#import <ReactiveCocoa/RACErrorSignal.h>

@interface SignalViewController ()

@end

@implementation SignalViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    //    [self didSignal];
    //    [self didReturnSignal];
    //    [self didEmptySignal];
    //    [self didBind];
    //    [self didBindT];
    //    [self didBindTT];
    //    [self didConcat];
    //    [self didZipWith];
    
    [self didMap];
}

#pragma mark - 理解 RACSignal
- (void)didSignal
{
    RACSignal *signal = [RACSignal createSignal:^RACDisposable *(id<RACSubscriber> subscriber) {
        // subscriber为下面subscribeNext方法生成的RACSubscriber对象
        [subscriber sendNext:@1];
        [subscriber sendNext:@2];
        [subscriber sendCompleted];
        return [RACDisposable disposableWithBlock:^{
            NSLog(@"dispose");
        }];
    }];
    
    // 生成一个RACDisposable对象和一个RACSubscriber对象，RACSubscriber对象被传到createSignal方法的block中
    RACDisposable *disposable = [signal subscribeNext:^(id x) {
        NSLog(@"%@",x);
    } error:^(NSError *error) {
        NSLog(@"error: %@", error);
    } completed:^{
        NSLog(@"completed");
    }];
    
    [disposable dispose];
}

#pragma mark - 理解 RACReturnSignal
- (void)didReturnSignal
{
    RACReturnSignal *returnSignal = [RACReturnSignal return:@"hello"];
    
    [returnSignal subscribeNext:^(id x) {
        if ([x isEqualToString:@"hello"]) {
            NSLog(@"%@",x);
        }
    } completed:^{
        NSLog(@"completed");
    }];
}

#pragma mark - 理解 RACEmptySignal
- (void)didEmptySignal
{
    RACEmptySignal *empty = [RACEmptySignal empty];
    
    [empty subscribeCompleted:^{
        NSLog(@"completed");
    }];
}

#pragma mark - 理解 RACErrorSignal
- (void)didErrorSignal
{
    // 没有信号的completed
    NSError *error = [NSError errorWithDomain:NSCocoaErrorDomain code:1 userInfo:nil];
    RACSignal *errorSignal = [RACErrorSignal error:error];
    
    [errorSignal subscribeError:^(NSError *error) {
        
    }];
}

#pragma mark - 理解 bind 方法
- (void)didBind
{
    RACSignal *signal = [RACSignal createSignal:^RACDisposable *(id<RACSubscriber> subscriber) {
        [subscriber sendNext:@1];
        [subscriber sendNext:@2];
        [subscriber sendNext:@3];
        [subscriber sendNext:@4];
        [subscriber sendCompleted];
        return nil;
    }];
    
    RACSignal *bindSignal = [signal bind:^RACStreamBindBlock{
        return ^RACStream *(NSNumber *value, BOOL *stop) {
            value = @(value.integerValue * value.integerValue);
            return [RACSignal return:value];
        };
    }];
    
    [signal subscribeNext:^(id x) {
        NSLog(@"signal : %@",x);
    }];
    
    [bindSignal subscribeNext:^(id x) {
        NSLog(@"bindSignal : %@",x);
    }];
}

#pragma mark - 理解 bind 方法
- (void)didBindT
{
    RACSignal *signal = [RACSignal createSignal:^RACDisposable *(id<RACSubscriber> subscriber) {
        [subscriber sendNext:@1];
        [subscriber sendNext:@2];
        [subscriber sendNext:@3];
        [subscriber sendCompleted];
        return nil;
    }];
    
    RACSignal *bindSignal = [signal bind:^RACStreamBindBlock{
        return ^RACStream *(NSNumber *value, BOOL *stop) {
            NSNumber *returnValue = @(value.integerValue * value.integerValue);
            return [RACSignal createSignal:^RACDisposable *(id<RACSubscriber> subscriber) {
                for (NSInteger i = 0; i < value.integerValue; i++) {
                    [subscriber sendNext:returnValue];
                }
                [subscriber sendCompleted];
                return nil;
            }];
        };
    }];
    
    [signal subscribeNext:^(id x) {
        NSLog(@"T signal : %@",x);
    }];
    
    [bindSignal subscribeNext:^(id x) {
        NSLog(@"T bindSignal : %@",x);
    }];
}

#pragma mark - 订阅是如何被清理的
- (void)didBindTT
{
    RACSignal *signal = [RACSignal createSignal:^RACDisposable *(id<RACSubscriber> subscriber) {
        [subscriber sendNext:@1];
        [subscriber sendNext:@2];
        [subscriber sendCompleted];
        return [RACDisposable disposableWithBlock:^{
            NSLog(@"Original Signal Dispose.");
        }];
    }];
    
    RACSignal *bindSignal = [signal bind:^RACStreamBindBlock{
        return ^RACStream *(NSNumber *value, BOOL *stop) {
            NSNumber *returnValue = @(value.integerValue * value.integerValue);
            return [RACSignal createSignal:^RACDisposable *(id<RACSubscriber> subscriber) {
                for (NSInteger i = 0; i < value.integerValue; i++) {
                    [subscriber sendNext:returnValue];
                }
                [subscriber sendCompleted];
                return [RACDisposable disposableWithBlock:^{
                    NSLog(@"Binding Signal Dispose.");
                }];
            }];
        };
    }];
    
    [bindSignal subscribeNext:^(id x) {
        NSLog(@"T bindSignal : %@",x);
    }];
}

#pragma mark - 理解 concat 方法
// 有顺序的，第一个信号发送完成后，第二个信号才开始发送值
- (void)didConcat
{
    RACSignal *signalO = [RACSignal createSignal:^RACDisposable *(id<RACSubscriber> subscriber) {
        [subscriber sendNext:@1];
        [subscriber sendNext:@2];
        [subscriber sendCompleted];
        return [RACDisposable disposableWithBlock:^{
            NSLog(@"dispose 1");
        }];
    }];
    
    RACSignal *signalT = [RACSignal createSignal:^RACDisposable *(id<RACSubscriber> subscriber) {
        [subscriber sendNext:@3];
        [subscriber sendNext:@4];
        [subscriber sendCompleted];
        return [RACDisposable disposableWithBlock:^{
            NSLog(@"dispose 2");
        }];
    }];
    
    RACSignal *concatSignal = [signalO concat:signalT];
    
    [concatSignal subscribeNext:^(id x) {
        NSLog(@"subscribe value = %@",x);
    }];
}

#pragma mark - 理解 zipWith 方法
// 把两个信号压缩成一个信号,只有当两个信号发出一一对应信号内容时，才会触发压缩流的next事件
- (void)didZipWith
{
    RACSignal *signalO = [RACSignal createSignal:^RACDisposable *(id<RACSubscriber> subscriber) {
        [subscriber sendNext:@1];
        [subscriber sendNext:@2];
        [subscriber sendCompleted];
        return [RACDisposable disposableWithBlock:^{
            NSLog(@"dispose 1");
        }];
    }];
    
    RACSignal *signalT = [RACSignal createSignal:^RACDisposable *(id<RACSubscriber> subscriber) {
        [subscriber sendNext:@3];
        [subscriber sendNext:@4];
        [subscriber sendNext:@5];
        [subscriber sendCompleted];
        return [RACDisposable disposableWithBlock:^{
            NSLog(@"dispose 2");
        }];
    }];
    
    RACSignal *zipWithSignal = [signalO zipWith:signalT];
    
    [zipWithSignal subscribeNext:^(id x) {
        NSLog(@"subscribe value = %@",x);
    }];
}

#pragma mark - 理解 Map 方法
- (void)didMap
{
    RACSignal *signalO = [RACSignal createSignal:^RACDisposable *(id<RACSubscriber> subscriber) {
        [subscriber sendNext:@1];
        [subscriber sendNext:@2];
        [subscriber sendCompleted];
        return [RACDisposable disposableWithBlock:^{
            NSLog(@"dispose 1");
        }];
    }];
    
    RACSignal *mapSignal = [signalO map:^id(NSNumber *value) {
        return @([value intValue] * 10);
    }];
    
    [mapSignal subscribeNext:^(id x) {
        NSLog(@"subscribe value = %@",x);
    }];
}

@end
