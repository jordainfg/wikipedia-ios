#import "WMFContentGroup+WMFFeedContentDisplaying.h"
#import "WMFAnnouncement.h"

NS_ASSUME_NONNULL_BEGIN

@implementation WMFContentGroup (WMFContentManaging)

- (nullable UIImage *)headerIcon {
    switch (self.contentGroupKind) {
        case WMFContentGroupKindContinueReading:
            return [UIImage imageNamed:@"home-continue-reading-mini"];
        case WMFContentGroupKindMainPage:
            return [UIImage imageNamed:@"news-mini"];
        case WMFContentGroupKindRelatedPages:
            return [UIImage imageNamed:@"recent-mini"];
        case WMFContentGroupKindLocation:
            return [UIImage imageNamed:@"nearby-mini"];
        case WMFContentGroupKindLocationPlaceholder:
            return [UIImage imageNamed:@"nearby-mini"];
        case WMFContentGroupKindPictureOfTheDay:
            return [UIImage imageNamed:@"potd-mini"];
        case WMFContentGroupKindRandom:
            return [UIImage imageNamed:@"random-mini"];
        case WMFContentGroupKindFeaturedArticle:
            return [UIImage imageNamed:@"featured-mini"];
        case WMFContentGroupKindTopRead:
            return [UIImage imageNamed:@"trending-mini"];
        case WMFContentGroupKindNews:
            return [UIImage imageNamed:@"news-mini"];
        case WMFContentGroupKindNotification:
            break;
        case WMFContentGroupKindAnnouncement:
            break;
        case WMFContentGroupKindUnknown:
        default:
            break;
    }
    return nil;
}

- (nullable UIColor *)headerIconTintColor {
    switch (self.contentGroupKind) {
        case WMFContentGroupKindContinueReading:
            break;
        case WMFContentGroupKindMainPage:
            break;
        case WMFContentGroupKindRelatedPages:
            break;
        case WMFContentGroupKindLocation:
            break;
        case WMFContentGroupKindLocationPlaceholder:
            break;
        case WMFContentGroupKindPictureOfTheDay:
            break;
        case WMFContentGroupKindRandom:
            break;
        case WMFContentGroupKindFeaturedArticle:
            return [UIColor wmf_colorWithHex:0xE6B84F alpha:1.0];
        case WMFContentGroupKindTopRead:
            return [UIColor wmf_blueTint];
        case WMFContentGroupKindNews:
            break;
        case WMFContentGroupKindNotification:
            break;
        case WMFContentGroupKindAnnouncement:
            return nil;
        case WMFContentGroupKindUnknown:
        default:
            break;
    }
    return [UIColor wmf_exploreSectionHeaderIconTint];
}

- (nullable UIColor *)headerIconBackgroundColor {
    switch (self.contentGroupKind) {
        case WMFContentGroupKindContinueReading:
            break;
        case WMFContentGroupKindMainPage:
            break;
        case WMFContentGroupKindRelatedPages:
            break;
        case WMFContentGroupKindLocation:
            break;
        case WMFContentGroupKindLocationPlaceholder:
            break;
        case WMFContentGroupKindPictureOfTheDay:
            break;
        case WMFContentGroupKindRandom:
            break;
        case WMFContentGroupKindFeaturedArticle:
            return [UIColor wmf_colorWithHex:0xFCF5E4 alpha:1.0];
        case WMFContentGroupKindTopRead:
            return [UIColor wmf_lightBlueTint];
        case WMFContentGroupKindNews:
            return [UIColor wmf_exploreSectionHeaderIconBackground];
        case WMFContentGroupKindNotification:
            break;
        case WMFContentGroupKindAnnouncement:
            return nil;
        case WMFContentGroupKindUnknown:
        default:
            break;
    }
    return [UIColor wmf_exploreSectionHeaderIconBackground];
}

- (nullable NSString *)headerTitle {
    switch (self.contentGroupKind) {
        case WMFContentGroupKindContinueReading:
            return MWLocalizedString(@"explore-continue-reading-heading", nil);
        case WMFContentGroupKindMainPage:
            return MWLocalizedString(@"explore-main-page-heading", nil);
        case WMFContentGroupKindRelatedPages:
            return MWLocalizedString(@"explore-continue-related-heading", nil);
        case WMFContentGroupKindLocation:
            return MWLocalizedString(@"explore-nearby-heading", nil);
        case WMFContentGroupKindLocationPlaceholder:
            return MWLocalizedString(@"explore-nearby-placeholder-heading", nil);
        case WMFContentGroupKindPictureOfTheDay:
            return MWLocalizedString(@"explore-potd-heading", nil);
        case WMFContentGroupKindRandom:
            return MWLocalizedString(@"explore-random-article-heading", nil);
        case WMFContentGroupKindFeaturedArticle:
            return MWLocalizedString(@"explore-featured-article-heading", nil);
        case WMFContentGroupKindTopRead:
            return [self stringWithLocalizedCurrentSiteLanguageReplacingPlaceholderInString:MWLocalizedString(@"explore-most-read-heading", nil) fallingBackOnGenericString:MWLocalizedString(@"explore-most-read-generic-heading", nil)];
        case WMFContentGroupKindNews:
            return MWLocalizedString(@"in-the-news-title", nil);
        case WMFContentGroupKindNotification:
            break;
        case WMFContentGroupKindAnnouncement:
            break;
        case WMFContentGroupKindUnknown:
        default:
            break;
    }
    return [[NSString alloc] init];
}

- (NSString *)stringWithLocalizedCurrentSiteLanguageReplacingPlaceholderInString:(NSString *)string fallingBackOnGenericString:(NSString *)genericString {
    // fall back to language code if it can't be localized
    NSString *language = [[NSLocale currentLocale] wmf_localizedLanguageNameForCode:self.siteURL.wmf_language];

    NSString *result = nil;

    //crash protection if language is nil
    if (language) {
        result = [string stringByReplacingOccurrencesOfString:@"$1" withString:language];
    } else {
        result = genericString;
    }
    return result;
}

- (nullable NSString *)headerSubTitle {
    switch (self.contentGroupKind) {
        case WMFContentGroupKindContinueReading: {
            NSString *relativeTimeString = [self.date wmf_relativeTimestamp];
            return [relativeTimeString wmf_stringByCapitalizingFirstCharacter];
        } break;
        case WMFContentGroupKindMainPage:
            return [[NSDateFormatter wmf_dayNameMonthNameDayOfMonthNumberDateFormatter] stringFromDate:[NSDate date]];
            break;
        case WMFContentGroupKindRelatedPages:
            return self.articleURL.wmf_title;
        case WMFContentGroupKindLocation: {
            if (self.isForToday) {
                return MWLocalizedString(@"explore-nearby-sub-heading-your-location", nil);
            } else if (self.placemark) {
                return [NSString stringWithFormat:@"%@, %@", self.placemark.name, self.placemark.locality];
            } else {
                return [NSString stringWithFormat:@"%f, %f", self.location.coordinate.latitude, self.location.coordinate.longitude];
            }
        } break;
        case WMFContentGroupKindLocationPlaceholder:
            return [self stringWithLocalizedCurrentSiteLanguageReplacingPlaceholderInString:MWLocalizedString(@"explore-nearby-placeholder-sub-heading-on-language-wikipedia", nil) fallingBackOnGenericString:MWLocalizedString(@"explore-nearby-placeholder-sub-heading-on-wikipedia", nil)];
        case WMFContentGroupKindPictureOfTheDay:
            return [[NSDateFormatter wmf_dayNameMonthNameDayOfMonthNumberDateFormatter] stringFromDate:self.date];
        case WMFContentGroupKindRandom:
            return MWSiteLocalizedString(self.siteURL, @"onboarding-wikipedia", nil);
        case WMFContentGroupKindFeaturedArticle:
            return [[NSDateFormatter wmf_dayNameMonthNameDayOfMonthNumberDateFormatter] stringFromDate:self.date];
        case WMFContentGroupKindTopRead: {
            NSString *dateString = [self localContentDateDisplayString];
            if (!dateString) {
                dateString = @"";
            }

            return dateString;
        }
        case WMFContentGroupKindNews:
            return [self localDateDisplayString];
        case WMFContentGroupKindNotification:
            break;
        case WMFContentGroupKindAnnouncement:
            break;
        case WMFContentGroupKindUnknown:
        default:
            break;
    }
    return [[NSString alloc] init];
}

- (nullable UIColor *)headerTitleColor {
    switch (self.contentGroupKind) {
        case WMFContentGroupKindContinueReading:
            return [UIColor wmf_exploreSectionHeaderTitle];
        case WMFContentGroupKindMainPage:
            return [UIColor wmf_exploreSectionHeaderTitle];
        case WMFContentGroupKindRelatedPages:
            return [UIColor wmf_exploreSectionHeaderTitle];
        case WMFContentGroupKindLocation:
            return [UIColor wmf_exploreSectionHeaderTitle];
        case WMFContentGroupKindLocationPlaceholder:
            return [UIColor wmf_exploreSectionHeaderTitle];
        case WMFContentGroupKindPictureOfTheDay:
            return [UIColor wmf_exploreSectionHeaderTitle];
        case WMFContentGroupKindRandom:
            return [UIColor wmf_exploreSectionHeaderTitle];
        case WMFContentGroupKindFeaturedArticle:
            return [UIColor wmf_exploreSectionHeaderTitle];
        case WMFContentGroupKindTopRead:
            return [UIColor wmf_exploreSectionHeaderTitle];
        case WMFContentGroupKindNews:
            return [UIColor wmf_exploreSectionHeaderTitle];
        case WMFContentGroupKindNotification:
            break;
        case WMFContentGroupKindAnnouncement:
            break;
        case WMFContentGroupKindUnknown:
        default:
            break;
    }
    return [UIColor blackColor];
}

- (nullable UIColor *)headerSubTitleColor {
    switch (self.contentGroupKind) {
        case WMFContentGroupKindContinueReading:
            return [UIColor wmf_exploreSectionHeaderSubTitle];
        case WMFContentGroupKindMainPage:
            return [UIColor wmf_exploreSectionHeaderSubTitle];
        case WMFContentGroupKindRelatedPages:
            return [UIColor wmf_blueTint];
        case WMFContentGroupKindLocation:
            return [UIColor wmf_exploreSectionHeaderSubTitle];
        case WMFContentGroupKindLocationPlaceholder:
            return [UIColor wmf_exploreSectionHeaderSubTitle];
        case WMFContentGroupKindPictureOfTheDay:
            return [UIColor wmf_exploreSectionHeaderSubTitle];
        case WMFContentGroupKindRandom:
            return [UIColor wmf_exploreSectionHeaderSubTitle];
        case WMFContentGroupKindFeaturedArticle:
            return [UIColor wmf_exploreSectionHeaderSubTitle];
        case WMFContentGroupKindTopRead:
            return [UIColor wmf_exploreSectionHeaderTitle];
        case WMFContentGroupKindNews:
            return [UIColor wmf_exploreSectionHeaderTitle];

        case WMFContentGroupKindNotification:
            break;
        case WMFContentGroupKindAnnouncement:
            break;
        case WMFContentGroupKindUnknown:
        default:
            break;
    }
    return [UIColor grayColor];
}

- (nullable NSURL *)headerContentURL {
    switch (self.contentGroupKind) {
        case WMFContentGroupKindContinueReading:
            break;
        case WMFContentGroupKindMainPage:
            break;
        case WMFContentGroupKindRelatedPages:
            return self.articleURL;
        case WMFContentGroupKindLocation:
            break;
        case WMFContentGroupKindLocationPlaceholder:
            break;
        case WMFContentGroupKindPictureOfTheDay:
            break;
        case WMFContentGroupKindRandom:
            break;
        case WMFContentGroupKindFeaturedArticle:
            break;
        case WMFContentGroupKindTopRead:
            break;
        case WMFContentGroupKindNews:
            break;
        case WMFContentGroupKindNotification:
            break;
        case WMFContentGroupKindAnnouncement:
            break;
        case WMFContentGroupKindUnknown:
        default:
            break;
    }
    return nil;
}

- (WMFFeedHeaderActionType)headerActionType {
    switch (self.contentGroupKind) {
        case WMFContentGroupKindContinueReading:
            break;
        case WMFContentGroupKindMainPage:
            break;
        case WMFContentGroupKindRelatedPages:
            return WMFFeedHeaderActionTypeOpenHeaderContent;
        case WMFContentGroupKindLocation:
            return WMFFeedHeaderActionTypeOpenMore;
        case WMFContentGroupKindLocationPlaceholder:
            break;
        case WMFContentGroupKindPictureOfTheDay:
            break;
        case WMFContentGroupKindRandom:
            break;
        case WMFContentGroupKindFeaturedArticle:
            break;
        case WMFContentGroupKindTopRead:
            return WMFFeedHeaderActionTypeOpenMore;
        case WMFContentGroupKindNews:
            return WMFFeedHeaderActionTypeOpenFirstItem;
        case WMFContentGroupKindNotification:
            break;
        case WMFContentGroupKindAnnouncement:
            return WMFFeedHeaderActionTypeOpenHeaderNone;
        case WMFContentGroupKindUnknown:
        default:
            break;
    }
    return WMFFeedHeaderActionTypeOpenFirstItem;
}

- (WMFFeedBlacklistOption)blackListOptions {
    switch (self.contentGroupKind) {
        case WMFContentGroupKindContinueReading:
            break;
        case WMFContentGroupKindMainPage:
            break;
        case WMFContentGroupKindRelatedPages:
            return WMFFeedBlacklistOptionContent;
        case WMFContentGroupKindLocation:
            break;
        case WMFContentGroupKindLocationPlaceholder:
            return WMFFeedBlacklistOptionSection;
        case WMFContentGroupKindPictureOfTheDay:
            break;
        case WMFContentGroupKindRandom:
            break;
        case WMFContentGroupKindFeaturedArticle:
            break;
        case WMFContentGroupKindTopRead:
            break;
        case WMFContentGroupKindNews:
            break;
        case WMFContentGroupKindNotification:
            break;
        case WMFContentGroupKindAnnouncement:
            break;
        case WMFContentGroupKindUnknown:
        default:
            break;
    }
    return WMFFeedBlacklistOptionNone;
}

- (WMFFeedDisplayType)displayType {
    switch (self.contentGroupKind) {
        case WMFContentGroupKindContinueReading:
            break;
        case WMFContentGroupKindMainPage:
            break;
        case WMFContentGroupKindRelatedPages:
            return WMFFeedDisplayTypePageWithPreview;
        case WMFContentGroupKindLocation:
            return WMFFeedDisplayTypePageWithLocation;
        case WMFContentGroupKindLocationPlaceholder:
            return WMFFeedDisplayTypePageWithLocation;
        case WMFContentGroupKindPictureOfTheDay:
            return WMFFeedDisplayTypePhoto;
        case WMFContentGroupKindRandom:
            return WMFFeedDisplayTypePageWithPreview;
        case WMFContentGroupKindFeaturedArticle:
            return WMFFeedDisplayTypePageWithPreview;
        case WMFContentGroupKindTopRead:
            break;
        case WMFContentGroupKindNews:
            return WMFFeedDisplayTypeStory;
        case WMFContentGroupKindNotification:
            break;
        case WMFContentGroupKindAnnouncement:
            return WMFFeedDisplayTypeAnnouncement;
        case WMFContentGroupKindUnknown:
        default:
            break;
    }
    return WMFFeedDisplayTypePage;
}

- (NSUInteger)maxNumberOfCells {
    switch (self.contentGroupKind) {
        case WMFContentGroupKindContinueReading:
            break;
        case WMFContentGroupKindMainPage:
            break;
        case WMFContentGroupKindRelatedPages:
            return 3;
        case WMFContentGroupKindLocation:
            return 3;
        case WMFContentGroupKindLocationPlaceholder:
            return 1;
        case WMFContentGroupKindPictureOfTheDay:
            break;
        case WMFContentGroupKindRandom:
            break;
        case WMFContentGroupKindFeaturedArticle:
            break;
        case WMFContentGroupKindTopRead:
            return 5;
        case WMFContentGroupKindNews:
            return 5;
        case WMFContentGroupKindNotification:
            break;
        case WMFContentGroupKindAnnouncement:
            return NSUIntegerMax;
        case WMFContentGroupKindUnknown:
        default:
            break;
    }
    return 1;
}

- (BOOL)prefersWiderColumn {
    switch (self.contentGroupKind) {
        case WMFContentGroupKindContinueReading:
            break;
        case WMFContentGroupKindMainPage:
            break;
        case WMFContentGroupKindRelatedPages:
            return YES /*FBTweakValue(@"Explore", @"General", @"Put 'Because You Read' in Wider Column", YES)*/;
        case WMFContentGroupKindLocation:
            break;
        case WMFContentGroupKindLocationPlaceholder:
            break;
        case WMFContentGroupKindPictureOfTheDay:
            return YES;
        case WMFContentGroupKindRandom:
            break;
        case WMFContentGroupKindFeaturedArticle:
            return YES;
        case WMFContentGroupKindTopRead:
            break;
        case WMFContentGroupKindNews:
            return YES;
        case WMFContentGroupKindNotification:
            break;
        case WMFContentGroupKindAnnouncement:
            return YES;
        case WMFContentGroupKindUnknown:
        default:
            break;
    }
    return NO;
}

- (WMFFeedDetailType)detailType {
    switch (self.contentGroupKind) {
        case WMFContentGroupKindContinueReading:
            break;
        case WMFContentGroupKindMainPage:
            break;
        case WMFContentGroupKindRelatedPages:
            break;
        case WMFContentGroupKindLocation:
            break;
        case WMFContentGroupKindLocationPlaceholder:
            break;
        case WMFContentGroupKindPictureOfTheDay:
            return WMFFeedDetailTypeGallery;
        case WMFContentGroupKindRandom:
            return WMFFeedDetailTypePageWithRandomButton;
        case WMFContentGroupKindFeaturedArticle:
            break;
        case WMFContentGroupKindTopRead:
            break;
        case WMFContentGroupKindNews:
            return WMFFeedDetailTypeStory;
        case WMFContentGroupKindNotification:
            break;
        case WMFContentGroupKindAnnouncement:
            return WMFFeedDetailTypeNone;
        case WMFContentGroupKindUnknown:
        default:
            break;
    }
    return WMFFeedDetailTypePage;
}

- (nullable NSString *)footerText {
    switch (self.contentGroupKind) {
        case WMFContentGroupKindContinueReading:
            break;
        case WMFContentGroupKindMainPage:
            break;
        case WMFContentGroupKindRelatedPages:
            return
                [MWLocalizedString(@"home-more-like-footer", nil) stringByReplacingOccurrencesOfString:@"$1"
                                                                                            withString:self.articleURL.wmf_title];
        case WMFContentGroupKindLocation: {
            if (self.isForToday) {
                return MWLocalizedString(@"home-nearby-footer", nil);
            } else {
                return [MWLocalizedString(@"home-nearby-location-footer", nil) stringByReplacingOccurrencesOfString:@"$1" withString:self.placemark.name];
            }
        }
        case WMFContentGroupKindLocationPlaceholder: {
            if (self.isForToday) {
                return MWLocalizedString(@"home-nearby-footer", nil);
            } else {
                return [MWLocalizedString(@"home-nearby-location-footer", nil) stringByReplacingOccurrencesOfString:@"$1" withString:self.placemark.name];
            }
        }
        case WMFContentGroupKindPictureOfTheDay:
            break;
        case WMFContentGroupKindRandom:
            return MWLocalizedString(@"explore-another-random", nil);
        case WMFContentGroupKindFeaturedArticle:
            break;
        case WMFContentGroupKindTopRead: {
            NSString *dateString = [self localContentDateShortDisplayString];
            if (!dateString) {
                dateString = @"";
            }

            return
                [MWLocalizedString(@"explore-most-read-footer-for-date", nil) stringByReplacingOccurrencesOfString:@"$1"
                                                                                                        withString:dateString];
        }
        case WMFContentGroupKindNews:
            break;
        case WMFContentGroupKindNotification:
            break;
        case WMFContentGroupKindAnnouncement:
            break;
        case WMFContentGroupKindUnknown:
        default:
            break;
    }
    return nil;
}

- (WMFFeedMoreType)moreType {
    switch (self.contentGroupKind) {
        case WMFContentGroupKindContinueReading:
            break;
        case WMFContentGroupKindMainPage:
            break;
        case WMFContentGroupKindRelatedPages:
            return WMFFeedMoreTypePageList;
        case WMFContentGroupKindLocation:
            return WMFFeedMoreTypePageListWithLocation;
        case WMFContentGroupKindLocationPlaceholder:
            return WMFFeedMoreTypeLocationAuthorization;
        case WMFContentGroupKindPictureOfTheDay:
            break;
        case WMFContentGroupKindRandom:
            return WMFFeedMoreTypePageWithRandomButton;
        case WMFContentGroupKindFeaturedArticle:
            break;
        case WMFContentGroupKindTopRead:
            return WMFFeedMoreTypePageList;
        case WMFContentGroupKindNews:
            break;
        case WMFContentGroupKindNotification:
            break;
        case WMFContentGroupKindAnnouncement:
            break;
        case WMFContentGroupKindUnknown:
        default:
            break;
    }
    return WMFFeedMoreTypeNone;
}

- (nullable NSString *)moreTitle {
    switch (self.contentGroupKind) {
        case WMFContentGroupKindContinueReading:
            break;
        case WMFContentGroupKindMainPage:
            break;
        case WMFContentGroupKindRelatedPages:
            return [MWLocalizedString(@"home-more-like-footer", nil) stringByReplacingOccurrencesOfString:@"$1" withString:self.articleURL.wmf_title];
        case WMFContentGroupKindLocation:
            return MWLocalizedString(@"main-menu-nearby", nil);
        case WMFContentGroupKindLocationPlaceholder:
            break;
        case WMFContentGroupKindPictureOfTheDay:
            break;
        case WMFContentGroupKindRandom:
            break;
        case WMFContentGroupKindFeaturedArticle:
            break;
        case WMFContentGroupKindTopRead:
            return [self topReadMoreTitleForDate:self.contentMidnightUTCDate];
        case WMFContentGroupKindNews:
            break;
        case WMFContentGroupKindNotification:
            break;
        case WMFContentGroupKindAnnouncement:
            break;
        case WMFContentGroupKindUnknown:
        default:
            break;
    }
    return nil;
}

- (nullable NSNumber *)analyticsValue {
    switch (self.contentGroupKind) {
        case WMFContentGroupKindContinueReading:
            break;
        case WMFContentGroupKindMainPage:
            break;
        case WMFContentGroupKindRelatedPages:
            break;
        case WMFContentGroupKindLocation:
            break;
        case WMFContentGroupKindLocationPlaceholder:
            break;
        case WMFContentGroupKindPictureOfTheDay:
            break;
        case WMFContentGroupKindRandom:
            break;
        case WMFContentGroupKindFeaturedArticle:
            break;
        case WMFContentGroupKindTopRead:
            break;
        case WMFContentGroupKindNews:
            break;
        case WMFContentGroupKindNotification:
            break;
        case WMFContentGroupKindAnnouncement: {
            static dispatch_once_t onceToken;
            static NSCharacterSet *nonNumericCharacterSet;
            dispatch_once(&onceToken, ^{
                nonNumericCharacterSet = [[NSCharacterSet decimalDigitCharacterSet] invertedSet];
            });

            WMFAnnouncement *_Nullable announcement = (WMFAnnouncement * _Nullable)self.content.firstObject;
            if (![announcement isKindOfClass:[WMFAnnouncement class]]) {
                return nil;
            }

            NSString *numberString = [announcement.identifier stringByTrimmingCharactersInSet:nonNumericCharacterSet];
            NSInteger integer = [numberString integerValue];
            return @(integer);
        }
        case WMFContentGroupKindUnknown:
        default:
            break;
    }

    return nil;
}

- (NSString *)analyticsContentType {
    switch (self.contentGroupKind) {
        case WMFContentGroupKindContinueReading:
            return @"Continue Reading";
        case WMFContentGroupKindMainPage:
            return @"Main Page";
        case WMFContentGroupKindRelatedPages:
            return @"Recommended";
        case WMFContentGroupKindLocation:
            return @"Nearby";
        case WMFContentGroupKindLocationPlaceholder:
            return @"Nearby Placeholder";
        case WMFContentGroupKindPictureOfTheDay:
            return @"Picture of the Day";
        case WMFContentGroupKindRandom:
            return @"Random";
        case WMFContentGroupKindFeaturedArticle:
            return @"Featured";
        case WMFContentGroupKindTopRead:
            return @"Most Read";
        case WMFContentGroupKindNews:
            return @"In The News";
        case WMFContentGroupKindNotification:
            return @"Notifications";
        case WMFContentGroupKindAnnouncement:
            return @"Announcement";
        case WMFContentGroupKindUnknown:
        default:
            break;
    }
    return @"Unknown Content Type";
}

- (WMFFeedHeaderType)headerType {
    switch (self.contentGroupKind) {
        case WMFContentGroupKindContinueReading:
            break;
        case WMFContentGroupKindMainPage:
            break;
        case WMFContentGroupKindRelatedPages:
            break;
        case WMFContentGroupKindLocation:
            break;
        case WMFContentGroupKindLocationPlaceholder:
            break;
        case WMFContentGroupKindPictureOfTheDay:
            break;
        case WMFContentGroupKindRandom:
            break;
        case WMFContentGroupKindFeaturedArticle:
            break;
        case WMFContentGroupKindTopRead:
            break;
        case WMFContentGroupKindNews:
            break;
        case WMFContentGroupKindNotification:
            return WMFFeedHeaderTypeNone;
        case WMFContentGroupKindAnnouncement:
            return WMFFeedHeaderTypeNone;
        case WMFContentGroupKindUnknown:
        default:
            break;
    }
    return WMFFeedHeaderTypeStandard;
}

/**
 *  String to display to the user for the receiver's date.
 *
 *  "Most read" articles are computed for UTC dates. UTC time zone is used because converting to the user's time zone
 *  might accidentally change the "day" the app displays based on the the offset between UTC & the device's default time
 *  zone.  For example: 02/12/2016 01:26 UTC converted to EST is 02/11/2016 20:26, one day off!
 *
 *  @return A string formatted with the current locale, in the UTC time zone.
 */
- (NSString *)localContentDateDisplayString {
    return [[NSDateFormatter wmf_utcDayNameMonthNameDayOfMonthNumberDateFormatter] stringFromDate:self.contentMidnightUTCDate];
}

- (NSString *)localContentDateShortDisplayString {
    return [[NSDateFormatter wmf_utcShortDayNameShortMonthNameDayOfMonthNumberDateFormatter] stringFromDate:self.contentMidnightUTCDate];
}

- (NSString *)topReadMoreTitleForDate:(NSDate *)date {
    return
        [MWLocalizedString(@"explore-most-read-more-list-title-for-date", nil) stringByReplacingOccurrencesOfString:@"$1"
                                                                                                         withString:
                                                                                                             [[NSDateFormatter wmf_utcShortDayNameShortMonthNameDayOfMonthNumberDateFormatter] stringFromDate:date]];
}

- (NSString *)localDateDisplayString {
    return [[NSDateFormatter wmf_utcDayNameMonthNameDayOfMonthNumberDateFormatter] stringFromDate:self.midnightUTCDate];
}

@end

NS_ASSUME_NONNULL_END
