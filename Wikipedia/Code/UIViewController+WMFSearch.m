#import "UIViewController+WMFSearch.h"
#import "WMFSearchViewController.h"
#import "SessionSingleton.h"
#import "WMFArticleDataStore.h"
#import "Wikipedia-Swift.h"
@import BlocksKitUIKitExtensions;

NS_ASSUME_NONNULL_BEGIN

@implementation UIViewController (WMFSearchButton)

static MWKDataStore *_dataStore = nil;
static WMFArticleDataStore *_previewStore = nil;

static WMFSearchViewController *_Nullable _sharedSearchViewController = nil;

+ (void)wmf_setSearchButtonDataStore:(MWKDataStore *)dataStore {
    NSParameterAssert(dataStore);
    _dataStore = dataStore;
    [self wmf_clearSearchViewController];
}

+ (void)wmf_setSearchButtonPreviewStore:(WMFArticleDataStore *)previewStore {
    NSParameterAssert(previewStore);
    _previewStore = previewStore;
    [self wmf_clearSearchViewController];
}

+ (void)wmf_clearSearchViewController {
    _sharedSearchViewController = nil;
}

+ (WMFSearchViewController *)wmf_sharedSearchViewController {
    return _sharedSearchViewController;
}

+ (void)load {
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(wmfSearchButton_applicationDidEnterBackgroundWithNotification:)
                                                 name:UIApplicationDidEnterBackgroundNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(wmfSearchButton_applicationDidReceiveMemoryWarningWithNotification:)
                                                 name:UIApplicationDidReceiveMemoryWarningNotification
                                               object:nil];
}

+ (void)wmfSearchButton_applicationDidEnterBackgroundWithNotification:(NSNotification *)note {
    [self wmf_clearSearchViewController];
}

+ (void)wmfSearchButton_applicationDidReceiveMemoryWarningWithNotification:(NSNotification *)note {
    [self wmf_clearSearchViewController];
}

- (UIBarButtonItem *)wmf_searchBarButtonItem {
    return [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"search"] style:UIBarButtonItemStylePlain target:self action:@selector(wmf_showSearch)];
}

- (void)wmf_showSearch {
    [self wmf_showSearchAnimated:YES];
}

- (void)wmf_showSearchAnimated:(BOOL)animated {
    NSParameterAssert(_dataStore);

    if (!_sharedSearchViewController) {
        WMFSearchViewController *searchVC =
            [WMFSearchViewController searchViewControllerWithDataStore:_dataStore
                                                          previewStore:_previewStore];
        _sharedSearchViewController = searchVC;
    }
    [self presentViewController:_sharedSearchViewController animated:animated completion:nil];
}

@end

NS_ASSUME_NONNULL_END
