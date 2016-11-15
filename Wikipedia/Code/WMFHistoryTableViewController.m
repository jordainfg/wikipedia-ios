#import "WMFHistoryTableViewController.h"
#import "PiwikTracker+WMFExtensions.h"
#import "NSUserActivity+WMFExtensions.h"

#import "NSString+WMFExtras.h"
#import "NSDate+Utilities.h"

#import "MWKDataStore+WMFDataSources.h"
#import "MWKHistoryEntry+WMFDatabaseStorable.h"
#import "MWKHistoryList.h"

#import "MWKArticle.h"
#import "MWKSavedPageEntry.h"

#import "WMFArticleListTableViewCell.h"
#import "UIView+WMFDefaultNib.h"

@interface WMFHistoryTableViewController () <WMFDataSourceDelegate>

@property (nonatomic, strong) id<WMFDataSource> dataSource;

@end

@implementation WMFHistoryTableViewController

#pragma mark - NSObject

- (void)awakeFromNib {
    [super awakeFromNib];
    self.title = MWLocalizedString(@"history-title", nil);
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Accessors

- (MWKHistoryList *)historyList {
    return [[WMFDatabaseStack sharedInstance] userStore].historyList;
}

- (MWKSavedPageList *)savedPageList {
    return [[WMFDatabaseStack sharedInstance] userStore].savedPageList;
}

- (MWKHistoryEntry *)objectAtIndexPath:(NSIndexPath *)indexPath {
    return (MWKHistoryEntry *)[self.dataSource objectAtIndexPath:indexPath];
}

#pragma mark - UIViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    [self.tableView registerNib:[WMFArticleListTableViewCell wmf_classNib] forCellReuseIdentifier:[WMFArticleListTableViewCell identifier]];

    self.tableView.estimatedRowHeight = [WMFArticleListTableViewCell estimatedRowHeight];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(teardownNotification:) name:MWKTeardownDataSourcesNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(setupNotification:) name:MWKSetupDataSourcesNotification object:nil];
}

- (void)setupDataSource {
    if (!self.dataSource) {
        NSParameterAssert([[WMFDatabaseStack sharedInstance] userStore]);
        self.dataSource = [[[WMFDatabaseStack sharedInstance] userStore] historyGroupedByDateDataSource];
        self.dataSource.delegate = self;
        [self.tableView reloadData];
        [self updateEmptyAndDeleteState];
    }
}

- (void)teardownDataSource {
    self.dataSource.delegate = nil;
    self.dataSource = nil;
}

- (void)teardownNotification:(NSNotification *)note {
    [self teardownDataSource];
}

- (void)setupNotification:(NSNotification *)note {
    [self setupDataSource];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self setupDataSource];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [[PiwikTracker sharedInstance] wmf_logView:self];
    [NSUserActivity wmf_makeActivityActive:[NSUserActivity wmf_recentViewActivity]];
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    [self teardownDataSource];
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return [self.dataSource numberOfSections];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return [self.dataSource numberOfItemsInSection:section];
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    NSString *dateString = [self.dataSource titleForSectionIndex:section];
    NSDate *date = [NSDate dateWithTimeIntervalSince1970:[dateString doubleValue]];

    //HACK: Table views for some reason aren't adding padding to the left of the default headers. Injecting some manually.
    NSString *padding = @"    ";

    if ([date isToday]) {
        return [padding stringByAppendingString:[MWLocalizedString(@"history-section-today", nil) uppercaseString]];
    } else if ([date isYesterday]) {
        return [padding stringByAppendingString:[MWLocalizedString(@"history-section-yesterday", nil) uppercaseString]];
    } else {
        return [padding stringByAppendingString:[[NSDateFormatter wmf_mediumDateFormatterWithoutTime] stringFromDate:date]];
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    WMFArticleListTableViewCell *cell = [self.tableView dequeueReusableCellWithIdentifier:[WMFArticleListTableViewCell identifier] forIndexPath:indexPath];

    MWKHistoryEntry *entry = [self objectAtIndexPath:indexPath];
    MWKArticle *article = [[[WMFDatabaseStack sharedInstance] userStore] articleWithURL:entry.url];
    cell.titleText = article.url.wmf_title;
    cell.descriptionText = [article.entityDescription wmf_stringByCapitalizingFirstCharacter];
    [cell setImage:[article bestThumbnailImage]];

    return cell;
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath {
    return YES;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    [[self historyList] removeEntryWithURL:[self urlAtIndexPath:indexPath]];
}

#pragma mark - WMFDataSourceDelegate

- (void)dataSourceDidUpdateAllData:(id<WMFDataSource>)dataSource {
    [self.tableView reloadData];
}

- (void)dataSourceWillBeginUpdates:(id<WMFDataSource>)dataSource {
    [self.tableView beginUpdates];
}

- (void)dataSourceDidFinishUpdates:(id<WMFDataSource>)dataSource {
    [self.tableView endUpdates];
    [self updateEmptyAndDeleteState];
}

- (void)dataSource:(id<WMFDataSource>)dataSource didDeleteSectionsAtIndexes:(NSIndexSet *)indexes {
    [self.tableView deleteSections:indexes withRowAnimation:UITableViewRowAnimationAutomatic];
}

- (void)dataSource:(id<WMFDataSource>)dataSource didInsertSectionsAtIndexes:(NSIndexSet *)indexes {
    [self.tableView insertSections:indexes withRowAnimation:UITableViewRowAnimationAutomatic];
}

- (void)dataSource:(id<WMFDataSource>)dataSource didDeleteRowsAtIndexPaths:(NSArray<NSIndexPath *> *)indexPaths {
    [self.tableView deleteRowsAtIndexPaths:indexPaths withRowAnimation:UITableViewRowAnimationAutomatic];
}

- (void)dataSource:(id<WMFDataSource>)dataSource didInsertRowsAtIndexPaths:(NSArray<NSIndexPath *> *)indexPaths {
    [self.tableView insertRowsAtIndexPaths:indexPaths withRowAnimation:UITableViewRowAnimationAutomatic];
}

- (void)dataSource:(id<WMFDataSource>)dataSource didMoveRowFromIndexPath:(NSIndexPath *)fromIndexPath toIndexPath:(NSIndexPath *)toIndexPath {
    [self.tableView deleteRowsAtIndexPaths:@[fromIndexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
    [self.tableView insertRowsAtIndexPaths:@[toIndexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
}

- (void)dataSource:(id<WMFDataSource>)dataSource didUpdateRowsAtIndexPaths:(NSArray<NSIndexPath *> *)indexPaths {
    [self.tableView reloadRowsAtIndexPaths:indexPaths withRowAnimation:UITableViewRowAnimationAutomatic];
}

#pragma mark - WMFArticleListTableViewController

- (WMFEmptyViewType)emptyViewType {
    return WMFEmptyViewTypeNoHistory;
}

- (NSString *)analyticsContext {
    return @"Recent";
}

- (NSString *)analyticsName {
    return [self analyticsContext];
}

- (BOOL)showsDeleteAllButton {
    return YES;
}

- (NSString *)deleteButtonText {
    return MWLocalizedString(@"history-clear-all", nil);
}

- (NSString *)deleteAllConfirmationText {
    return MWLocalizedString(@"history-clear-confirmation-heading", nil);
}

- (NSString *)deleteText {
    return MWLocalizedString(@"history-clear-delete-all", nil);
}

- (NSString *)deleteCancelText {
    return MWLocalizedString(@"history-clear-cancel", nil);
}

- (BOOL)canDeleteItemAtIndexPath:(NSIndexPath *)indexPath {
    return YES;
}

- (NSURL *)urlAtIndexPath:(NSIndexPath *)indexPath {
    return [[self objectAtIndexPath:indexPath] url];
}

- (void)deleteAll {
    [[self historyList] removeAllEntries];
}

- (NSInteger)numberOfItems {
    return [self.dataSource numberOfItems];
}

@end
