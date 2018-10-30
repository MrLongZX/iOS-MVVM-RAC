//
//  SchedulerViewController.m
//  RACLearn
//
//  Created by guimi on 2018/10/29.
//  Copyright © 2018 Pulian. All rights reserved.
//

#import "SchedulerViewController.h"
#import <ReactiveCocoa/ReactiveCocoa.h>

@interface SchedulerViewController ()

@end

@implementation SchedulerViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    //    [self didImmediateScheduler];
    
    [self didTargetQueueScheduler];
}

- (void)didImmediateScheduler
{
    [[RACScheduler immediateScheduler] schedule:^{
        NSLog(@"immediateScheduler 0");
    }];
    
    NSLog(@"immediateScheduler 1");
    [[RACScheduler immediateScheduler] afterDelay:2.0 schedule:^{
        NSLog(@"immediateScheduler 2");
    }];
    
    __block int i = 5;
    [[RACScheduler immediateScheduler] scheduleRecursiveBlock:^(void (^reschedule)(void)) {
        if (i > 0) {
            NSLog(@"immediateScheduler 3");
            i--;
            reschedule();
        }
    }];
}

- (void)didTargetQueueScheduler
{
    RACDisposable *disposable = [[RACScheduler mainThreadScheduler] schedule:^{
        NSLog(@"TargetQueueScheduler 0");
    }];
    // disposable对象暂时不知道如何处理
    disposable = nil;
    
    NSLog(@"TargetQueueScheduler 1");
    RACDisposable *afterDisposable = [[RACScheduler mainThreadScheduler] afterDelay:2.0 schedule:^{
        NSLog(@"TargetQueueScheduler 2");
    }];
    
    afterDisposable = nil;
    
    __block int i = 5;
    RACDisposable *recursiveDisposable = [[RACScheduler mainThreadScheduler] scheduleRecursiveBlock:^(void (^reschedule)(void)) {
        if (i > 0) {
            NSLog(@"TargetQueueScheduler 3");
            i--;
            reschedule();
        }
    }];
    
    recursiveDisposable = nil;
}

@end
