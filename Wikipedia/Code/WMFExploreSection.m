
#import "WMFExploreSection.h"
#import "MWKSite.h"
#import "MWKTitle.h"
#import "MWKHistoryEntry.h"
#import "MWKSavedPageEntry.h"
#import "NSDate+Utilities.h"
#import "WMFLocationManager.h"

NS_ASSUME_NONNULL_BEGIN

@interface WMFExploreSection ()

@property (nonatomic, assign, readwrite) WMFExploreSectionType type;
@property (nonatomic, strong, readwrite) MWKSite* site;
@property (nonatomic, strong, readwrite) MWKTitle* title;
@property (nonatomic, strong, readwrite) NSDate* dateCreated;
@property (nonatomic, strong, readwrite) CLLocation* location;

@end

@implementation WMFExploreSection

- (instancetype)init {
    self = [super init];
    if (self) {
        self.dateCreated = [NSDate date];
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder*)coder {
    self = [super initWithCoder:coder];
    if (self) {
        //site was added after persistence. We need to provide a default value.
        if (self.type == WMFExploreSectionTypeFeaturedArticle && self.site == nil) {
            self.site = [MWKSite siteWithLanguage:@"en"];
        }
    }
    return self;
}

/**
 *  Provides the index of the receiver's item, specifying its ordering with other item types within its @c dateCreated.
 *
 *  @return A positive integer which, when compared with other items' indices, will yield the comparison result describing
 *          their ordering.
 */
- (NSInteger)dailyOrderingIndex {
    switch (self.type) {
        case WMFExploreSectionTypeContinueReading:
            return 0;
        case WMFExploreSectionTypeFeaturedArticle:
            return 1;
        case WMFExploreSectionTypeTrending:
            return 2;
        case WMFExploreSectionTypeMainPage:
            return 3;
        case WMFExploreSectionTypePictureOfTheDay:
            return 4;
        case WMFExploreSectionTypeRandom:
            return 5;
        case WMFExploreSectionTypeNearby:
            return 6;

        case WMFExploreSectionTypeSaved:
        case WMFExploreSectionTypeHistory:
            // Saved & History have identical same-day sorting behavior
            return 7;
    }
}

- (NSComparisonResult)compare:(WMFExploreSection*)section {
    NSParameterAssert([section isKindOfClass:[WMFExploreSection class]]);
    if (self.type == WMFExploreSectionTypeContinueReading) {
        // continue reading always goes above everything else, regardless of date
        return NSOrderedAscending;
    } else if (section.type == WMFExploreSectionTypeContinueReading) {
        // corollary of above, everything else always goes below continue reading, regardless of date
        return NSOrderedDescending;
    } else if (self.type != WMFExploreSectionTypeSaved
               && section.type != WMFExploreSectionTypeSaved
               && self.type != WMFExploreSectionTypeHistory
               && section.type != WMFExploreSectionTypeHistory
               && [self.dateCreated isEqualToDateIgnoringTime:section.dateCreated]) {
        // explicit ordering for non-history/-saved items created w/in the same day
        NSInteger selfOrderingIndex  = [self dailyOrderingIndex];
        NSInteger otherOrderingIndex = [section dailyOrderingIndex];
        if (selfOrderingIndex > otherOrderingIndex) {
            return NSOrderedDescending;
        } else if (selfOrderingIndex < otherOrderingIndex) {
            return NSOrderedAscending;
        } else {
            return NSOrderedSame;
        }
    } else {
        // sort all items from different days and/or history/saved items by date, descending
        return -[self.dateCreated compare:section.dateCreated];
    }
}

#pragma mark - Factory Methods

+ (instancetype)trendingSectionForDate:(NSDate *)date {
    WMFExploreSection* trending = [[WMFExploreSection alloc] init];
    trending.type = WMFExploreSectionTypeTrending;
    trending.dateCreated = date;
    return trending;
}

+ (instancetype)pictureOfTheDaySection {
    WMFExploreSection* item = [[WMFExploreSection alloc] init];
    item.type = WMFExploreSectionTypePictureOfTheDay;
    return item;
}

+ (instancetype)continueReadingSectionWithTitle:(MWKTitle*)title {
    WMFExploreSection* item = [[WMFExploreSection alloc] init];
    item.type  = WMFExploreSectionTypeContinueReading;
    item.title = title;
    return item;
}

+ (nullable instancetype)featuredArticleSectionWithSiteIfSupported:(MWKSite*)site {
    NSParameterAssert(site);
    if (![site.language isEqualToString:@"en"] || ![site.domain isEqualToString:@"wikipedia.org"]) {
        /*
           HAX: "Today's Featured Article" template is only available on en.wikipedia.org.
         */
        return nil;
    }
    WMFExploreSection* item = [[WMFExploreSection alloc] init];
    item.type = WMFExploreSectionTypeFeaturedArticle;
    item.site = site;
    return item;
}

+ (instancetype)mainPageSection {
    WMFExploreSection* item = [[WMFExploreSection alloc] init];
    item.type = WMFExploreSectionTypeMainPage;
    return item;
}

+ (nullable instancetype)nearbySectionWithLocation:(nullable CLLocation*)location {
    if ([WMFLocationManager isDeniedOrDisabled]) {
        return nil;
    }
    WMFExploreSection* item = [[WMFExploreSection alloc] init];
    item.type     = WMFExploreSectionTypeNearby;
    item.location = location;
    return item;
}

+ (instancetype)randomSection {
    WMFExploreSection* item = [[WMFExploreSection alloc] init];
    item.type = WMFExploreSectionTypeRandom;
    return item;
}

+ (instancetype)historySectionWithHistoryEntry:(MWKHistoryEntry*)entry {
    NSParameterAssert(entry.title);
    NSParameterAssert(entry.date);
    WMFExploreSection* item = [[WMFExploreSection alloc] init];
    item.type        = WMFExploreSectionTypeHistory;
    item.title       = entry.title;
    item.dateCreated = entry.date;
    return item;
}

+ (instancetype)savedSectionWithSavedPageEntry:(MWKSavedPageEntry*)entry {
    NSParameterAssert(entry.title);
    NSParameterAssert(entry.date);
    WMFExploreSection* item = [[WMFExploreSection alloc] init];
    item.type        = WMFExploreSectionTypeSaved;
    item.title       = entry.title;
    item.dateCreated = entry.date;
    return item;
}

@end

NS_ASSUME_NONNULL_END
