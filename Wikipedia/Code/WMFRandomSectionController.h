#import "WMFBaseExploreSectionController.h"

NS_ASSUME_NONNULL_BEGIN

extern NSString *const WMFRandomSectionIdentifier;

@interface WMFRandomSectionController : WMFBaseExploreSectionController <WMFExploreSectionController, WMFTitleProviding, WMFHeaderActionProviding, WMFMoreFooterProviding, WMFAnalyticsContentTypeProviding>

- (instancetype)initWithSearchSiteURL:(NSURL *)url dataStore:(MWKDataStore *)dataStore;

- (instancetype)initWithDataStore:(MWKDataStore *)dataStore NS_UNAVAILABLE;

- (instancetype)initWithDataStore:(MWKDataStore *)dataStore items:(NSArray *)items NS_UNAVAILABLE;

@property(nonatomic, strong, readonly) NSURL *searchSiteURL;

@end

NS_ASSUME_NONNULL_END