#import <UIKit/UIKit.h>
#import <XCTest/XCTest.h>
#import "WMFArticleFetcher.h"
#import "MWKDataStore+TemporaryDataStore.h"
#import "MWKArticle.h"
#import "WMFTestFixtureUtilities.h"
#import "SessionSingleton.h"
#import <Nocilla/Nocilla.h>
#import "Wikipedia-Swift.h"
#import "WMFArticleBaseFetcher_Testing.h"

#import "XCTestCase+PromiseKit.h"

#define HC_SHORTHAND 1
#import <OCHamcrest/OCHamcrest.h>

@interface ArticleFetcherTests : XCTestCase

@property(strong, nonatomic) MWKDataStore *tempDataStore;
@property(strong, nonatomic) WMFArticleFetcher *articleFetcher;

@end

@implementation ArticleFetcherTests

- (void)setUp {
    [super setUp];
    self.tempDataStore = [MWKDataStore temporaryDataStore];
    self.articleFetcher = [[WMFArticleFetcher alloc] initWithDataStore:self.tempDataStore];
    [[LSNocilla sharedInstance] start];
}

- (void)tearDown {
    [[LSNocilla sharedInstance] stop];
    [self.tempDataStore removeFolderAtBasePath];
    self.tempDataStore = nil;
    self.articleFetcher = nil;
    [super tearDown];
}

+ (NSArray<NSInvocation *> *)testInvocations {
    return [[NSProcessInfo processInfo] wmf_isTravis] ? @[] : [super testInvocations];
}

- (void)testSuccessfulFetchWritesArticleToDataStoreWithoutDuplicatingData {
    NSURL *siteURL = [NSURL wmf_URLWithDefaultSiteAndlanguage:@"en"];
    NSURL *dummyArticleURL = [siteURL wmf_URLWithTitle:@"Foo"];
    NSURL *url = [NSURL wmf_desktopAPIURLForURL:siteURL];

    NSData *json = [[self wmf_bundle] wmf_dataFromContentsOfFile:@"Obama" ofType:@"json"];

    // TODO: refactor into convenience method
    NSRegularExpression *anyRequestFromTestSite =
        [NSRegularExpression regularExpressionWithPattern:
                                 [NSString stringWithFormat:@"%@.*", [url absoluteString]]
                                                  options:0
                                                    error:nil];

    stubRequest(@"GET", anyRequestFromTestSite)
        .andReturn(200)
        .withHeaders(@{ @"Content-Type" : @"application/json" })
        .withBody(json);

    __block MWKArticle *firstFetchResult;

    __block MWKArticle *secondFetchResult;

    __block MWKArticle *savedArticleAfterFirstFetch;

    WMFArticleFetcher *fetcher = self.articleFetcher;
    expectResolutionWithTimeout(10, ^AnyPromise * {
      return [fetcher fetchArticleForURL:dummyArticleURL progress:NULL].then(^id(MWKArticle *article) {
        savedArticleAfterFirstFetch = [self.tempDataStore articleWithURL:dummyArticleURL];
        firstFetchResult = article;
        return [fetcher fetchArticleForURL:dummyArticleURL progress:NULL]
            .then(^(MWKArticle *article) {
              secondFetchResult = article;
            });
      });
    });

    assertThat(@([firstFetchResult isDeeplyEqualToArticle:savedArticleAfterFirstFetch]), isTrue());

    XCTAssertTrue(secondFetchResult != firstFetchResult,
                  @"Expected object returned from 2nd fetch to not be identical to 1st.");
    assertThat(@([secondFetchResult isDeeplyEqualToArticle:firstFetchResult]), isTrue());

    MWKArticle *savedArticleAfterSecondFetch = [self.tempDataStore articleFromDiskWithURL:dummyArticleURL];
    assertThat(@([savedArticleAfterSecondFetch isDeeplyEqualToArticle:firstFetchResult]), isTrue());
}

- (NSDictionary *)requestHeaders {
    return self.articleFetcher.operationManager.requestSerializer.HTTPRequestHeaders;
}

- (void)testRequestHeadersForWikipediaAppUserAgent {
    NSString *userAgent = [self requestHeaders][@"User-Agent"];
    assertThat(@([userAgent hasPrefix:@"WikipediaApp/"]), isTrue());
}

- (void)testRequestHeadersForGZIPAcceptEncoding {
    NSString *acceptEncoding = [self requestHeaders][@"Accept-Encoding"];
    assertThat(acceptEncoding, is(equalTo(@"gzip")));
}

- (void)testRequestHeadersForOptInUUID {
    if ([SessionSingleton sharedInstance].shouldSendUsageReports) {
        assertThat(@([self requestHeaders][@"X-WMF-UUID"] != nil), isTrue());
    } else {
        assertThat(@([self requestHeaders][@"X-WMF-UUID"] == nil), isTrue());
    }
}

@end
