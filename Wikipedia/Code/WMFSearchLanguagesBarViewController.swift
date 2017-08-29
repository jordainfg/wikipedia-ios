import Foundation

@objc protocol WMFSearchLanguagesBarViewControllerDelegate: class {
    func searchLanguagesBarViewController(_ controller: WMFSearchLanguagesBarViewController, didChangeCurrentlySelectedSearchLanguage language: MWKLanguageLink)
}

class WMFSearchLanguagesBarViewController: UIViewController, WMFPreferredLanguagesViewControllerDelegate, WMFLanguagesViewControllerDelegate, Themeable {
    weak var delegate: WMFSearchLanguagesBarViewControllerDelegate?
    
    @IBOutlet fileprivate var languageButtons: [UIButton] = []
    @IBOutlet fileprivate var otherLanguagesButton: UIButton?
    @IBOutlet fileprivate var heightConstraint: NSLayoutConstraint?
    
    var theme: Theme = Theme.standard
    
    fileprivate var hidden: Bool = false {
        didSet {
            if(hidden){
                heightConstraint!.constant = 0
                view.isHidden = true
            }else{
                heightConstraint!.constant = 44
                view.isHidden = false
            }
        }
    }

    fileprivate(set) var currentlySelectedSearchLanguage: MWKLanguageLink? {
        get {
            if let siteURL = UserDefaults.wmf_userDefaults().wmf_currentSearchLanguageDomain(), let selectedLanguage = MWKLanguageLinkController.sharedInstance().language(forSiteURL: siteURL) {
                return selectedLanguage
            }else{
                
                if let appLang = MWKLanguageLinkController.sharedInstance().appLanguage {
                    self.currentlySelectedSearchLanguage = appLang
                    return appLang
                }else{
                    assertionFailure("appLanguage should have been set at this point")
                    return nil
                }
            }
        }
        set {
            UserDefaults.wmf_userDefaults().wmf_setCurrentSearchLanguageDomain(newValue?.siteURL())
            delegate?.searchLanguagesBarViewController(self, didChangeCurrentlySelectedSearchLanguage: newValue!)
            updateLanguageBarLanguageButtons()
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        otherLanguagesButton?.setTitle(WMFLocalizedString("main-menu-title", value:"More", comment:"Title for menu of secondary items.\n{{Identical|More}}"), for: UIControlState())
        otherLanguagesButton?.titleLabel?.font = UIFont.wmf_subtitle()

        NotificationCenter.default.addObserver(forName: NSNotification.Name.WMFAppLanguageDidChange, object: nil, queue: nil) { notification in
            guard let langController = notification.object, let appLanguage = (langController as AnyObject).appLanguage else {
                assertionFailure("Could not extract app language from WMFAppLanguageDidChangeNotification")
                return
            }
            self.currentlySelectedSearchLanguage = appLanguage
        }

        NotificationCenter.default.addObserver(forName: NSNotification.Name.WMFPreferredLanguagesDidChange, object: nil, queue: nil) { _ in
            if let selectedLang = self.currentlySelectedSearchLanguage {
                // The selected lang won't be in languageBarLanguages() if the user has dragged it down so it's not in top 3 langs...
                if(self.languageBarLanguages().index(of: selectedLang) == nil){
                    // ...so select first lang if the selected lang has been moved down out of the top 3.
                    self.currentlySelectedSearchLanguage = self.languageBarLanguages().first
                    // Reminder: cannot use "reorderPreferredLanguage" for this (in "didUpdatePreferredLanguages:") because
                    // that would undo the dragging the user just did and would also not work for changes made from settings.
                }
            }
        }
        apply(theme: theme)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updateLanguageBarLanguageButtons()
        hidden = !UserDefaults.wmf_userDefaults().wmf_showSearchLanguageBar()

        var selectedButtonCount = 0
        for button in languageButtons{
            if button.isSelected {
                selectedButtonCount += 1
            }
        }
        assert(selectedButtonCount == 1, "One button should be selected by now")
    }
    
    fileprivate func languageBarLanguages() -> [MWKLanguageLink] {
        return Array(MWKLanguageLinkController.sharedInstance().preferredLanguages.prefix(3))
    }

    fileprivate func updateLanguageBarLanguageButtons(){
        for (index, language) in languageBarLanguages().enumerated() {
            if index >= languageButtons.count {
                break
            }
            let button = languageButtons[index]
            button.setTitle(language.localizedName, for: UIControlState())
            if let selectedLanguage = currentlySelectedSearchLanguage {
                button.isSelected = language.isEqual(to: selectedLanguage)
            }else{
                assertionFailure("selectedLanguage should have been set at this point")
                button.isSelected = false
            }
        }
        for(index, button) in languageButtons.enumerated(){
            if index >= languageBarLanguages().count {
                button.isEnabled = false
                button.isHidden = true
            }else{
                button.isEnabled = true
                button.isHidden = false
            }
        }
    }
    
    @IBAction fileprivate func setCurrentlySelectedLanguageToButtonLanguage(withSender sender: UIButton) {
        guard let buttonIndex = languageButtons.index(of: sender), languageBarLanguages().indices.contains(buttonIndex) else {
            assertionFailure("Language button not found for language")
            return
        }
        currentlySelectedSearchLanguage = languageBarLanguages()[buttonIndex]
    }
    
    @IBAction fileprivate func openLanguagePicker() {
        let languagesVC = WMFPreferredLanguagesViewController.preferredLanguagesViewController()
        languagesVC?.delegate = self
        if let themeable = languagesVC as Themeable? {
            themeable.apply(theme: self.theme)
        }
        present(ThemeableNavigationController(rootViewController: languagesVC!, theme: self.theme), animated: true, completion: nil)
    }
    
    func languagesController(_ controller: WMFLanguagesViewController!, didSelectLanguage language: MWKLanguageLink!) {
        // If the selected language will not be displayed because we only display max 3 languages, move it to index 2
        if(languageBarLanguages().index(of: language) == nil){
            MWKLanguageLinkController.sharedInstance().reorderPreferredLanguage(language, to: 2)
        }
        
        currentlySelectedSearchLanguage = language
        controller.dismiss(animated: true, completion: nil)
    }
    
    func apply(theme: Theme) {
        self.theme = theme
        guard viewIfLoaded != nil else {
            return
        }
        view.backgroundColor = theme.colors.paperBackground
        for languageButton in languageButtons {
            languageButton.setTitleColor(theme.colors.primaryText, for: .normal)
            languageButton.tintColor = theme.colors.link
        }
    }
}
