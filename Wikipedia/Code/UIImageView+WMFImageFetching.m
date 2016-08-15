#import "UIImageView+WMFImageFetchingInternal.h"
#import "UIImageView+WMFContentOffset.h"

NS_ASSUME_NONNULL_BEGIN

@implementation UIImageView (WMFImageFetching)

- (void)wmf_reset {
    self.image = nil;
    [self wmf_resetContentsRect];
    [self wmf_cancelImageDownload];
}

- (void)wmf_setImageWithURL:(NSURL *)imageURL detectFaces:(BOOL)detectFaces failure:(nonnull WMFErrorHandler)failure success:(nonnull WMFSuccessHandler)success {
    [self wmf_cancelImageDownload];
    self.wmf_imageURL = imageURL;
    [self wmf_fetchImageDetectFaces:detectFaces failure:failure success:success];
}

- (void)wmf_setImageWithMetadata:(MWKImage *)imageMetadata detectFaces:(BOOL)detectFaces failure:(nonnull WMFErrorHandler)failure success:(nonnull WMFSuccessHandler)success {
    [self wmf_cancelImageDownload];
    self.wmf_imageMetadata = imageMetadata;
    [self wmf_fetchImageDetectFaces:detectFaces failure:failure success:success];
}

@end

NS_ASSUME_NONNULL_END
