//
//  MWKLanguageLinkController.m
//  Wikipedia
//
//  Created by Brian Gerstle on 6/17/15.
//  Copyright (c) 2015 Wikimedia Foundation. All rights reserved.
//

#import "MWKLanguageLinkController_Private.h"
#import "MWKTitle.h"
#import "MWKLanguageLink.h"
#import "NSObjectUtilities.h"
#import "NSString+WMFExtras.h"
#import "MediaWikiKit.h"
#import "Defines.h"
#import "WMFAssetsFile.h"
#import "WikipediaAppUtils.h"
#import <BlocksKit/BlocksKit.h>
#import "Wikipedia-Swift.h"

NS_ASSUME_NONNULL_BEGIN

NSString* const WMFPreferredLanguagesDidChangeNotification = @"WMFPreferredLanguagesDidChangeNotification";

static NSString* const WMFPreviousLanguagesKey = @"WMFPreviousSelectedLanguagesKey";

/**
 * List of unsupported language codes.
 *
 * As of iOS 8, the system font doesn't support these languages, e.g. "arc" (Aramaic, Syriac font). [0]
 *
 * 0: http://syriaca.org/documentation/view-syriac.html
 */
static NSArray* WMFUnsupportedLanguages() {
    static NSArray* unsupportedLanguageCodes;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        unsupportedLanguageCodes = @[@"am", @"dv", @"lez", @"arc", @"got", @"ti"];
    });
    return unsupportedLanguageCodes;
}

@interface MWKLanguageLinkController ()

@property (readwrite, copy, nonatomic) NSArray* preferredLanguages;

@property (readwrite, copy, nonatomic) NSArray* otherLanguages;

@end

@implementation MWKLanguageLinkController

static id _sharedInstance;

+ (instancetype)sharedInstance {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        _sharedInstance = [[[self class] alloc] init];
    });
    return _sharedInstance;
}

- (instancetype)init {
    assert(_sharedInstance == nil);
    self = [super init];
    if (self) {
        [self loadLanguagesFromFile];
    }
    return self;
}

#pragma mark - Loading

- (void)loadLanguagesFromFile {
    WMFAssetsFile* assetsFile = [[WMFAssetsFile alloc] initWithFileType:WMFAssetsFileTypeLanguages];
    NSParameterAssert(assetsFile.array);
    self.allLanguages = [assetsFile.array bk_map:^id (NSDictionary* langAsset) {
        NSString* code = langAsset[@"code"];
        NSString* localizedName = langAsset[@"canonical_name"];
        if (![self isCompoundLanguageCode:code]) {
            // iOS will return less descriptive name for compound codes - ie "Chinese" for zh-yue which
            // should be "Cantonese". It looks like iOS ignores anything after the "-".
            NSString* iOSLocalizedName = [[NSLocale currentLocale] wmf_localizedLanguageNameForCode:code];
            if (iOSLocalizedName) {
                localizedName = iOSLocalizedName;
            }
        }
        return [[MWKLanguageLink alloc] initWithLanguageCode:code
                                               pageTitleText:@""
                                                        name:langAsset[@"name"]
                                               localizedName:localizedName];
    }];
    NSParameterAssert(self.allLanguages.count);
}

- (BOOL)isCompoundLanguageCode:(NSString*)code {
    return [code containsString:@"-"];
}

#pragma mark - Getters & Setters

- (void)setAllLanguages:(NSArray*)allLanguages {
    NSArray* unsupportedLanguages   = WMFUnsupportedLanguages();
    NSArray* supportedLanguageLinks = [allLanguages bk_reject:^BOOL (MWKLanguageLink* languageLink) {
        return [unsupportedLanguages containsObject:languageLink.languageCode];
    }];

    supportedLanguageLinks = [supportedLanguageLinks sortedArrayUsingSelector:@selector(compare:)];

    _allLanguages = supportedLanguageLinks;
    [self updateLanguageArrays];
}

- (nullable MWKLanguageLink*)languageForSite:(MWKSite*)site {
    return [self.allLanguages bk_match:^BOOL (MWKLanguageLink* obj) {
        return [obj.site isEqualToSite:site];
    }];
}

- (MWKLanguageLink*)appLanguage {
    return [self.preferredLanguages firstObject];
}

#pragma mark - Build Language Arrays

- (void)updateLanguageArrays {
    [self willChangeValueForKey:WMF_SAFE_KEYPATH(self, allLanguages)];
    NSArray* preferredLanguageCodes = [self readPreferredLanguageCodes];
    self.preferredLanguages = [preferredLanguageCodes wmf_mapAndRejectNil:^id (NSString* langString) {
        return [self.allLanguages bk_match:^BOOL (MWKLanguageLink* langLink) {
            return [langLink.languageCode isEqualToString:langString];
        }];
    }];
    self.otherLanguages = [self.allLanguages bk_select:^BOOL (MWKLanguageLink* langLink) {
        return ![self.preferredLanguages containsObject:langLink];
    }];
    [self didChangeValueForKey:WMF_SAFE_KEYPATH(self, allLanguages)];
}

#pragma mark - Preferred Language Management

- (void)addPreferredLanguage:(MWKLanguageLink*)language {
    NSParameterAssert(language);
    NSMutableArray<NSString*>* langCodes = [[self readPreferredLanguageCodes] mutableCopy];
    [langCodes removeObject:language.languageCode];
    [langCodes insertObject:language.languageCode atIndex:0];
    [self savePreferredLanguageCodes:langCodes];
}

- (void)appendPreferredLanguage:(MWKLanguageLink*)language {
    NSParameterAssert(language);
    NSMutableArray<NSString*>* langCodes = [[self readPreferredLanguageCodes] mutableCopy];
    [langCodes removeObject:language.languageCode];
    [langCodes addObject:language.languageCode];
    [self savePreferredLanguageCodes:langCodes];
}

- (void)reorderPreferredLanguage:(MWKLanguageLink*)language toIndex:(NSUInteger)newIndex {
    NSMutableArray<NSString*>* langCodes = [[self readPreferredLanguageCodes] mutableCopy];
    NSAssert(newIndex < [langCodes count], @"new language index is out of range");
    if (newIndex >= [langCodes count]) {
        return;
    }
    NSUInteger oldIndex = [langCodes indexOfObject:language.languageCode];
    NSAssert(oldIndex != NSNotFound, @"Language is not a preferred language");
    if (oldIndex == NSNotFound) {
        return;
    }
    [langCodes removeObject:language.languageCode];
    [langCodes insertObject:language.languageCode atIndex:newIndex];
    [self savePreferredLanguageCodes:langCodes];
}

- (void)removePreferredLanguage:(MWKLanguageLink*)language {
    NSMutableArray<NSString*>* langCodes = [[self readPreferredLanguageCodes] mutableCopy];
    [langCodes removeObject:language.languageCode];
    [self savePreferredLanguageCodes:langCodes];
}

#pragma mark - Reading/Saving Preferred Language Codes to NSUserDefaults

- (NSArray<NSString*>*)readPreferredLanguageCodesWithoutOSPreferredLanguages {
    NSArray<NSString*>* preferredLanguages = [[NSUserDefaults standardUserDefaults] arrayForKey:WMFPreviousLanguagesKey] ? : @[];
    return preferredLanguages;
}

- (NSArray<NSString*>*)readOSPreferredLanguageCodes {
    NSArray<NSString*>* osLanguages = [[NSLocale preferredLanguages] wmf_mapAndRejectNil:^NSString*(NSString* languageCode) {
        NSLocale* locale = [NSLocale localeWithLocaleIdentifier:languageCode];
        // use language code when determining if a langauge is preferred (e.g. "en_US" is preferred if "en" was selected)
        return [locale objectForKey:NSLocaleLanguageCode];
    }];
    return osLanguages;
}

- (NSArray<NSString*>*)readPreferredLanguageCodes {
    NSMutableArray<NSString*>* preferredLanguages = [[self readPreferredLanguageCodesWithoutOSPreferredLanguages] mutableCopy];
    NSArray<NSString*>* osLanguages               = [self readOSPreferredLanguageCodes];

    if (preferredLanguages.count == 0) {
        [osLanguages enumerateObjectsWithOptions:NSEnumerationReverse usingBlock:^(id _Nonnull obj, NSUInteger idx, BOOL* _Nonnull stop) {
            if (![preferredLanguages containsObject:obj]) {
                [preferredLanguages insertObject:obj atIndex:0];
            }
        }];
    }
    return [preferredLanguages bk_reject:^BOOL (id obj) {
        return [obj isEqual:[NSNull null]];
    }];
}

- (void)savePreferredLanguageCodes:(NSArray<NSString*>*)languageCodes {
    [[NSUserDefaults standardUserDefaults] setObject:languageCodes forKey:WMFPreviousLanguagesKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
    [self updateLanguageArrays];
    [[NSNotificationCenter defaultCenter] postNotificationName:WMFPreferredLanguagesDidChangeNotification object:self];
}

- (void)resetPreferredLanguages {
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:WMFPreviousLanguagesKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
    [self updateLanguageArrays];
    [[NSNotificationCenter defaultCenter] postNotificationName:WMFPreferredLanguagesDidChangeNotification object:self];
}

- (BOOL)languageIsOSLanguage:(MWKLanguageLink*)language {
    NSArray* languageCodes = [self readOSPreferredLanguageCodes];
    return [languageCodes bk_match:^BOOL (NSString* obj) {
        BOOL answer = [obj isEqualToString:language.languageCode];
        return answer;
    }] != nil;
}

@end

NS_ASSUME_NONNULL_END
