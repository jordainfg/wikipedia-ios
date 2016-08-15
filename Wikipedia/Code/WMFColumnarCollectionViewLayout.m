#import "WMFColumnarCollectionViewLayout.h"
#import "WMFCVLInfo.h"
#import "WMFCVLColumn.h"
#import "WMFCVLSection.h"
#import "WMFCVLAttributes.h"
#import "WMFCVLInvalidationContext.h"
#import "WMFCVLMetrics.h"

@interface WMFColumnarCollectionViewLayout ()

@property(nonatomic, readonly) id<WMFColumnarCollectionViewLayoutDelegate> delegate;
@property(nonatomic, strong) WMFCVLInfo *info;
@property(nonatomic, strong) WMFCVLMetrics *metrics;

@end

@implementation WMFColumnarCollectionViewLayout

#pragma mark - Classes

+ (Class)invalidationContextClass {
    return [WMFCVLInvalidationContext class];
}

+ (Class)layoutAttributesClass {
    return [WMFCVLAttributes class];
}

#pragma mark - Properties

- (id<WMFColumnarCollectionViewLayoutDelegate>)delegate {
    assert(self.collectionView.delegate == nil || [self.collectionView.delegate conformsToProtocol:@protocol(WMFColumnarCollectionViewLayoutDelegate)]);
    return (id<WMFColumnarCollectionViewLayoutDelegate>)self.collectionView.delegate;
}

- (NSInteger)numberOfItemsInSection:(NSInteger)section {
    return [self.collectionView.dataSource collectionView:self.collectionView numberOfItemsInSection:section];
}

- (CGSize)collectionViewContentSize {
    return self.info.contentSize;
}

#pragma mark - Layout

- (nullable NSArray<__kindof UICollectionViewLayoutAttributes *> *)layoutAttributesForElementsInRect:(CGRect)rect {

    NSMutableArray *attributesArray = [NSMutableArray array];

    [self.info enumerateSectionsWithBlock:^(WMFCVLSection *_Nonnull section, NSUInteger idx, BOOL *_Nonnull stop) {
      if (CGRectIntersectsRect(section.frame, rect)) {
          [section enumerateLayoutAttributesWithBlock:^(WMFCVLAttributes *attributes, BOOL *stop) {
            if (CGRectIntersectsRect(attributes.frame, rect)) {
                [attributesArray addObject:attributes];
            }
          }];
      }
    }];

    return attributesArray;
}

- (nullable UICollectionViewLayoutAttributes *)layoutAttributesForItemAtIndexPath:(NSIndexPath *)indexPath {
    return [self.info layoutAttributesForItemAtIndexPath:indexPath];
}

- (nullable UICollectionViewLayoutAttributes *)layoutAttributesForSupplementaryViewOfKind:(NSString *)elementKind atIndexPath:(NSIndexPath *)indexPath {
    return [self.info layoutAttributesForSupplementaryViewOfKind:elementKind atIndexPath:indexPath];
}

- (nullable UICollectionViewLayoutAttributes *)layoutAttributesForDecorationViewOfKind:(NSString *)elementKind atIndexPath:(NSIndexPath *)indexPath {
    return nil;
}

- (void)prepareLayout {
    if (self.info == nil) {
        self.info = [[WMFCVLInfo alloc] init];
        self.metrics = [WMFCVLMetrics metricsWithBoundsSize:self.collectionView.bounds.size];
        [self.info layoutWithMetrics:self.metrics delegate:self.delegate collectionView:self.collectionView invalidationContext:nil];
    }
    [super prepareLayout];
}

- (CGPoint)targetContentOffsetForProposedContentOffset:(CGPoint)proposedContentOffset {
    return proposedContentOffset;
}

- (CGPoint)targetContentOffsetForProposedContentOffset:(CGPoint)proposedContentOffset withScrollingVelocity:(CGPoint)velocity {
    return proposedContentOffset;
}

#pragma mark - Invalidation

- (BOOL)shouldInvalidateLayoutForBoundsChange:(CGRect)newBounds {
    return newBounds.size.width != self.metrics.boundsSize.width;
}

- (UICollectionViewLayoutInvalidationContext *)invalidationContextForBoundsChange:(CGRect)newBounds {
    WMFCVLInvalidationContext *context = (WMFCVLInvalidationContext *)[super invalidationContextForBoundsChange:newBounds];
    context.boundsDidChange = YES;
    self.metrics = [WMFCVLMetrics metricsWithBoundsSize:newBounds.size];
    [self.info updateWithMetrics:self.metrics invalidationContext:context delegate:self.delegate collectionView:self.collectionView];
    return context;
}

- (BOOL)shouldInvalidateLayoutForPreferredLayoutAttributes:(UICollectionViewLayoutAttributes *)preferredAttributes withOriginalAttributes:(UICollectionViewLayoutAttributes *)originalAttributes {
    return !CGRectEqualToRect(preferredAttributes.frame, originalAttributes.frame);
}

- (UICollectionViewLayoutInvalidationContext *)invalidationContextForPreferredLayoutAttributes:(UICollectionViewLayoutAttributes *)preferredAttributes withOriginalAttributes:(UICollectionViewLayoutAttributes *)originalAttributes {
    WMFCVLInvalidationContext *context = (WMFCVLInvalidationContext *)[super invalidationContextForPreferredLayoutAttributes:preferredAttributes withOriginalAttributes:originalAttributes];
    if (context == nil) {
        context = [WMFCVLInvalidationContext new];
    }
    context.preferredLayoutAttributes = preferredAttributes;
    context.originalLayoutAttributes = originalAttributes;
    [self.info updateWithMetrics:self.metrics invalidationContext:context delegate:self.delegate collectionView:self.collectionView];
    return context;
}

- (void)invalidateLayoutWithContext:(WMFCVLInvalidationContext *)context {
    assert([context isKindOfClass:[WMFCVLInvalidationContext class]]);
    if (context.invalidateEverything || context.invalidateDataSourceCounts) {
        self.metrics = [WMFCVLMetrics metricsWithBoundsSize:self.collectionView.bounds.size];
        [self.info updateWithMetrics:self.metrics invalidationContext:context delegate:self.delegate collectionView:self.collectionView];
    }
    [super invalidateLayoutWithContext:context];
}

@end
