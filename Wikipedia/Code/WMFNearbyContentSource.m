#import "WMFNearbyContentSource.h"
#import "WMFContentGroupDataStore.h"
#import "WMFArticleDataStore.h"
#import "WMFLocationSearchResults.h"
#import "MWKLocationSearchResult.h"

#import "WMFLocationManager.h"
#import "WMFLocationSearchFetcher.h"
#import "CLLocation+WMFComparison.h"

@interface WMFNearbyContentSource () <WMFLocationManagerDelegate>

@property (readwrite, nonatomic, strong) NSURL *siteURL;
@property (readwrite, nonatomic, strong) WMFContentGroupDataStore *contentStore;
@property (readwrite, nonatomic, strong) WMFArticleDataStore *previewStore;

@property (nonatomic, strong, readwrite) WMFLocationManager *currentLocationManager;
@property (nonatomic, strong) WMFLocationSearchFetcher *locationSearchFetcher;

@property (readwrite, nonatomic, assign) BOOL isFetchingInitialLocation;

@property (readwrite, nonatomic, assign) BOOL isProcessingLocation;

@property (readwrite, nonatomic, copy) dispatch_block_t completion;

@end

@implementation WMFNearbyContentSource

- (instancetype)initWithSiteURL:(NSURL *)siteURL contentGroupDataStore:(WMFContentGroupDataStore *)contentStore articlePreviewDataStore:(WMFArticleDataStore *)previewStore {
    NSParameterAssert(siteURL);
    NSParameterAssert(contentStore);
    NSParameterAssert(previewStore);
    self = [super init];
    if (self) {
        self.siteURL = siteURL;
        self.contentStore = contentStore;
        self.previewStore = previewStore;
    }
    return self;
}

- (WMFLocationManager *)currentLocationManager {
    if (_currentLocationManager == nil) {
        _currentLocationManager = [WMFLocationManager coarseLocationManager];
        _currentLocationManager.delegate = self;
    }
    return _currentLocationManager;
}

- (WMFLocationSearchFetcher *)locationSearchFetcher {
    if (_locationSearchFetcher == nil) {
        _locationSearchFetcher = [[WMFLocationSearchFetcher alloc] init];
    }
    return _locationSearchFetcher;
}

#pragma mark - WMFContentSource

- (void)startUpdating {
    self.isFetchingInitialLocation = NO;
    [self.currentLocationManager startMonitoringLocation];
}

- (void)stopUpdating {
    [self.currentLocationManager stopMonitoringLocation];
}

- (void)loadNewContentForce:(BOOL)force completion:(nullable dispatch_block_t)completion {
    if (![WMFLocationManager isAuthorized]) {
        [self removeAllContent];
        if (completion) {
            completion();
        }
    } else if (self.currentLocationManager.location == nil) {
        self.isFetchingInitialLocation = YES;
        self.completion = completion;
        [self.currentLocationManager startMonitoringLocation];
    } else {
        [self getGroupForLocation:self.currentLocationManager.location
            completion:^(WMFContentGroup *group) {
                [self fetchResultsForLocationGroup:group completion:completion];
            }
            failure:^(NSError *error) {
                if (completion) {
                    completion();
                }
            }];
    }
}

- (void)removeAllContent {
    [self.contentStore removeAllContentGroupsOfKind:WMFContentGroupKindLocation];
}

#pragma mark - WMFLocationManagerDelegate

- (void)locationManager:(WMFLocationManager *)controller didUpdateLocation:(CLLocation *)location {
    if ([[NSDate date] timeIntervalSinceDate:[location timestamp]] < 60 * 60 && self.isFetchingInitialLocation) {
        [self stopUpdating];
    }
    self.isFetchingInitialLocation = NO;
    [self getGroupForLocation:location
        completion:^(WMFContentGroup *group) {
            [self fetchResultsForLocationGroup:group completion:self.completion];
            self.completion = nil;
        }
        failure:^(NSError *error) {
            if (self.completion) {
                self.completion();
            }
            self.completion = nil;
        }];
}

- (void)locationManager:(WMFLocationManager *)controller didReceiveError:(NSError *)error {
    if (self.isFetchingInitialLocation) {
        [self stopUpdating];
    }
    self.isFetchingInitialLocation = NO;
    if (self.completion) {
        self.completion();
    }
    self.completion = nil;
}

- (nullable WMFContentGroup *)contentGroupCloseToLocation:(CLLocation *)location {

    __block WMFContentGroup *locationContentGroup = nil;
    [self.contentStore enumerateContentGroupsOfKind:WMFContentGroupKindLocation
                                          withBlock:^(WMFContentGroup *_Nonnull currentGroup, BOOL *_Nonnull stop) {
                                              WMFContentGroup *potentiallyCloseLocationGroup = (WMFContentGroup *)currentGroup;
                                              if ([potentiallyCloseLocationGroup.location wmf_isCloseTo:location]) {
                                                  locationContentGroup = potentiallyCloseLocationGroup;
                                                  *stop = YES;
                                              }
                                          }];

    return locationContentGroup;
}

#pragma mark - Fetching

- (void)getGroupForLocation:(CLLocation *)location completion:(void (^)(WMFContentGroup *group))completion
                    failure:(void (^)(NSError *error))failure {

    if (self.isProcessingLocation) {
        failure(nil);
        return;
    }
    self.isProcessingLocation = YES;

    WMFContentGroup *group = [self contentGroupCloseToLocation:location];
    if (group) {
        completion(group);
        return;
    }

    [self.currentLocationManager reverseGeocodeLocation:location
        completion:^(CLPlacemark *_Nonnull placemark) {
            WMFContentGroup *group = [self.contentStore createGroupOfKind:WMFContentGroupKindLocation forDate:[NSDate date] withSiteURL:self.siteURL associatedContent:nil customizationBlock:^(WMFContentGroup * _Nonnull group) {
                group.location = location;
                group.placemark = placemark;
            }];
            completion(group);

        }
        failure:^(NSError *_Nonnull error) {
            self.isProcessingLocation = NO;
            failure(error);
        }];
}

- (void)fetchResultsForLocationGroup:(WMFContentGroup *)group completion:(nullable dispatch_block_t)completion {

    NSArray<NSURL *> *results = (NSArray<NSURL *> *)group.content;

    if ([results count] > 0) {
        self.isProcessingLocation = NO;
        if (completion) {
            completion();
        }
        return;
    }

    @weakify(self);
    [self.locationSearchFetcher fetchArticlesWithSiteURL:self.siteURL
        location:group.location
        resultLimit:20
        completion:^(WMFLocationSearchResults *_Nonnull results) {
            @strongify(self);
            self.isProcessingLocation = NO;

            if([results.results count] == 0){
                return;
            }
            
            NSArray<NSURL *> *urls = [results.results bk_map:^id(id obj) {
                return [results urlForResult:obj];
            }];
            [results.results enumerateObjectsUsingBlock:^(MWKLocationSearchResult *_Nonnull obj, NSUInteger idx, BOOL *_Nonnull stop) {
                [self.previewStore addPreviewWithURL:urls[idx] updatedWithLocationSearchResult:obj];
            }];

            [self removeOldSectionsForDate:group.midnightUTCDate];
            [self.contentStore addContentGroup:group associatedContent:urls];
        }
        failure:^(NSError *_Nonnull error) {
            self.isProcessingLocation = NO;
            if (completion) {
                completion();
            }
        }];
}

- (void)removeOldSectionsForDate:(NSDate *)date {
    NSMutableArray *oldSectionKeys = [NSMutableArray array];
    [self.contentStore enumerateContentGroupsOfKind:WMFContentGroupKindLocation
                                          withBlock:^(WMFContentGroup *_Nonnull section, BOOL *_Nonnull stop) {
                                              if ([section isForLocalDate:date]) {
                                                  [oldSectionKeys addObject:section.key];
                                              }
                                          }];
    [self.contentStore removeContentGroupsWithKeys:oldSectionKeys];
}

@end
