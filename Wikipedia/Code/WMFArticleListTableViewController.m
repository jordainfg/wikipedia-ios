#import "WMFArticleListTableViewController.h"
#import "Wikipedia-Swift.h"
#import "UIViewController+WMFArticlePresentation.h"
@import WMF;

@interface WMFArticleListTableViewController () <UIViewControllerPreviewingDelegate, WMFArticlePreviewingActionsDelegate, WMFAnalyticsContextProviding>

@property (nonatomic, weak) id<UIViewControllerPreviewing> previewingContext;

@end

@implementation WMFArticleListTableViewController

#pragma mark - UIViewController

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return [self wmf_orientationMaskPortraitiPhoneAnyiPad];
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.extendedLayoutIncludesOpaqueBars = YES;
    self.automaticallyAdjustsScrollViewInsets = YES;

    self.tableView.estimatedRowHeight = [WMFArticleListTableViewCell estimatedRowHeight];
    self.tableView.rowHeight = UITableViewAutomaticDimension;

    //HACK: this is the only way to force the table view to hide separators when the table view is empty.
    //See: http://stackoverflow.com/a/5377805/48311
    self.tableView.tableFooterView = [[UIView alloc] initWithFrame:CGRectZero];
    [self registerForPreviewingIfAvailable];

    [self applyTheme:self.theme];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    NSParameterAssert(self.userDataStore);
    [self updateEmptyAndDeleteState];
}

- (void)traitCollectionDidChange:(nullable UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    [self registerForPreviewingIfAvailable];
}

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];

    [coordinator animateAlongsideTransition:^(id<UIViewControllerTransitionCoordinatorContext> context) {
        [self.tableView reloadData];
    }
                                 completion:NULL];
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [[PiwikTracker sharedInstance] wmf_logActionTapThroughInContext:self contentType:self];
    [self wmf_hideKeyboard];
    [self.tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSURL *url = [self urlAtIndexPath:indexPath];
    if (self.delegate) {
        [self.delegate listViewController:self didSelectArticleURL:url];
        return;
    }
    [self wmf_pushArticleWithURL:url dataStore:self.userDataStore theme:self.theme animated:YES];
}

#pragma mark - Previewing

- (void)registerForPreviewingIfAvailable {
    [self wmf_ifForceTouchAvailable:^{
        [self unregisterPreviewing];
        self.previewingContext = [self registerForPreviewingWithDelegate:self
                                                              sourceView:self.tableView];
    }
        unavailable:^{
            [self unregisterPreviewing];
        }];
}

- (void)unregisterPreviewing {
    if (self.previewingContext) {
        [self unregisterForPreviewingWithContext:self.previewingContext];
        self.previewingContext = nil;
    }
}

#pragma mark - UIViewControllerPreviewingDelegate

- (nullable UIViewController *)previewingContext:(id<UIViewControllerPreviewing>)previewingContext
                       viewControllerForLocation:(CGPoint)location {
    NSIndexPath *previewIndexPath = [self.tableView indexPathForRowAtPoint:location];
    if (!previewIndexPath) {
        return nil;
    }

    previewingContext.sourceRect = [self.tableView cellForRowAtIndexPath:previewIndexPath].frame;

    NSURL *url = [self urlAtIndexPath:previewIndexPath];
    [[PiwikTracker sharedInstance] wmf_logActionPreviewInContext:self contentType:self];

    UIViewController *vc = self.delegate ? [self.delegate listViewController:self viewControllerForPreviewingArticleURL:url] : [[WMFArticleViewController alloc] initWithArticleURL:url dataStore:self.userDataStore theme:self.theme];

    if ([vc conformsToProtocol:@protocol(WMFThemeable)]) {
        [(id<WMFThemeable>)vc applyTheme:self.theme];
    }

    if ([vc isKindOfClass:[WMFArticleViewController class]]) {
        ((WMFArticleViewController *)vc).articlePreviewingActionsDelegate = self;
    }
    return vc;
}

- (void)previewingContext:(id<UIViewControllerPreviewing>)previewingContext
     commitViewController:(UIViewController *)viewControllerToCommit {
    [self commitViewController:viewControllerToCommit];
}

- (void)commitViewController:(UIViewController *)viewControllerToCommit {
    [[PiwikTracker sharedInstance] wmf_logActionTapThroughInContext:self contentType:self];
    if (self.delegate) {
        [self.delegate listViewController:self didCommitToPreviewedViewController:viewControllerToCommit];
    } else {
        [self wmf_pushArticleViewController:(WMFArticleViewController *)viewControllerToCommit animated:YES];
    }
}

#pragma mark - WMFArticlePreviewingActionsDelegate

- (void)readMoreArticlePreviewActionSelectedWithArticleController:(WMFArticleViewController *)articleController {
    [self commitViewController:articleController];
}

- (void)shareArticlePreviewActionSelectedWithArticleController:(WMFArticleViewController *)articleController
                                       shareActivityController:(UIActivityViewController *)shareActivityController {
    [self presentViewController:shareActivityController animated:YES completion:NULL];
}

- (void)viewOnMapArticlePreviewActionSelectedWithArticleController:(WMFArticleViewController *)articleController {
    NSURL *placesURL = [NSUserActivity wmf_URLForActivityOfType:WMFUserActivityTypePlaces withArticleURL:articleController.articleURL];
    [[UIApplication sharedApplication] openURL:placesURL];
}

#pragma mark - Delete Button

- (void)updateDeleteButton {
    if ([self showsDeleteAllButton]) {
        if (self.navigationItem.leftBarButtonItem == nil) {
            self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:[self deleteButtonText] style:UIBarButtonItemStylePlain target:self action:@selector(deleteButtonPressed:)];
        }

        if (!self.isEmpty) {
            self.navigationItem.leftBarButtonItem.enabled = YES;
        } else {
            self.navigationItem.leftBarButtonItem.enabled = NO;
        }
    } else {
        self.navigationItem.leftBarButtonItem = nil;
    }
}

- (void)deleteButtonPressed:(id)sender {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:[self deleteAllConfirmationText] message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:[self deleteText]
                                              style:UIAlertActionStyleDestructive
                                            handler:^(UIAlertAction *_Nonnull action) {
                                                [self deleteAll];
                                                [self.tableView reloadData];
                                            }]];
    [sheet addAction:[UIAlertAction actionWithTitle:[self deleteCancelText] style:UIAlertActionStyleCancel handler:NULL]];
    sheet.popoverPresentationController.barButtonItem = sender;
    sheet.popoverPresentationController.permittedArrowDirections = UIPopoverArrowDirectionAny;
    [self presentViewController:sheet animated:YES completion:NULL];
}

#pragma mark - Empty State

- (void)updateEmptyState {
    if (!self.isEmpty) {
        [self wmf_hideEmptyView];
    } else {
        [self wmf_showEmptyViewOfType:[self emptyViewType] theme:self.theme];
    }
}

#pragma mark - Subclasses

- (NSString *)analyticsContext {
    return @"Generic Article List";
}

- (NSString *)analyticsContentType {
    return @"Generic Article List";
}

- (WMFEmptyViewType)emptyViewType {
    return WMFEmptyViewTypeNone;
}

- (BOOL)showsDeleteAllButton {
    return NO;
}

- (NSString *)deleteButtonText {
    return @"";
}

- (NSString *)deleteAllConfirmationText {
    return @"";
}

- (NSString *)deleteText {
    return @"";
}

- (NSString *)deleteCancelText {
    return @"";
}

- (void)deleteItemAtIndexPath:(NSIndexPath *)indexPath {
}

- (void)deleteAll {
}

- (BOOL)isEmpty {
    return NO;
}

- (NSURL *)urlAtIndexPath:(NSIndexPath *)indexPath {
    return [NSURL new];
}

- (void)updateEmptyAndDeleteState {
    [self updateDeleteButton];
    [self updateEmptyState];
}

#pragma mark - WMFTableViewUpdaterDelegate

- (void)tableViewUpdater:(WMFTableViewUpdater *)updater didUpdateTableView:(UITableView *)tableView {
    //Delay the empty state update so its not jarring to the user
    dispatchOnMainQueueAfterDelayInSeconds(0.7, ^{
        [self updateEmptyAndDeleteState];
    });
}

#pragma mark - Sharing

- (void)shareArticle:(NSURL *)url {
    WMFShareActivityController *shareActivityController = [[WMFShareActivityController alloc] initWithArticleURL:url userDataStore:self.userDataStore context:self];
    [self presentViewController:shareActivityController animated:YES completion:NULL];
}

#pragma mark - WMFThemeable

- (void)applyTheme:(WMFTheme *)theme {
    self.theme = theme;
    if ([self viewIfLoaded] == nil) {
        return;
    }
    self.tableView.backgroundColor = theme.colors.baseBackground;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleSingleLine;
    self.tableView.separatorColor = theme.colors.border;
    [self.tableView reloadData];
    [self.tableView wmf_applyThemeToHeadersAndFooters:theme];
}

@end
