//
//  LNTestObject.m
//  macBridgeTest
//
//  Created by liuhui on 2017/7/19.
//  Copyright © 2019年 liuhui. All rights reserved.
//

#import "LNTestObject.h"
#import <CrashReporter/CrashReporter.h>
#import "macBridgeTestMSPLSource-Swift.h"

@implementation LNTestObject
//C中不能直接使用self来调用OC方法,这里使用单例创建对象(调用方法前需要先创建单例)
static LNTestObject*testObject =nil;
+ (instancetype)shareInstance{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        testObject = [[self alloc] init];
    });
    return testObject;
}
//
//C实现
void c_testFunction(int temp){
    [[LNTestObject shareInstance] c_testFunction:temp];
    //[testObject c_testFunction:temp];
}

void c_testFunction2(int temp){
    [[LNTestObject shareInstance] c_testFunction2];
}


//OC实现
- (void)c_testFunction:(int)temp{
    NSLog(@"temp=%d",temp);
    [self loadCrashReporter];
}

//OC实现2
- (void)c_testFunction2{
    NSLog(@"in c_testFunction2");
 
    [self addressChanged];
//        [self arrayError];
//        [self machException];
//        [self selector];
}

-(void) addressChanged {
    char* ptr = (char*)-1;
    *ptr = 10;
}

-(void) arrayError {
    NSArray *array;
    array = [NSArray arrayWithObjects: @1, @2, @3, nil];
    //Create crash
    NSLog(@ "%@", [array objectAtIndex: 4]);
}

-(void) machException {
    char *c;
    free(c);
}

-(void) selector {
    SEL sel = NSSelectorFromString(@"aaa");
    [self performSelector:sel withObject:nil];
}

- (void) loadCrashReporter {
    PLCrashReporter *crashReporter = [PLCrashReporter sharedReporter];
    NSError *error;

    // Check if we previously crashed
    if ([crashReporter hasPendingCrashReport])
        [self prepareCrashReport];

    // Enable the Crash Reporter
    if (![crashReporter enableCrashReporterAndReturnError: &error])
        NSLog(@"Warning: Could not enable crash reporter: %@", error);
}

- (void) prepareCrashReport {
    PLCrashReporter *crashReporter = [PLCrashReporter sharedReporter];
    NSData *crashData;
    NSError *error;

     // Try loading the crash report
    crashData = [crashReporter loadPendingCrashReportDataAndReturnError: &error];
    if (crashData == nil) {
        NSLog(@"Could not load crash report: %@", error);
        [crashReporter purgePendingCrashReport];
        return;
    }
 
    PLCrashReport *report = [[PLCrashReport alloc] initWithData: crashData error: &error];
    
    //Convert probuf report into unsymbolicated report, and prepend with "Package: HOCKEYAPP_BUNDLEID"
    NSString *packageName = @"Package: com.easilydo.mail\n";
    NSString *unsymbolicatedString = [PLCrashReportTextFormatter stringValueForCrashReport:report withTextFormat:PLCrashReportTextFormatiOS];
    NSString *crashLog = [packageName stringByAppendingString:unsymbolicatedString];
    
    //Write crashLog to Documents directory
    NSArray *docPathArray = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *docPath = [docPathArray firstObject];
    NSString *timestamp = [self getTimestamp];
    NSString *filepath = [NSString stringWithFormat:@"%@/%@.crash", docPath, timestamp];
    [crashLog writeToFile:filepath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    NSLog(@"Path %@", filepath);
        
    //Upload to HockeyApp
    HockeyManager *hockeyManager = [[HockeyManager alloc] init];
    [hockeyManager approveCrashReportWith:filepath];
    [hockeyManager handleCrashReports];
    
    if (report == nil) {
        NSLog(@"Could not parse crash report");
        goto finish;
    }

    // Purge the report
    finish:
        [crashReporter purgePendingCrashReport];
    return;
}

-(NSString*) getTimestamp {
    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    [dateFormatter setDateFormat:@"yyyy-MM-dd_HH-mm-ss"];
    [dateFormatter setTimeZone:[NSTimeZone localTimeZone]];
    return [dateFormatter stringFromDate: [NSDate date]];
}

@end

