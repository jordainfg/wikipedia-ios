#import "WMFArticleRevisionFetcher.h"
#import "AFHTTPSessionManager+WMFConfig.h"
#import "AFHTTPSessionManager+WMFDesktopRetry.h"
#import "WMFMantleJSONResponseSerializer.h"
#import "WMFNetworkUtilities.h"

#import "WMFRevisionQueryResults.h"
#import "WMFArticleRevision.h"

@interface WMFArticleRevisionFetcher ()
@property(nonatomic, strong) AFHTTPSessionManager *requestManager;
@end

@implementation WMFArticleRevisionFetcher

- (instancetype)init {
    self = [super init];
    if (self) {
        self.requestManager = [AFHTTPSessionManager wmf_createDefaultManager];
        self.requestManager.responseSerializer =
            [WMFMantleJSONResponseSerializer serializerForArrayOf:[WMFRevisionQueryResults class]
                                                      fromKeypath:@"query.pages"];
    }
    return self;
}

- (void)setTimeoutInterval:(NSTimeInterval)timeoutInterval {
    self.requestManager.requestSerializer.timeoutInterval = timeoutInterval;
}

- (AnyPromise *)fetchLatestRevisionsForArticleURL:(NSURL *)articleURL
                                      resultLimit:(NSUInteger)numberOfResults
                               endingWithRevision:(NSUInteger)revisionId {
    return [self.requestManager wmf_GETAndRetryWithURL:articleURL
                                            parameters:@{
                                                @"format" : @"json",
                                                @"continue" : @"",
                                                @"formatversion" : @2,
                                                @"action" : @"query",
                                                @"prop" : @"revisions",
                                                @"redirects" : @1,
                                                @"titles" : articleURL.wmf_title,
                                                @"rvlimit" : @(numberOfResults),
                                                @"rvendid" : @(revisionId),
                                                @"rvprop" : WMFJoinedPropertyParameters(@[ @"ids", @"size", @"flags" ])
                                            }]
        .then(^(NSArray<WMFRevisionQueryResults *> *results) {
          return results.firstObject;
        });
}

@end
