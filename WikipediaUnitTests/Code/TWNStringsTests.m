
#import <UIKit/UIKit.h>
#import <XCTest/XCTest.h>

#define HC_SHORTHAND 1
#import <OCHamcrest/OCHamcrest.h>
#import <BlocksKit/BlocksKit.h>

@interface TWNStringsTests : XCTestCase

@property (strong, nonatomic) NSArray* lprojFiles;
@property (strong, nonatomic) NSString* bundleRoot;

@end

@implementation TWNStringsTests

- (void)setUp {
    [super setUp];
    self.bundleRoot = [[NSBundle mainBundle] bundlePath];
    self.lprojFiles = [self bundledLprogFiles];
}

- (NSArray*)bundledLprogFiles {
    return [[[NSFileManager defaultManager] contentsOfDirectoryAtPath:self.bundleRoot error:nil] filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"pathExtension='lproj'"]];
}

- (NSArray*)allLprogFiles {
    return [[[NSFileManager defaultManager] contentsOfDirectoryAtPath:LOCALIZATIONS_DIR error:nil] filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"pathExtension='lproj'"]];
}

- (NSDictionary*)getTranslationStringsDictFromLprogAtPath:(NSString*)lprojPath {
    NSString* stringsFilePath = [lprojPath stringByAppendingPathComponent:@"Localizable.strings"];
    BOOL isDirectory          = NO;
    if ([[NSFileManager defaultManager] fileExistsAtPath:stringsFilePath isDirectory:&isDirectory]) {
        return [NSDictionary dictionaryWithContentsOfFile:stringsFilePath];
    }
    return nil;
}

- (void)test_lproj_count {
    assertThat(@(self.lprojFiles.count), is(greaterThan(@(0))));
}

- (void)test_incoming_translation_string_for_reversed_substitution_shortcuts {
    for (NSString* lprojFileName in self.lprojFiles) {
        NSDictionary* stringsDict = [self getTranslationStringsDictFromLprogAtPath:[self.bundleRoot stringByAppendingPathComponent:lprojFileName]];
        for (NSString* key in stringsDict) {
            NSString* localizedString = stringsDict[key];
            assertThat(localizedString, isNot(containsSubstring(@"1$")));
            assertThat(localizedString, isNot(containsSubstring(@"2$")));
            assertThat(localizedString, isNot(containsSubstring(@"3$")));
            assertThat(localizedString, isNot(containsSubstring(@"4$")));
            assertThat(localizedString, isNot(containsSubstring(@"5$")));
        }
    }
}

- (void)test_incoming_translation_string_for_percent_s {
    for (NSString* lprojFileName in self.lprojFiles) {
        NSDictionary* stringsDict = [self getTranslationStringsDictFromLprogAtPath:[self.bundleRoot stringByAppendingPathComponent:lprojFileName]];
        for (NSString* key in stringsDict) {
            NSString* localizedString = stringsDict[key];
            assertThat(localizedString, isNot(containsSubstring(@"%s")));
        }
    }
}

- (void)test_incoming_translation_string_for_html {
    for (NSString* lprojFileName in self.lprojFiles) {
        NSDictionary* stringsDict = [self getTranslationStringsDictFromLprogAtPath:[self.bundleRoot stringByAppendingPathComponent:lprojFileName]];
        for (NSString* key in stringsDict) {
            NSString* localizedString = stringsDict[key];
            assertThat(localizedString, isNot(stringContainsInOrder(@"<", @">", nil)));
            assertThat(localizedString, isNot(containsSubstring(@"&nbsp")));
        }
    }
}

- (void)test_incoming_translation_string_for_bracket_substitutions {
    for (NSString* lprojFileName in self.lprojFiles) {
        if (![lprojFileName isEqualToString:@"qqq.lproj"]) {
            NSDictionary* stringsDict = [self getTranslationStringsDictFromLprogAtPath:[self.bundleRoot stringByAppendingPathComponent:lprojFileName]];
            for (NSString* key in stringsDict) {
                NSString* localizedString = stringsDict[key];
                assertThat(localizedString, isNot(stringContainsInOrder(@"{{", @"}}", nil)));
            }
        }
    }
}

- (NSArray*)unbundledLprojFiles {
    NSMutableArray* files = [[self allLprogFiles] mutableCopy];
    [files removeObjectsInArray:[self bundledLprogFiles]];
    return files;
}

- (NSArray*)unbundledLprojFilesWithTranslations {
    // unbundled lProj's containing "Localizable.strings"
    return
        [self.unbundledLprojFiles bk_select:^BOOL (NSString* lprojFileName) {
        BOOL isDirectory = NO;
        NSString* localizableStringsFilePath =
            [[LOCALIZATIONS_DIR stringByAppendingPathComponent:lprojFileName] stringByAppendingPathComponent:@"Localizable.strings"];
        return [[NSFileManager defaultManager] fileExistsAtPath:localizableStringsFilePath isDirectory:&isDirectory];
    }];
}

- (void)test_all_translated_languages_were_added_to_project_localizations {
    NSMutableArray* files = [self.unbundledLprojFilesWithTranslations mutableCopy];
    [files removeObjectsInArray:[self languagesUnsureHowToMapToWikiCodes]];

    // Fails if any lproj languages have translations (in "Localizable.strings") but are
    // not yet bundled in the project.

    // So, if this test fails, the languages listed will need to be added these to the project's localizations.

    assertThat(files, isEmpty());
}

- (NSArray*)languagesUnsureHowToMapToWikiCodes {
    // These have no obvious mappings to the lang options Apple provides...
    // TODO: ^ revisit these
    return @[
        @"azb.lproj",
        @"be-tarask.lproj",
        @"bgn.lproj",
        @"cnh.lproj",
        @"ku-latn.lproj",
        @"mai.lproj",
        @"pt-br.lproj",      // for some reason Brazilian Portugese is still showing up as not bundled, but I added it... hmm...
        @"sa.lproj",
        @"sd.lproj",
        @"tl.lproj",
        @"vec.lproj",
        @"xmf.lproj",
        @"ba.lproj"
    ];
}

- (void)tearDown {
    [super tearDown];
    self.lprojFiles = nil;
    self.bundleRoot = nil;
}

@end
