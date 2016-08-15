#import "MWKImageInfoFetcher.h"
#import "WMFNetworkUtilities.h"
#import "AFHTTPSessionManager+WMFConfig.h"
#import "MWKImageInfoResponseSerializer.h"
#import "MWKArticle.h"
#import "MediaWikiKit.h"
#import "AFHTTPSessionManager+WMFDesktopRetry.h"
#import "UIScreen+WMFImageWidth.h"
#import "AFHTTPSessionManager+WMFCancelAll.h"

@interface MWKImageInfoFetcher ()

@property(nonatomic, strong, readonly) AFHTTPSessionManager *manager;

// Designated initializer, can be used to inject a mock request manager while testing.
- (instancetype)initWithDelegate:(id<FetchFinishedDelegate>)delegate
                  requestManager:(AFHTTPSessionManager *)requestManager;

@end

@implementation MWKImageInfoFetcher

- (instancetype)init {
    return [self initWithDelegate:nil];
}

- (instancetype)initWithDelegate:(id<FetchFinishedDelegate>)delegate {
    AFHTTPSessionManager *manager = [AFHTTPSessionManager wmf_createDefaultManager];
    manager.responseSerializer = [MWKImageInfoResponseSerializer serializer];
    return [self initWithDelegate:delegate requestManager:manager];
}

- (instancetype)initWithDelegate:(id<FetchFinishedDelegate>)delegate
                  requestManager:(AFHTTPSessionManager *)requestManager {
    NSParameterAssert(requestManager);
    self = [super init];
    if (self) {
        self.fetchFinishedDelegate = delegate;
        _manager = requestManager;
    }
    return self;
}

- (AnyPromise *)fetchGalleryInfoForImage:(NSString *)canonicalPageTitle fromSiteURL:(NSURL *)siteURL {
    return [AnyPromise promiseWithResolverBlock:^(PMKResolver _Nonnull resolve) {
      [self fetchGalleryInfoForImageFiles:@[ canonicalPageTitle ]
                              fromSiteURL:siteURL
                                  success:^(NSArray *infoObjects) {
                                    resolve(infoObjects.firstObject);
                                  }
                                  failure:resolve];
    }];
}

- (AnyPromise *)fetchGalleryInfoForImagesOnPages:(NSArray *)pageTitles
                                     fromSiteURL:(NSURL *)siteURL
                                metadataLanguage:(NSString *)metadataLanguage {
    return [AnyPromise promiseWithResolverBlock:^(PMKResolver _Nonnull resolve) {
      [self fetchInfoForTitles:pageTitles
                   fromSiteURL:siteURL
                thumbnailWidth:[[UIScreen mainScreen] wmf_galleryImageWidthForScale]
               extmetadataKeys:[MWKImageInfoResponseSerializer galleryExtMetadataKeys]
              metadataLanguage:metadataLanguage
                  useGenerator:YES
                       success:resolve
                       failure:resolve];
    }];
}

- (AnyPromise *)fetchPartialInfoForImagesOnPages:(NSArray *)pageTitles
                                     fromSiteURL:(NSURL *)siteURL
                                metadataLanguage:(nullable NSString *)metadataLanguage {
    return [AnyPromise promiseWithResolverBlock:^(PMKResolver _Nonnull resolve) {
      [self fetchInfoForTitles:pageTitles
                   fromSiteURL:siteURL
                thumbnailWidth:[[UIScreen mainScreen] wmf_potdImageWidthForScale]
               extmetadataKeys:[MWKImageInfoResponseSerializer picOfTheDayExtMetadataKeys]
              metadataLanguage:metadataLanguage
                  useGenerator:YES
                       success:resolve
                       failure:resolve];
    }];
}

- (id<MWKImageInfoRequest>)fetchGalleryInfoForImageFiles:(NSArray *)imageTitles
                                             fromSiteURL:(NSURL *)siteURL
                                                 success:(void (^)(NSArray *infoObjects))success
                                                 failure:(void (^)(NSError *error))failure {
    return [self fetchInfoForTitles:imageTitles
                        fromSiteURL:siteURL
                     thumbnailWidth:[[UIScreen mainScreen] wmf_galleryImageWidthForScale]
                    extmetadataKeys:[MWKImageInfoResponseSerializer galleryExtMetadataKeys]
                   metadataLanguage:siteURL.wmf_language
                       useGenerator:NO
                            success:success
                            failure:failure];
}

- (id<MWKImageInfoRequest>)fetchInfoForTitles:(NSArray *)titles
                                  fromSiteURL:(NSURL *)siteURL
                               thumbnailWidth:(NSNumber *)thumbnailWidth
                              extmetadataKeys:(NSArray<NSString *> *)extMetadataKeys
                             metadataLanguage:(nullable NSString *)metadataLanguage
                                 useGenerator:(BOOL)useGenerator
                                      success:(void (^)(NSArray *))success
                                      failure:(void (^)(NSError *))failure {
    NSParameterAssert([titles count]);
    NSAssert([titles count] <= 50, @"Only 50 titles can be queried at a time.");
    NSParameterAssert(siteURL);

    NSMutableDictionary *params =
        [@{ @"format" : @"json",
            @"action" : @"query",
            @"titles" : WMFJoinedPropertyParameters(titles),
            // suppress continue warning
            @"rawcontinue" : @"",
            @"prop" : @"imageinfo",
            @"iiprop" : WMFJoinedPropertyParameters(@[ @"url", @"extmetadata", @"dimensions" ]),
            @"iiextmetadatafilter" : WMFJoinedPropertyParameters(extMetadataKeys),
            @"iiurlwidth" : thumbnailWidth } mutableCopy];

    if (useGenerator) {
        params[@"generator"] = @"images";
    }

    if (metadataLanguage) {
        params[@"iiextmetadatalanguage"] = metadataLanguage;
    }

    @weakify(self);
    NSURLSessionDataTask *request =
        [self.manager wmf_GETAndRetryWithURL:siteURL
            parameters:params
            retry:nil
            success:^(NSURLSessionDataTask *operation, NSArray *galleryItems) {
              @strongify(self);
              [self finishWithError:nil fetchedData:galleryItems];
              if (success) {
                  success(galleryItems);
              }
            }
            failure:^(NSURLSessionDataTask *operation, NSError *error) {
              @strongify(self);
              [self finishWithError:error fetchedData:nil];
              if (failure) {
                  failure(error);
              }
            }];
    NSParameterAssert(request);
    return (id<MWKImageInfoRequest>)request;
}

- (void)cancelAllFetches {
    [self.manager wmf_cancelAllTasks];
}

@end
