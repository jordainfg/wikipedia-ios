#import <Foundation/Foundation.h>

@interface NSAttributedString (WMFSavedPagesAttributedStrings)

+ (NSAttributedString *)wmf_attributedStringWithTitle:(NSString *)title
                                          description:(NSString *)description
                                             language:(NSString *)language;

@end
