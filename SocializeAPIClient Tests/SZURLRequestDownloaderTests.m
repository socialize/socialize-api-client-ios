//
//  SZURLRequestDownloaderTests.m
//  SocializeAPIClient
//
//  Created by Nate Griswold on 2/8/13.
//  Copyright (c) 2013 Socialize. All rights reserved.
//

#import "SZURLRequestDownloaderTests.h"
#import "SZURLRequestDownloader_private.h"

@interface SZURLRequestDownloaderTests ()
@property (nonatomic, strong) id partial;
@property (nonatomic, strong) NSURLConnection *realConnection;
@property (nonatomic, strong) id mockConnection;
@property (nonatomic, strong) SZURLRequestDownloader *URLRequestDownloader;

@end

@implementation SZURLRequestDownloaderTests

+ (NSURL*)testURL {
    return [NSURL URLWithString:@"http://api.getsocialize.com"];
}

+ (NSURLRequest*)testURLRequest {
    return [NSURLRequest requestWithURL:[self testURL]];
}

- (void)setUp {
    self.URLRequestDownloader = [[SZURLRequestDownloader alloc] initWithURLRequest:[[self class] testURLRequest]];

    self.mockConnection = [OCMockObject mockForClass:[NSURLConnection class]];
}

- (void)disableAllConnections {
    [NSURLConnection disable];
}

- (void)tearDown {
    [self.mockConnection verify];
    self.mockConnection = nil;
    self.partial = nil;
    self.URLRequestDownloader = nil;
}

- (void)becomePartial {
    if (self.partial == nil) {
        self.partial = [OCMockObject partialMockForObject:self.URLRequestDownloader];
    }
}

- (void)replaceConnectionProperty {
    [self becomePartial];
    REPLACE_PROPERTY(self.partial, connection, self.mockConnection, setConnection, self.realConnection);
}

- (void)testConnectionIsStartedOnDedicatedThread {
    [self disableAllConnections];
    [self replaceConnectionProperty];

    NSThread *testThread = [NSThread currentThread];
    
    [(NSURLConnection*)[[self.mockConnection expect] andDo0:^{
        GHAssertNotEquals([NSThread currentThread], testThread, @"Should not be test thread");
        GHAssertNotEquals([NSThread currentThread], [NSThread mainThread], @"Should not be main thread");
    }] start];
    
    [self.URLRequestDownloader start];
}

- (void)testSuccessfulDownload {
    [self disableAllConnections];
    [self replaceConnectionProperty];

    WEAK(self) weakSelf = self;
    self.URLRequestDownloader.completionBlock = ^(NSURLResponse *response, NSData *data, NSError *error) {
#define self weakSelf
        
        // Verify the response string was reassembled correctly
        NSString *responseString = [self.URLRequestDownloader responseString];
        GHAssertEqualStrings(responseString, @"Hello", @"Bad response string");
        
        [self notify:kGHUnitWaitStatusSuccess];
#undef self
    };
        
    // Fake a 200 response with data by mimicking the NSURLConnection protocol
    NSDictionary *responseHeaders = @{@"Content-type": @"text/html;charset=utf-8"};
    NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:[[self class] testURL]
                                                              statusCode:200
                                                             HTTPVersion:@"HTTP/1.1"
                                                            headerFields:responseHeaders];
    NSArray *chunks = @[ [@"He" dataUsingEncoding:NSUTF8StringEncoding], [@"llo" dataUsingEncoding:NSUTF8StringEncoding] ];
    [self.mockConnection expectStartAndRespondWithDelegate:self.URLRequestDownloader response:response chunks:chunks];

    [self prepare];
    [self.URLRequestDownloader start];
    [self waitForStatus:kGHUnitWaitStatusSuccess timeout:2];
}

- (void)testCompletionHandlerIsForciblyCalledOnStartingThread {
    [self disableAllConnections];
    [self replaceConnectionProperty];
    
    NSThread *startThread = [NSThread currentThread];
    WEAK(self) weakSelf = self;
    self.URLRequestDownloader.completionBlock = ^(NSURLResponse *response, NSData *data, NSError *error) {
#define self weakSelf
        GHAssertEquals([NSThread currentThread], startThread, @"Completion thread should be same as start thread");
        [self notify:kGHUnitWaitStatusSuccess];
#undef self
    };
    
    [(NSURLConnection*)[[self.mockConnection expect] andDo0:^{
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            [self.URLRequestDownloader connection:nil didFailWithError:nil];
        });
    }] start];
    
    [self prepare];
    [self.URLRequestDownloader start];
    [self waitForStatus:kGHUnitWaitStatusSuccess timeout:2];
}

- (void)testHTTPErrorResponse {
    [self disableAllConnections];
    [self replaceConnectionProperty];

    WEAK(self) weakSelf = self;
    self.URLRequestDownloader.completionBlock = ^(NSURLResponse *response, NSData *data, NSError *error) {
#define self weakSelf
        GHAssertNotNil(error, @"Expected error");
        [self notify:kGHUnitWaitStatusSuccess];
#undef self
    };
    
    // Respond with a failing 404 response
    NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:[[self class] testURL] statusCode:404 HTTPVersion:@"HTTP/1.1" headerFields:nil];
    [self.mockConnection expectStartAndRespondWithDelegate:self.URLRequestDownloader response:response chunks:nil];

    [self prepare];
    [self.URLRequestDownloader start];
    [self waitForStatus:kGHUnitWaitStatusSuccess timeout:2];
}

- (void)testFailedConnection {
    [self disableAllConnections];
    [self replaceConnectionProperty];

    id mockError = [OCMockObject mockForClass:[NSError class]];

    [self.mockConnection expectStartAndFailWithDelegate:self.URLRequestDownloader error:mockError];
    
    WEAK(self) weakSelf = self;
    self.URLRequestDownloader.completionBlock = ^(NSURLResponse *response, NSData *data, NSError *error) {
#define self weakSelf
        [weakSelf notify:kGHUnitWaitStatusSuccess];
        GHAssertEquals(error, mockError, @"Bad error");
#undef self
    };
    
    [self prepare];
    [self.URLRequestDownloader start];
    [self waitForStatus:kGHUnitWaitStatusSuccess timeout:1];
    
    GHAssertEquals(mockError, self.URLRequestDownloader.error, @"Should have error");
}

- (void)testCancelBeforeStartDoesNotDownload {
    [self disableAllConnections];
    [self replaceConnectionProperty];

    [[self.mockConnection expect] cancel];
    
    [self.URLRequestDownloader cancel];
    
    [self.URLRequestDownloader start];
}

- (void)testCancellingSetsIsCancelled {
    [self.URLRequestDownloader cancel];
    GHAssertTrue(self.URLRequestDownloader.isCancelled, @"Should be cancelled");
}

@end
