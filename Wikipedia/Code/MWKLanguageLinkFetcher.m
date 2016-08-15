#import "MWKLanguageLinkFetcher.h"
#import "MWNetworkActivityIndicatorManager.h"
#import "SessionSingleton.h"
#import "NSObject+WMFExtras.h"
#import "Defines.h"
#import "WikipediaAppUtils.h"
#import "WMFNetworkUtilities.h"
#import "MWKLanguageLinkResponseSerializer.h"
#import "MediaWikiKit.h"

#import <AFNetworking/AFHTTPSessionManager.h>

@interface MWKLanguageLinkFetcher ()

@property(strong, nonatomic) AFHTTPSessionManager *manager;

@end

@implementation MWKLanguageLinkFetcher

- (instancetype)initAndFetchLanguageLinksForArticleURL:(NSURL *)url
                                           withManager:(AFHTTPSessionManager *)manager
                                    thenNotifyDelegate:(id<FetchFinishedDelegate>)delegate {
    self = [self initWithManager:manager delegate:delegate];
    [self fetchLanguageLinksForArticleURL:url success:nil failure:nil];
    return self;
}

- (instancetype)initWithManager:(AFHTTPSessionManager *)manager delegate:(id<FetchFinishedDelegate>)delegate {
    NSParameterAssert(manager);
    self = [super init];
    if (self) {
        self.manager = manager;
        self.fetchFinishedDelegate = delegate;
    }
    return self;
}

- (void)finishWithError:(NSError *)error fetchedData:(id)fetchedData block:(void (^)(id))block {
    [super finishWithError:error fetchedData:fetchedData];
    if (block) {
        dispatchOnMainQueue(^{
          block(error ?: fetchedData);
        });
    }
}

- (void)fetchLanguageLinksForArticleURL:(NSURL *)url
                                success:(void (^)(NSArray *))success
                                failure:(void (^)(NSError *))failure {
    if (!url.wmf_title.length) {
        NSError *error = [NSError errorWithDomain:WMFNetworkingErrorDomain
                                             code:WMFNetworkingError_InvalidParameters
                                         userInfo:nil];
        [self finishWithError:error fetchedData:nil block:failure];
        return;
    }
    NSURL *apiURL = [[SessionSingleton sharedInstance] urlForLanguage:url.wmf_language];
    NSDictionary *params = @{
        @"action" : @"query",
        @"prop" : @"langlinks",
        @"titles" : url.wmf_title,
        @"lllimit" : @"500",
        @"llprop" : WMFJoinedPropertyParameters(@[ @"langname", @"autonym" ]),
        @"llinlanguagecode" : [[NSLocale currentLocale] objectForKey:NSLocaleLanguageCode],
        @"redirects" : @"",
        @"format" : @"json"
    };
    [[MWNetworkActivityIndicatorManager sharedManager] push];
    [self.manager GET:apiURL.absoluteString
        parameters:params
        progress:NULL
        success:^(NSURLSessionDataTask *operation, NSDictionary *indexedLanguageLinks) {
          [[MWNetworkActivityIndicatorManager sharedManager] pop];
          NSAssert(indexedLanguageLinks.count < 2,
                   @"Expected language links to return one or no objects for the title we fetched, but got: %@",
                   indexedLanguageLinks);
          NSArray *languageLinksForTitle = [[indexedLanguageLinks allValues] firstObject];
          [self finishWithError:nil fetchedData:languageLinksForTitle block:success];
        }
        failure:^(NSURLSessionDataTask *operation, NSError *error) {
          [[MWNetworkActivityIndicatorManager sharedManager] pop];
          [self finishWithError:error fetchedData:nil block:failure];
        }];
}

@end
