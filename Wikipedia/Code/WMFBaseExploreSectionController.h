#import <Foundation/Foundation.h>
#import "WMFExploreSectionController.h"
#import "WMFAnalyticsLogging.h"

@class WMFEmptySectionCollectionViewCell, MWKDataStore, MWKSavedPageList, MWKHistoryList;

NS_ASSUME_NONNULL_BEGIN

/**
 *  Base implementation of WMFExploreSectionController protocol
 *  This class implements many of the WMFExploreSectionController methods needed for conformance.
 *  Read each category below to see what is implmeneted and what is not.
 *
 *  See WMFExploreSectionController.h for further documentation.
 */
@interface WMFBaseExploreSectionController : NSObject <WMFAnalyticsContextProviding>

- (instancetype)init NS_UNAVAILABLE;

- (instancetype)initWithDataStore:(MWKDataStore *)dataStore;

- (instancetype)initWithDataStore:(MWKDataStore *)dataStore items:(NSArray *)items;

@property(nonatomic, strong, readonly) MWKDataStore *dataStore;

@property(nonatomic, strong, readonly) MWKSavedPageList *savedPageList;

@property(nonatomic, strong, readonly) MWKHistoryList *historyList;

@property(nonatomic, strong, readonly) NSArray *items;

@end

/**
 *  The methods in this category must be implemented by all subclasses
 */
@interface WMFBaseExploreSectionController (WMFBaseExploreSubclassRequiredMethods)

- (NSString *)cellIdentifier;

- (UINib *)cellNib;

- (void)configureCell:(UICollectionViewCell *)cell withItem:(id)item atIndexPath:(NSIndexPath *)indexPath;

@end

/**
 *  The methods in this category are optional
 */
@interface WMFBaseExploreSectionController (WMFBaseExploreOptionalMethods)

/**
 *  Default returns a successful promise with the current items
 *  Implementations should resolve promises with an NSArray
 */
- (AnyPromise *)fetchData;

@end

/**
 *  Implement the following methods to support placeholders
 */
@interface WMFBaseExploreSectionController (WMFPlaceholderCellSupport)

/**
 *  The number of placeholder cells to display
 *
 *  @return The number of cells. Default is 3
 */
- (NSUInteger)numberOfPlaceholderCells;

- (nullable NSString *)placeholderCellIdentifier;

- (nullable UINib *)placeholderCellNib;

- (BOOL)containsPlaceholders;

@end

/**
 *  Implement the following methods to support empty cells
 */
@interface WMFBaseExploreSectionController (WMFEmptyCellSupport)

/**
 *  Configure the empty cell
 *
 *  @param cell The cell to configure
 */
- (void)configureEmptyCell:(WMFEmptySectionCollectionViewCell *)cell;

@end

/**
 *  The following methods of WMFExploreSectionController are implemented by WMFBaseExploreSectionController.
 */
@interface WMFBaseExploreSectionController (WMFExploreSectionControllerOverrideMethods)

/**
 *  Clears the current items. Override if you need to perform additional cleanup.
 */
- (void)resetData;

/**
 *  Returns no for placeholders and empty cells. Otehrwise YES
 *  Override if you need to further customize this behavior.
 */
- (BOOL)shouldSelectItemAtIndexPath:(NSIndexPath *)indexPath;

@end

/**
 *  The following methods of WMFExploreSectionController are implemented by WMFBaseExploreSectionController.
 *  Subclasses do NOT need to implement these except to change behavior.
 */
@interface WMFBaseExploreSectionController (WMFExploreSectionControllerImplementedMethods)

@property(nonatomic, strong, readonly) NSArray *items;

- (AnyPromise *)fetchDataIfNeeded;

- (AnyPromise *)fetchDataIfError;

- (AnyPromise *)fetchDataUserInitiated;

- (void)registerCellsInCollectionView:(UICollectionView *)collectionView;

- (NSString *)cellIdentifierForItemIndexPath:(NSIndexPath *)indexPath;

- (void)configureCell:(UICollectionViewCell *)cell atIndexPath:(NSIndexPath *)indexPath;

@end

NS_ASSUME_NONNULL_END
