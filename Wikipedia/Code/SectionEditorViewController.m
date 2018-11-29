#import "SectionEditorViewController.h"
@import WMF.MWLanguageInfo;
@import WMF.AFHTTPSessionManager_WMFCancelAll;
#import "WikiTextSectionFetcher.h"
#import "PreviewAndSaveViewController.h"
#import "UIBarButtonItem+WMFButtonConvenience.h"
#import "UIViewController+WMFStoryboardUtilities.h"
#import "Wikipedia-Swift.h"

#define EDIT_TEXT_VIEW_FONT [UIFont systemFontOfSize:16.0f]
#define EDIT_TEXT_VIEW_LINE_HEIGHT_MIN (25.0f)
#define EDIT_TEXT_VIEW_LINE_HEIGHT_MAX (25.0f)

@interface SectionEditorViewController () <PreviewAndSaveViewControllerDelegate, WMFEditToolbarAccessoryViewDelegate, WMFEditTextViewDataSource>

@property (weak, nonatomic) IBOutlet WMFEditTextView *editTextView;
@property (strong, nonatomic) NSString *unmodifiedWikiText;
@property (nonatomic) CGRect viewKeyboardRect;
@property (strong, nonatomic) UIBarButtonItem *rightButton;
@property (strong, nonatomic) WMFEditToolbarAccessoryView *editToolbarAccessoryView;
@property (strong, nonatomic) UINavigationController *textFormattingNavigationController;
@property (strong, nonatomic) WMFTheme *theme;

@end

@implementation SectionEditorViewController

@synthesize shouldShowCustomInputViewController;

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view from its nib.

    if (!self.theme) {
        self.theme = [WMFTheme standard];
    }

    UIBarButtonItem *buttonX = [UIBarButtonItem wmf_buttonType:WMFButtonTypeX target:self action:@selector(xButtonPressed)];
    buttonX.accessibilityLabel = WMFCommonStrings.accessibilityBackTitle;
    self.navigationItem.leftBarButtonItem = buttonX;

    self.rightButton = [[UIBarButtonItem alloc] initWithTitle:[WMFCommonStrings nextTitle]
                                                        style:UIBarButtonItemStylePlain
                                                       target:self
                                                       action:@selector(rightButtonPressed)];
    self.navigationItem.rightBarButtonItem = self.rightButton;

    self.unmodifiedWikiText = nil;

    [self.editTextView setDelegate:self];
    [self.editTextView setDataSource:self];

    [self loadLatestWikiTextForSectionFromServer];

    if ([self.editTextView respondsToSelector:@selector(keyboardDismissMode)]) {
        self.editTextView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    }

    self.editTextView.smartQuotesType = UITextSmartQuotesTypeNo;

    self.viewKeyboardRect = CGRectNull;

    self.editToolbarAccessoryView = [WMFEditToolbarAccessoryView loadFromNib];
    self.editToolbarAccessoryView.delegate = self;

    [self applyTheme:self.theme];

    // "loginWithSavedCredentials..." should help ensure the user will only appear to be logged in when
    // they reach the 'publish' screen if they actually still are logged in. (It uses the "currentlyLoggedInUserFetcher"
    // to try to ensure this.)
    [[WMFAuthenticationManager sharedInstance]
        loginWithSavedCredentialsWithSuccess:^(WMFAccountLoginResult *_Nonnull success) {
            DDLogDebug(@"\n\nSuccessfully logged in with saved credentials for user '%@'.\n\n", success.username);
        }
        userAlreadyLoggedInHandler:^(WMFCurrentlyLoggedInUser *_Nonnull currentLoggedInHandler) {
            DDLogDebug(@"\n\nUser '%@' is already logged in.\n\n", currentLoggedInHandler.name);
        }
        failure:^(NSError *_Nonnull error) {
            DDLogDebug(@"\n\nloginWithSavedCredentials failed with error '%@'.\n\n", error);
        }];
}

- (BOOL)canBecomeFirstResponder {
    return YES;
}

- (UIView *)inputAccessoryView {
    if (shouldShowCustomInputViewController) {
        return nil;
    } else {
        [self.editToolbarAccessoryView applyTheme:self.theme];
        return self.editToolbarAccessoryView;
    }
}

- (void)xButtonPressed {
    [self.delegate sectionEditorFinishedEditing:self
                                    withChanges:NO];
}

- (void)rightButtonPressed {
    if (![self changesMade]) {
        [[WMFAlertManager sharedInstance] showAlert:WMFLocalizedStringWithDefaultValue(@"wikitext-preview-changes-none", nil, nil, @"No changes were made to be previewed.", @"Alert text shown if no changes were made to be previewed.") sticky:NO dismissPreviousAlerts:YES tapCallBack:NULL];
    } else {
        [self preview];
    }
}

- (void)textViewDidChange:(UITextView *)textView {
    [self highlightProgressiveButton:[self changesMade]];

    [self scrollTextViewSoCursorNotUnderKeyboard:textView];
}

- (BOOL)changesMade {
    if (!self.unmodifiedWikiText) {
        return NO;
    }
    return ![self.unmodifiedWikiText isEqualToString:self.editTextView.text];
}

- (void)highlightProgressiveButton:(BOOL)highlight {
    self.navigationItem.rightBarButtonItem.enabled = highlight;
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];

    [self registerForKeyboardNotifications];

    [self highlightProgressiveButton:[self changesMade]];

    if ([self changesMade]) {
        // Needed to keep keyboard on screen when cancelling out of preview.
        [self.editTextView becomeFirstResponder];
    }
}

- (void)viewWillDisappear:(BOOL)animated {
    [self unRegisterForKeyboardNotifications];

    [self highlightProgressiveButton:NO];

    [super viewWillDisappear:animated];
}

- (void)fetchFinished:(id)sender
          fetchedData:(id)fetchedData
               status:(FetchFinalStatus)status
                error:(NSError *)error {
    if ([sender isKindOfClass:[WikiTextSectionFetcher class]]) {
        switch (status) {
            case FETCH_FINAL_STATUS_SUCCEEDED: {
                WikiTextSectionFetcher *wikiTextSectionFetcher = (WikiTextSectionFetcher *)sender;
                NSDictionary *resultsDict = (NSDictionary *)fetchedData;
                NSString *revision = resultsDict[@"revision"];
                NSDictionary *userInfo = resultsDict[@"userInfo"];

                self.funnel = [[EditFunnel alloc] initWithUserId:[userInfo[@"id"] intValue]];
                [self.funnel logStart];

                MWKProtectionStatus *protectionStatus = wikiTextSectionFetcher.section.article.protection;

                if (protectionStatus && [[protectionStatus allowedGroupsForAction:@"edit"] count] > 0) {
                    NSArray *groups = [protectionStatus allowedGroupsForAction:@"edit"];
                    NSString *msg;
                    if ([groups indexOfObject:@"autoconfirmed"] != NSNotFound) {
                        msg = WMFLocalizedStringWithDefaultValue(@"page-protected-autoconfirmed", nil, nil, @"This page has been semi-protected.", @"Brief description of Wikipedia 'autoconfirmed' protection level, shown when editing a page that is protected.");
                    } else if ([groups indexOfObject:@"sysop"] != NSNotFound) {
                        msg = WMFLocalizedStringWithDefaultValue(@"page-protected-sysop", nil, nil, @"This page has been fully protected.", @"Brief description of Wikipedia 'sysop' protection level, shown when editing a page that is protected.");
                    } else {
                        msg = WMFLocalizedStringWithDefaultValue(@"page-protected-other", nil, nil, @"This page has been protected to the following levels: %1$@", @"Brief description of Wikipedia unknown protection level, shown when editing a page that is protected. %1$@ will refer to a list of protection levels.");
                    }
                    [[WMFAlertManager sharedInstance] showAlert:msg sticky:NO dismissPreviousAlerts:YES tapCallBack:NULL];
                } else {
                    //[self showAlert:WMFLocalizedStringWithDefaultValue(@"wikitext-download-success", nil, nil, @"Content loaded.", @"Alert text shown when latest revision of the section being edited has been retrieved") type:ALERT_TYPE_TOP duration:1];
                    [[WMFAlertManager sharedInstance] dismissAlert];
                }
                self.unmodifiedWikiText = revision;
                self.editTextView.attributedText = [self getAttributedString:revision];
                //[self.editTextView performSelector:@selector(becomeFirstResponder) withObject:nil afterDelay:0.4f];
            } break;
            case FETCH_FINAL_STATUS_CANCELLED: {
                [[WMFAlertManager sharedInstance] showErrorAlert:error sticky:YES dismissPreviousAlerts:YES tapCallBack:NULL];
            } break;
            case FETCH_FINAL_STATUS_FAILED: {
                [[WMFAlertManager sharedInstance] showErrorAlert:error sticky:YES dismissPreviousAlerts:YES tapCallBack:NULL];
            } break;
        }
    }
}

- (void)loadLatestWikiTextForSectionFromServer {
    [[WMFAlertManager sharedInstance] showAlert:WMFLocalizedStringWithDefaultValue(@"wikitext-downloading", nil, nil, @"Loading content...", @"Alert text shown when obtaining latest revision of the section being edited") sticky:YES dismissPreviousAlerts:YES tapCallBack:NULL];

    [[QueuesSingleton sharedInstance].sectionWikiTextDownloadManager wmf_cancelAllTasksWithCompletionHandler:^{
        (void)[[WikiTextSectionFetcher alloc] initAndFetchWikiTextForSection:self.section
                                                                 withManager:[QueuesSingleton sharedInstance].sectionWikiTextDownloadManager
                                                          thenNotifyDelegate:self];
    }];
}

- (NSAttributedString *)getAttributedString:(NSString *)string {
    NSMutableParagraphStyle *paragraphStyle = [[NSMutableParagraphStyle alloc] init];
    paragraphStyle.maximumLineHeight = EDIT_TEXT_VIEW_LINE_HEIGHT_MIN;
    paragraphStyle.minimumLineHeight = EDIT_TEXT_VIEW_LINE_HEIGHT_MAX;

    paragraphStyle.headIndent = 10.0;
    paragraphStyle.firstLineHeadIndent = 10.0;
    paragraphStyle.tailIndent = -10.0;

    return
        [[NSAttributedString alloc] initWithString:string
                                        attributes:@{
                                            NSParagraphStyleAttributeName: paragraphStyle,
                                            NSFontAttributeName: EDIT_TEXT_VIEW_FONT,
                                            NSForegroundColorAttributeName: self.theme.colors.primaryText
                                        }];
}

- (void)preview {
    PreviewAndSaveViewController *previewVC = [PreviewAndSaveViewController wmf_initialViewControllerFromClassStoryboard];
    previewVC.section = self.section;
    previewVC.wikiText = self.editTextView.text;
    previewVC.funnel = self.funnel;
    previewVC.savedPagesFunnel = self.savedPagesFunnel;
    previewVC.delegate = self;
    [previewVC applyTheme:self.theme];
    [self.navigationController pushViewController:previewVC animated:YES];
}

- (void)previewViewControllerDidSave:(PreviewAndSaveViewController *)previewViewController {
    [self.delegate sectionEditorFinishedEditing:self withChanges:YES];
}

#pragma mark Keyboard

// Ensure the edit text view can scroll whatever text it is displaying all the
// way so the bottom of the text can be scrolled to the top of the screen.
// More info here:
// https://developer.apple.com/library/ios/documentation/StringsTextFonts/Conceptual/TextAndWebiPhoneOS/KeyboardManagement/KeyboardManagement.html

- (void)registerForKeyboardNotifications {
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardWasShown:)
                                                 name:UIKeyboardDidShowNotification
                                               object:nil];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardWillBeHidden:)
                                                 name:UIKeyboardWillHideNotification
                                               object:nil];
}

- (void)unRegisterForKeyboardNotifications {
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:UIKeyboardDidShowNotification
                                                  object:nil];

    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:UIKeyboardWillHideNotification
                                                  object:nil];
}

- (void)keyboardWasShown:(NSNotification *)aNotification {
    NSDictionary *info = [aNotification userInfo];

    CGRect windowKeyboardRect = [[info objectForKey:UIKeyboardFrameEndUserInfoKey] CGRectValue];

    CGRect viewKeyboardRect = [self.view.window convertRect:windowKeyboardRect toView:self.view];

    self.viewKeyboardRect = viewKeyboardRect;

    // This makes it so you can always scroll to the bottom of the text view's text
    // even if the keyboard is onscreen.
    UIEdgeInsets contentInsets = UIEdgeInsetsMake(0.0, 0.0, viewKeyboardRect.size.height, 0.0);
    self.editTextView.contentInset = contentInsets;
    self.editTextView.scrollIndicatorInsets = contentInsets;

    // Mark the text view as needing a layout update so the inset changes above will
    // be taken in to account when the cursor is scrolled onscreen.
    [self.editTextView setNeedsLayout];
    [self.editTextView layoutIfNeeded];

    // Scroll cursor onscreen if needed.
    [self scrollTextViewSoCursorNotUnderKeyboard:self.editTextView];
}

- (void)keyboardWillBeHidden:(NSNotification *)aNotification {
    UIEdgeInsets contentInsets = UIEdgeInsetsZero;
    self.editTextView.contentInset = contentInsets;
    self.editTextView.scrollIndicatorInsets = contentInsets;

    self.viewKeyboardRect = CGRectNull;
}

- (void)scrollTextViewSoCursorNotUnderKeyboard:(UITextView *)textView {
    // If cursor is hidden by keyboard, scroll the text view so cursor is onscreen.
    if (!CGRectIsNull(self.viewKeyboardRect)) {
        CGRect cursorRectInTextView = [textView caretRectForPosition:textView.selectedTextRange.start];
        CGRect cursorRectInView = [textView convertRect:cursorRectInTextView toView:self.view];
        if (CGRectIntersectsRect(self.viewKeyboardRect, cursorRectInView)) {
            CGFloat margin = -20;
            // Margin here is the amount the cursor will be scrolled above the top of the keyboard.
            cursorRectInTextView = CGRectInset(cursorRectInTextView, 0, margin);

            [textView scrollRectToVisible:cursorRectInTextView animated:YES];
        }
    }
}

#pragma mark Accessibility

- (BOOL)accessibilityPerformEscape {
    [self.navigationController popViewControllerAnimated:YES];
    return YES;
}

#pragma mark WMFEditToolbarAccessoryViewDelegate

- (void)editToolbarAccessoryViewDidTapTextFormattingButton:(WMFEditToolbarAccessoryView *)editToolbarAccessoryView button:(UIButton *)button {
    [self setTextFormattingViewHidden:NO];
}

#pragma mark TextFormattingView visibility

- (void)setTextFormattingViewHidden:(BOOL)hidden {
    UIResponder *responder = self.isFirstResponder ? self : self.editTextView;

    shouldShowCustomInputViewController = !hidden;
    [self setCursorPositionIfNeeded];

    UIViewPropertyAnimator *animator = [[UIViewPropertyAnimator alloc] initWithDuration:0.3
                                                                                  curve:UIViewAnimationCurveEaseInOut
                                                                             animations:^{
                                                                                 [responder resignFirstResponder];
                                                                             }];

    [animator addCompletion:^(UIViewAnimatingPosition finalPosition) {
        [self.editTextView becomeFirstResponder];
    }];

    [animator startAnimation];
}

- (void)setCursorPositionIfNeeded {
    BOOL shouldSetCursor = !self.editTextView.isFirstResponder;

    if (!shouldSetCursor) {
        return;
    }

    UITextPosition *newPosition = self.editTextView.beginningOfDocument;
    self.editTextView.selectedTextRange = [self.editTextView textRangeFromPosition:newPosition toPosition:newPosition];
}

#pragma mark WMFThemeable

- (void)applyTheme:(WMFTheme *)theme {
    self.theme = theme;
    if (self.viewIfLoaded == nil) {
        return;
    }
    self.editTextView.backgroundColor = theme.colors.paperBackground;
    self.editTextView.textColor = theme.colors.primaryText;
    self.view.backgroundColor = theme.colors.paperBackground;
    self.editTextView.keyboardAppearance = theme.keyboardAppearance;
}

@end
