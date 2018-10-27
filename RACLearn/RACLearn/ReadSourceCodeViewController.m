//
//  ReadSourceCodeViewController.m
//  RACLearn
//
//  Created by guimi on 2018/10/24.
//  Copyright © 2018 Pulian. All rights reserved.
//

#import "ReadSourceCodeViewController.h"
#import <ReactiveCocoa/ReactiveCocoa.h>
#import <ReactiveCocoa/RACReturnSignal.h>

@interface ReadSourceCodeViewController ()

@end

@implementation ReadSourceCodeViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    [self didSignal];
//    [self didBind];
//    [self didBindT];
//    [self didBindTT];
}

#pragma mark - 理解RACSignal
- (void)didSignal
{
    RACSignal *signal = [RACSignal createSignal:^RACDisposable *(id<RACSubscriber> subscriber) {
        [subscriber sendNext:@1];
        [subscriber sendNext:@2];
        [subscriber sendCompleted];
        return [RACDisposable disposableWithBlock:^{
            NSLog(@"dispose");
        }];
    }];
    
    [signal subscribeNext:^(id x) {
        NSLog(@"%@",x);
    }];
}

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

@end
