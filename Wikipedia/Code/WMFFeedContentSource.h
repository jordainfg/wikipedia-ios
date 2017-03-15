#import "WMFContentSource.h"

@class WMFContentGroupDataStore;
@class WMFArticleDataStore;
@class WMFNotificationsController;
@class MWKDataStore;
@class WMFFeedNewsStory;
@class WMFFeedDayResponse;
@class WMFArticle;

NS_ASSUME_NONNULL_BEGIN

extern NSInteger const WMFFeedNotificationMinHour;
extern NSInteger const WMFFeedNotificationMaxHour;
extern NSInteger const WMFFeedNotificationMaxPerDay;

@interface WMFFeedContentSource : NSObject <WMFContentSource, WMFDateBasedContentSource>

@property (readonly, nonatomic, strong) NSURL *siteURL;

@property (nonatomic, getter=isNotificationSchedulingEnabled) BOOL notificationSchedulingEnabled;

@property (readonly, nonatomic, strong) WMFContentGroupDataStore *contentStore;
@property (readonly, nonatomic, strong) WMFArticleDataStore *previewStore;

- (instancetype)initWithSiteURL:(NSURL *)siteURL contentGroupDataStore:(WMFContentGroupDataStore *)contentStore articlePreviewDataStore:(WMFArticleDataStore *)previewStore userDataStore:(MWKDataStore *)userDataStore notificationsController:(nullable WMFNotificationsController *)notificationsController;

- (instancetype)init NS_UNAVAILABLE;

- (BOOL)scheduleNotificationForNewsStory:(WMFFeedNewsStory *)newsStory articlePreview:(WMFArticle *)articlePreview force:(BOOL)force;

//Use this method to fetch content directly. Using this will not persist the results
- (void)fetchContentForDate:(NSDate *)date force:(BOOL)force completion:(void (^)(WMFFeedDayResponse *__nullable feedResponse, NSDictionary<NSURL *, NSDictionary<NSDate *, NSNumber *> *> *__nullable pageViews))completion;

@end

NS_ASSUME_NONNULL_END
