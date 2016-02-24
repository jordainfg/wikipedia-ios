
#import "WMFExploreSectionSchema.h"
#import "MWKSite.h"
#import "MWKTitle.h"
#import "MWKDataStore.h"
#import "MWKSavedPageList.h"
#import "MWKHistoryList.h"
#import "WMFExploreSection.h"
#import "Wikipedia-Swift.h"
#import "NSDate+Utilities.h"
#import "WMFLocationManager.h"
#import "WMFAssetsFile.h"
#import "WMFRelatedSectionBlackList.h"
#import "NSDate+WMFMostReadDate.h"
#import "NSCalendar+WMFCommonCalendars.h"

@import Tweaks;
@import CoreLocation;

NS_ASSUME_NONNULL_BEGIN

static NSTimeInterval const WMFHomeMinimumAutomaticReloadTime      = 600.0; //10 minutes
static NSTimeInterval const WMFTimeBeforeDisplayingLastReadArticle = 24 * 60 * 60; //24 hours
static NSTimeInterval const WMFTimeBeforeRefreshingRandom          = 60 * 60 * 24 * 7; //7 days


static CLLocationDistance const WMFMinimumDistanceBeforeUpdatingNearby = 500.0;

static NSString* const WMFExploreSectionsFileName      = @"WMFHomeSections";
static NSString* const WMFExploreSectionsFileExtension = @"plist";



@interface WMFExploreSectionSchema ()<WMFLocationManagerDelegate>

@property (nonatomic, strong, readwrite) MWKSite* site;
@property (nonatomic, strong, readwrite) MWKSavedPageList* savedPages;
@property (nonatomic, strong, readwrite) MWKHistoryList* historyPages;
@property (nonatomic, strong, readwrite) WMFRelatedSectionBlackList* blackList;

@property (nonatomic, strong) WMFLocationManager* locationManager;

@property (nonatomic, strong, readwrite) WMFAssetsFile* mainPages;

@property (nonatomic, strong, readwrite, nullable) NSDate* lastUpdatedAt;

@property (nonatomic, strong, readwrite) NSArray<WMFExploreSection*>* sections;

@end


@implementation WMFExploreSectionSchema

- (NSString*)description {
    // HAX: prevent this from logging all its properties in its description, as this causes recursion to
    // WMFLocationManager.description
    return [NSString stringWithFormat:@"<%@: %p>", [self class], self];
}

#pragma mark - Setup

+ (instancetype)schemaWithSite:(MWKSite*)site savedPages:(MWKSavedPageList*)savedPages history:(MWKHistoryList*)history blackList:(WMFRelatedSectionBlackList*)blackList {
    NSParameterAssert(site);
    NSParameterAssert(savedPages);
    NSParameterAssert(history);
    NSParameterAssert(blackList);

    WMFExploreSectionSchema* schema = [self loadSchemaFromDisk];

    if (schema) {
        schema.site         = site;
        schema.savedPages   = savedPages;
        schema.historyPages = history;
        schema.blackList    = blackList;
        [schema update:YES];
    } else {
        schema = [[WMFExploreSectionSchema alloc] initWithSite:site savedPages:savedPages history:history blackList:blackList];
    }

    return schema;
}

- (instancetype)initWithSite:(MWKSite*)site
                  savedPages:(MWKSavedPageList*)savedPages
                     history:(MWKHistoryList*)history
                   blackList:(WMFRelatedSectionBlackList*)blackList {
    NSParameterAssert(site);
    NSParameterAssert(savedPages);
    NSParameterAssert(history);
    NSParameterAssert(blackList);
    self = [super init];
    if (self) {
        self.site         = site;
        self.savedPages   = savedPages;
        self.historyPages = history;
        self.blackList    = blackList;
        [self reset];
    }
    return self;
}

- (void)setBlackList:(WMFRelatedSectionBlackList*)blackList {
    if (_blackList) {
        [self.KVOController unobserve:_blackList];
    }

    _blackList = blackList;

    [self.KVOController observe:_blackList keyPath:WMF_SAFE_KEYPATH(_blackList, entries) options:0 block:^(WMFExploreSectionSchema* observer, WMFRelatedSectionBlackList* object, NSDictionary* change) {
        [observer updateWithChangesInBlackList:object];
    }];
}

/**
 *  Reset the feed to its initial set, containing a specific array of items depending on the current site.
 *
 *  Inserts featured section as well as related sections from saved and/or history to the @c startingSchema.
 *
 *  @see startingSchema
 */
- (void)reset {
    NSMutableArray<WMFExploreSection*>* startingSchema = [[self startingSchema] mutableCopy];

    [startingSchema addObject:[self newMostReadSectionWithLatestPopulatedDate]];

    [startingSchema wmf_safeAddObject:[WMFExploreSection featuredArticleSectionWithSiteIfSupported:self.site]];

    WMFExploreSection* saved =
        [[self sectionsFromSavedEntriesExcludingExistingTitlesInSections:nil maxLength:1] firstObject];

    WMFExploreSection* recent =
        [[self sectionsFromHistoryEntriesExcludingExistingTitlesInSections:saved ? @[saved] : nil maxLength:1] firstObject];

    [startingSchema wmf_safeAddObject:recent];
    [startingSchema wmf_safeAddObject:saved];

    self.lastUpdatedAt = nil;
    [self updateSections:startingSchema];
}

/**
 *  Sections used to "seed" a user's "feed" with an initial set of content.
 *
 *  Omits certain sections which are not guaranteed to be available (e.g. featured articles & nearby).
 *
 *  @return An array of sections that can be used to start the "feed" from scratch.
 */
- (NSArray<WMFExploreSection*>*)startingSchema {
    return @[[WMFExploreSection mainPageSectionWithSite:self.site],
             [WMFExploreSection pictureOfTheDaySection],
             [WMFExploreSection randomSectionWithSite:self.site]];
}

#pragma mark - Location

- (WMFLocationManager*)locationManager {
    if (_locationManager == nil) {
        _locationManager          = [[WMFLocationManager alloc] init];
        _locationManager.delegate = self;
    }
    return _locationManager;
}

#pragma mark - Main Article

/*
 * This is required so we don't show items related to main pages in the feed.
 * Ideally, we would pull this info from a service - but for now this is the easiest way to do it.
 * Note: we can get main pages individually for each site via the API, but not in an aggregate call.
 */
- (WMFAssetsFile*)mainPages {
    if (!_mainPages) {
        _mainPages = [[WMFAssetsFile alloc] initWithFileType:WMFAssetsFileTypeMainPages];
    }

    return _mainPages;
}

- (MWKTitle*)mainArticleTitleForSite:(MWKSite*)site {
    if (!site.language) {
        return nil;
    }
    NSString* titleText = self.mainPages.dictionary[site.language];
    if (!titleText) {
        return nil;
    }
    return [site titleWithString:titleText];
}

- (BOOL)titleIsForMainArticle:(MWKTitle*)title {
    MWKTitle* mainArticleTitle = [self mainArticleTitleForSite:title.site];
    return ([title.text isEqualToString:mainArticleTitle.text]);
}

#pragma mark - Sections

- (void)updateSections:(NSArray<WMFExploreSection*>*)sections {
    self.sections = [sections sortedArrayWithOptions:NSSortStable usingComparator:^NSComparisonResult (WMFExploreSection* _Nonnull obj1, WMFExploreSection* _Nonnull obj2) {
        return [obj1 compare:obj2];
    }];
    [self.delegate sectionSchemaDidUpdateSections:self];
    [WMFExploreSectionSchema saveSchemaToDisk:self];
}

- (void)removeSection:(WMFExploreSection*)section {
    NSUInteger index = [self.sections indexOfObject:section];
    if (index == NSNotFound) {
        return;
    }
    NSMutableArray* sections = [self.sections mutableCopy];
    [sections removeObject:section];
    self.sections = sections;
    [self.delegate sectionSchema:self didRemoveSection:section atIndex:index];
    [WMFExploreSectionSchema saveSchemaToDisk:self];
}

#pragma mark - Update

- (void)updateSite:(MWKSite*)site {
    if ([site isEqual:self.site]) {
        return;
    }
    self.site = site;
    [self update:YES];
}

- (void)update {
    [self update:NO];
}

- (BOOL)update:(BOOL)force {
    [self.locationManager restartLocationMonitoring];

    if (!FBTweakValue(@"Explore", @"General", @"Always update on launch", NO)
        && !force
        && self.lastUpdatedAt
        && [[NSDate date] timeIntervalSinceDate:self.lastUpdatedAt] < WMFHomeMinimumAutomaticReloadTime) {
        return [self updateContinueReading];
    }


    //Get updated static sections
    NSMutableArray<WMFExploreSection*>* sections = [[self staticSections] mutableCopy];

    [sections addObjectsFromArray:[self featuredSections]];
    [sections addObjectsFromArray:[self mostReadSectionsWithUpdateIfNeeded]];
    [sections addObjectsFromArray:[self nearbySections]];

    //Add Saved and History
    NSArray<WMFExploreSection*>* recent = [self historyAndSavedPageSections];
    if ([recent count] > 0) {
        [sections addObjectsFromArray:recent];
    }

    self.lastUpdatedAt = [NSDate date];
    [self updateSections:sections];
    return YES;
}

- (BOOL)updateContinueReading {
    WMFExploreSection* old = [self existingContinueReadingSection];
    WMFExploreSection* new = [self continueReadingSection];
    if ([[old title] isEqual:[new title]]) {
        return NO;
    }

    //Get updated static sections
    NSMutableArray<WMFExploreSection*>* sections = [[self sections] mutableCopy];
    [sections removeObject:old];

    if (new) {
        [sections insertObject:new atIndex:0];
    }
    [self updateSections:sections];
    return YES;
}

- (void)insertNearbySectionWithLocationIfNeeded:(CLLocation*)location {
    NSParameterAssert(location);

    NSMutableArray<WMFExploreSection*>* existingNearbySections = [[self nearbySections] mutableCopy];
    
    WMFExploreSection* closeEnough = [existingNearbySections bk_match:^BOOL(WMFExploreSection* oldNearby) {
        
        //Don't add a new one if we have one that is minimum distance
        if (oldNearby.location && [location distanceFromLocation:oldNearby.location] < WMFMinimumDistanceBeforeUpdatingNearby && oldNearby.placemark != nil) {
            return YES;
        }

        //Don't add more than one more in a single day
        if (oldNearby.location && [oldNearby.dateCreated isToday] && oldNearby.placemark != nil) {
            return YES;
        }

        return NO;
    }];
    
    if(closeEnough != nil){
        return;
    }
    
    @weakify(self);
    [self reverseGeocodeLocation:location completionHandler:^(CLPlacemark* _Nullable placemark) {
        dispatchOnMainQueue(^{
            @strongify(self);

            NSMutableArray<WMFExploreSection*>* sections = [self.sections mutableCopy];
            [sections bk_performReject:^BOOL (WMFExploreSection* obj) {
                return obj.type == WMFExploreSectionTypeNearby;
            }];
            
            [existingNearbySections addObject:[self nearbySectionWithLocation:location placemark:placemark]];
            
            NSUInteger max = [WMFExploreSection maxNumberOfSectionsForType:WMFExploreSectionTypeNearby];
            
            [existingNearbySections sortWithOptions:NSSortStable
                      usingComparator:^NSComparisonResult (WMFExploreSection* _Nonnull obj1, WMFExploreSection* _Nonnull obj2) {
                          return -[obj1.dateCreated compare:obj2.dateCreated];
                      }];
            
            [existingNearbySections wmf_arrayByTrimmingToLength:max];
            [sections addObjectsFromArray:existingNearbySections];

            [self updateSections:sections];
        });
    }];
}

typedef void (^ WMFGeocodeCompletionHandler)(CLPlacemark* __nullable placemark);

- (void)reverseGeocodeLocation:(CLLocation*)location completionHandler:(nonnull WMFGeocodeCompletionHandler)completionHandler {
    CLGeocoder* gc = [[CLGeocoder alloc] init];
    [gc reverseGeocodeLocation:location completionHandler:^(NSArray < CLPlacemark* > * _Nullable placemarks, NSError* _Nullable error) {
        if (error) {
            completionHandler(nil);
            return;
        }

        completionHandler([placemarks firstObject]);
    }];
}

- (void)removeNearbySection {
    NSMutableArray<WMFExploreSection*>* sections = [self.sections mutableCopy];
    [sections bk_performReject:^BOOL (WMFExploreSection* obj) {
        return obj.type == WMFExploreSectionTypeNearby;
    }];
    [self updateSections:sections];
}

- (void)updateWithChangesInBlackList:(WMFRelatedSectionBlackList*)blackList {
    //enumerate in reverse so that indexes are always correct
    [[blackList.entries wmf_mapAndRejectNil:^id (MWKTitle* obj) {
        return [self existingSectionForTitle:obj];
    }] enumerateObjectsWithOptions:NSEnumerationReverse usingBlock:^(WMFExploreSection* _Nonnull obj, NSUInteger idx, BOOL* _Nonnull stop) {
        [self removeSection:obj];
    }];
}

#pragma mmrk - Section Creation

/**
 *  Sections which should always be present in the "feed" (i.e. everything that isn't site specific).
 *
 *  @return An array of all existing site-independent sections.
 */
- (NSArray<WMFExploreSection*>*)staticSections {
    NSMutableArray<WMFExploreSection*>* sections = [NSMutableArray array];

    [sections wmf_safeAddObject:[self randomSection]];
    [sections addObject:[self mainPageSection]];
    [sections addObject:[self picOfTheDaySection]];
    [sections wmf_safeAddObject:[self continueReadingSection]];

    return sections;
}

- (WMFExploreSection*)randomSection {
    WMFExploreSection* random = [self.sections bk_match:^BOOL (WMFExploreSection* obj) {
        if (obj.type == WMFExploreSectionTypeRandom && [obj.site isEqual:self.site]) {
            return YES;
        }
        return NO;
    }];

    MWKHistoryEntry* lastEntry = [self.historyPages.entries firstObject];
    if (lastEntry && [[NSDate date] timeIntervalSinceDate:lastEntry.date] > WMFTimeBeforeRefreshingRandom) {
        random = [WMFExploreSection randomSectionWithSite:self.site];
    }

    //Always return a random section
    if (!random) {
        random = [WMFExploreSection randomSectionWithSite:self.site];
    }

    return random;
}

- (NSArray<WMFExploreSection*>*)nearbySections{
    
    NSArray<WMFExploreSection*>* nearby = [self.sections bk_select:^BOOL (WMFExploreSection* obj) {
        if (obj.type == WMFExploreSectionTypeNearby && obj.location != nil && obj.site != nil) {
            return YES;
        }
        return NO;
    }];

    return nearby;
}

- (nullable WMFExploreSection*)nearbySectionWithLocation:(CLLocation*)location placemark:(nullable CLPlacemark*)placemark {
    NSParameterAssert(location);
    if (!location || [WMFLocationManager isDeniedOrDisabled]) {
        return nil;
    }
    return [WMFExploreSection nearbySectionWithLocation:location placemark:placemark site:self.site];
}

/**
 *  Retrieve an updated list of "most read" sections, incorporating prior ones.
 *
 *  Selects all "most read" sections from the receiver and, if possible, appends an additional section for the most
 *  recent data from the current site.
 *
 *  @return An array of "most read" sections that should be in an updated version of the receiver.
 */
- (NSArray<WMFExploreSection*>*)mostReadSectionsWithUpdateIfNeeded {
    NSMutableArray<WMFExploreSection*>* mostReadSections = [[self.sections bk_select:^BOOL (WMFExploreSection* section) {
        return section.type == WMFExploreSectionTypeMostRead;
    }] mutableCopy];

    WMFExploreSection* latestMostReadSection = [self newMostReadSectionWithLatestPopulatedDate];

    BOOL containsLatestSectionEquivalent = [mostReadSections bk_any:^BOOL (WMFExploreSection* mostReadSection) {
        BOOL const matchesDay = [[NSCalendar wmf_utcGregorianCalendar] compareDate:mostReadSection.dateCreated
                                                                            toDate:latestMostReadSection.dateCreated
                                                                 toUnitGranularity:NSCalendarUnitDay] == NSOrderedSame;
        BOOL const matchesSite = [mostReadSection.site isEqualToSite:latestMostReadSection.site];
        return matchesDay && matchesSite;
    }];

    if (!containsLatestSectionEquivalent) {
        [mostReadSections addObject:latestMostReadSection];
    }

    NSUInteger max = FBTweakValue(@"Explore", @"Sections", @"Max number of most read", [WMFExploreSection maxNumberOfSectionsForType:WMFExploreSectionTypeMostRead]);

    //Sort by date
    [mostReadSections sortWithOptions:NSSortStable
                      usingComparator:^NSComparisonResult (WMFExploreSection* _Nonnull obj1, WMFExploreSection* _Nonnull obj2) {
        return -[obj1.dateCreated compare:obj2.dateCreated];
    }];

    return [mostReadSections wmf_arrayByTrimmingToLength:max];
}

- (nullable WMFExploreSection*)newMostReadSectionWithLatestPopulatedDate {
    return [WMFExploreSection mostReadSectionForDate:[NSDate wmf_latestMostReadDataWithLikelyAvailableData]
                                                site:self.site];
}

- (NSArray<WMFExploreSection*>*)featuredSections {
    NSArray* existingFeaturedArticleSections = [self.sections bk_select:^BOOL (WMFExploreSection* obj) {
        return obj.type == WMFExploreSectionTypeFeaturedArticle;
    }];

    //Don't add new ones if we aren't in english
    NSMutableArray* featured = [existingFeaturedArticleSections mutableCopy];

    WMFExploreSection* today = [featured bk_match:^BOOL (WMFExploreSection* obj) {
        NSAssert(obj.type == WMFExploreSectionTypeFeaturedArticle,
                 @"List should only contain featured sections, got %@", featured);
        return [obj.dateCreated isToday];
    }];

    if (!today) {
        [featured wmf_safeAddObject:[WMFExploreSection featuredArticleSectionWithSiteIfSupported:self.site]];
    }

    NSUInteger max = FBTweakValue(@"Explore", @"Sections", @"Max number of featured", [WMFExploreSection maxNumberOfSectionsForType:WMFExploreSectionTypeFeaturedArticle]);

    //Sort by date
    [featured sortWithOptions:NSSortStable
              usingComparator:^NSComparisonResult (WMFExploreSection* _Nonnull obj1, WMFExploreSection* _Nonnull obj2) {
        return -[obj1.dateCreated compare:obj2.dateCreated];
    }];

    return [featured wmf_arrayByTrimmingToLength:max];
}

- (WMFExploreSection*)mainPageSection {
    WMFExploreSection* main = [self.sections bk_match:^BOOL (WMFExploreSection* obj) {
        if (obj.type == WMFExploreSectionTypeMainPage && [obj.site isEqual:self.site]) {
            return YES;
        }
        return NO;
    }];

    //If it's a new day and we havent created a new main page section, create it now
    if ([main.dateCreated isToday] && [main.site isEqual:self.site]) {
        return main;
    }

    return [WMFExploreSection mainPageSectionWithSite:self.site];
}

- (WMFExploreSection*)picOfTheDaySection {
    WMFExploreSection* existingSection = [self.sections bk_match:^BOOL (WMFExploreSection* obj) {
        if (obj.type == WMFExploreSectionTypePictureOfTheDay) {
            return YES;
        }
        return NO;
    }];

    //If it's a new day and we havent created a new main page section, create it now
    if ([existingSection.dateCreated isToday]) {
        return existingSection;
    }

    return [WMFExploreSection pictureOfTheDaySection];
}

- (nullable WMFExploreSection*)continueReadingSection {
    NSDate* resignActiveDate             = [[NSUserDefaults standardUserDefaults] wmf_appResignActiveDate];
    BOOL const shouldShowContinueReading =
        FBTweakValue(@"Explore", @"Continue Reading", @"Always Show", NO) ||
        fabs([resignActiveDate timeIntervalSinceNow]) >= WMFTimeBeforeDisplayingLastReadArticle;

    //Only return if
    if (shouldShowContinueReading) {
        MWKTitle* lastRead = [[NSUserDefaults standardUserDefaults] wmf_openArticleTitle];
        if (lastRead) {
            return [WMFExploreSection continueReadingSectionWithTitle:lastRead];
        }
    }
    return nil;
}

- (nullable)existingContinueReadingSection {
    return [self.sections bk_match:^BOOL (WMFExploreSection* obj) {
        if (obj.type == WMFExploreSectionTypeContinueReading) {
            return YES;
        }
        return NO;
    }];
}

- (nullable WMFExploreSection*)existingSectionForTitle:(MWKTitle*)title {
    return [self.sections bk_match:^BOOL (WMFExploreSection* obj) {
        if ([obj.title isEqualToTitle:title]) {
            return YES;
        }
        return NO;
    }];
}

- (NSArray<WMFExploreSection*>*)historyAndSavedPageSections {
    NSMutableArray<WMFExploreSection*>* sections = [NSMutableArray array];

    NSUInteger max = FBTweakValue(@"Explore", @"Sections", @"Max number of history/saved", [WMFExploreSection maxNumberOfSectionsForType:WMFExploreSectionTypeSaved] + [WMFExploreSection maxNumberOfSectionsForType:WMFExploreSectionTypeHistory]);

    NSArray<WMFExploreSection*>* saved   = [self sectionsFromSavedEntriesExcludingExistingTitlesInSections:nil maxLength:max];
    NSArray<WMFExploreSection*>* history = [self sectionsFromHistoryEntriesExcludingExistingTitlesInSections:saved maxLength:max];

    [sections addObjectsFromArray:saved];
    [sections addObjectsFromArray:history];

    //Sort by date
    [sections sortWithOptions:NSSortStable | NSSortConcurrent usingComparator:^NSComparisonResult (WMFExploreSection* _Nonnull obj1, WMFExploreSection* _Nonnull obj2) {
        return -[obj1.dateCreated compare:obj2.dateCreated];
    }];

    return [sections wmf_arrayByTrimmingToLength:max];
}

- (NSArray<WMFExploreSection*>*)sectionsFromHistoryEntriesExcludingExistingTitlesInSections:(nullable NSArray<WMFExploreSection*>*)existingSections maxLength:(NSUInteger)maxLength {
    NSArray<MWKTitle*>* existingTitles = [existingSections valueForKeyPath:WMF_SAFE_KEYPATH([WMFExploreSection new], title)];

    NSArray<MWKHistoryEntry*>* entries = [self.historyPages.entries bk_select:^BOOL (MWKHistoryEntry* obj) {
        return obj.titleWasSignificantlyViewed;
    }];

    entries = [entries bk_reject:^BOOL (MWKHistoryEntry* obj) {
        return [self.blackList titleIsBlackListed:obj.title];
    }];

    entries = [entries wmf_arrayByTrimmingToLength:maxLength + [existingSections count]];

    entries = [entries bk_reject:^BOOL (MWKHistoryEntry* obj) {
        return [self titleIsForMainArticle:obj.title] || [existingTitles containsObject:obj.title];
    }];

    return [[entries bk_map:^id (MWKHistoryEntry* obj) {
        return [WMFExploreSection historySectionWithHistoryEntry:obj];
    }] wmf_arrayByTrimmingToLength:maxLength];
}

- (NSArray<WMFExploreSection*>*)sectionsFromSavedEntriesExcludingExistingTitlesInSections:(nullable NSArray<WMFExploreSection*>*)existingSections maxLength:(NSUInteger)maxLength {
    NSArray<MWKTitle*>* existingTitles = [existingSections valueForKeyPath:WMF_SAFE_KEYPATH([WMFExploreSection new], title)];

    NSArray<MWKHistoryEntry*>* entries = [self.savedPages.entries bk_reject:^BOOL (MWKHistoryEntry* obj) {
        return [self.blackList titleIsBlackListed:obj.title];
    }];

    entries = [entries wmf_arrayByTrimmingToLength:maxLength + [existingSections count]];

    entries = [entries bk_reject:^BOOL (MWKHistoryEntry* obj) {
        return [self titleIsForMainArticle:obj.title] || [existingTitles containsObject:obj.title];
    }];

    return [[entries bk_map:^id (MWKSavedPageEntry* obj) {
        return [WMFExploreSection savedSectionWithSavedPageEntry:obj];
    }] wmf_arrayByTrimmingToLength:maxLength];
}

#pragma mark - WMFLocationManagerDelegate

- (void)nearbyController:(WMFLocationManager*)controller didChangeEnabledState:(BOOL)enabled {
    if (!enabled) {
        [self updateSections:
         [self.sections filteredArrayUsingPredicate:
          [NSPredicate predicateWithBlock:^BOOL (WMFExploreSection* _Nonnull evaluatedObject,
                                                 NSDictionary < NSString*, id > * _Nullable _) {
            return evaluatedObject.type != WMFExploreSectionTypeNearby;
        }]]];
    }
}

- (void)nearbyController:(WMFLocationManager*)controller didUpdateLocation:(CLLocation*)location {
    [self insertNearbySectionWithLocationIfNeeded:location];
}

- (void)nearbyController:(WMFLocationManager*)controller didUpdateHeading:(CLHeading*)heading {
}

- (void)nearbyController:(WMFLocationManager*)controller didReceiveError:(NSError*)error {
    if ([WMFLocationManager isDeniedOrDisabled]) {
        [self removeNearbySection];
        [self.locationManager stopMonitoringLocation];
        return;
    }

    if (![error.domain isEqualToString:kCLErrorDomain] && error.code == kCLErrorLocationUnknown) {
        //TODO: anything we need to handle here?
    }
}

#pragma mark - Persistance

+ (NSDictionary*)encodingBehaviorsByPropertyKey {
    NSMutableDictionary* behaviors = [[super encodingBehaviorsByPropertyKey] mutableCopy];
    [behaviors setObject:@(MTLModelEncodingBehaviorExcluded) forKey:@"site"];
    [behaviors setObject:@(MTLModelEncodingBehaviorExcluded) forKey:@"savedPages"];
    [behaviors setObject:@(MTLModelEncodingBehaviorExcluded) forKey:@"historyPages"];
    [behaviors setObject:@(MTLModelEncodingBehaviorExcluded) forKey:@"mainPages"];
    [behaviors setObject:@(MTLModelEncodingBehaviorExcluded) forKey:@"delegate"];
    [behaviors setObject:@(MTLModelEncodingBehaviorExcluded) forKey:@"locationManager"];
    [behaviors setObject:@(MTLModelEncodingBehaviorExcluded) forKey:@"locationRequestStarted"];
    [behaviors setObject:@(MTLModelEncodingBehaviorExcluded) forKey:@"blackList"];

    return behaviors;
}

+ (NSURL*)schemaFileURL {
    return [NSURL fileURLWithPath:[[documentsDirectory() stringByAppendingPathComponent:WMFExploreSectionsFileName] stringByAppendingPathExtension:WMFExploreSectionsFileExtension]];
}

+ (void)saveSchemaToDisk:(WMFExploreSectionSchema*)schema {
    dispatchOnBackgroundQueue(^{
        if (![NSKeyedArchiver archiveRootObject:schema toFile:[[self schemaFileURL] path]]) {
            //TODO: not sure what to do with an error here
            DDLogError(@"Failed to save sections to disk!");
        }
    });
}

+ (WMFExploreSectionSchema*)loadSchemaFromDisk {
    //Need to map old class names
    [NSKeyedUnarchiver setClass:[WMFExploreSectionSchema class] forClassName:@"WMFHomeSectionSchema"];
    [NSKeyedUnarchiver setClass:[WMFExploreSection class] forClassName:@"WMFHomeSection"];

    return [NSKeyedUnarchiver unarchiveObjectWithFile:[[self schemaFileURL] path]];
}

@end

NS_ASSUME_NONNULL_END
