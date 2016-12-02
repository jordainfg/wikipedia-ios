let WMFAppLaunchDateKey = "WMFAppLaunchDateKey"
let WMFAppBecomeActiveDateKey = "WMFAppBecomeActiveDateKey"
let WMFAppResignActiveDateKey = "WMFAppResignActiveDateKey"
let WMFOpenArticleURLKey = "WMFOpenArticleURLKey"
let WMFAppSiteKey = "Domain"
let WMFSearchURLKey = "WMFSearchURLKey"
let WMFMigrateHistoryListKey = "WMFMigrateHistoryListKey"
let WMFMigrateToSharedContainerKey = "WMFMigrateToSharedContainerKey"
let WMFMigrateSavedPageListKey = "WMFMigrateSavedPageListKey"
let WMFMigrateBlackListKey = "WMFMigrateBlackListKey"
let WMFDidMigrateToGroupKey = "WMFDidMigrateToGroup"
let WMFDidMigrateToCoreDataFeedKey = "WMFDidMigrateToCoreDataFeedKey"
let WMFMostRecentInTheNewsNotificationDateKey = "WMFMostRecentInTheNewsNotificationDate"
let WMFInTheNewsMostRecentDateNotificationCountKey = "WMFInTheNewsMostRecentDateNotificationCount"
let WMFDidShowNewsNotificatonInFeedKey = "WMFDidShowNewsNotificatonInFeedKey"
let WMFInTheNewsNotificationsEnabled = "WMFInTheNewsNotificationsEnabled"

//Legacy Keys
let WMFOpenArticleTitleKey = "WMFOpenArticleTitleKey"
let WMFSearchLanguageKey = "WMFSearchLanguageKey"


public extension NSUserDefaults {
    
    public class func wmf_userDefaults() -> NSUserDefaults {
        guard let defaults = NSUserDefaults(suiteName: WMFApplicationGroupIdentifier) else {
            assert(false)
            return NSUserDefaults.standardUserDefaults()
        }
        return defaults
    }
    
    public class func wmf_migrateToWMFGroupUserDefaultsIfNecessary() {
        let newDefaults = self.wmf_userDefaults()
        let didMigrate = newDefaults.boolForKey(WMFDidMigrateToGroupKey)
        if (!didMigrate) {
            let oldDefaults = NSUserDefaults.standardUserDefaults()
            let oldDefaultsDictionary = oldDefaults.dictionaryRepresentation()
            for (key, value) in oldDefaultsDictionary {
                let lowercaseKey = key.lowercaseString
                if lowercaseKey.hasPrefix("apple") || lowercaseKey.hasPrefix("ns") {
                    continue
                }
                newDefaults.setObject(value, forKey: key)
            }
            newDefaults.setBool(true, forKey: WMFDidMigrateToGroupKey)
            newDefaults.synchronize()
        }
    }

    public func wmf_dateForKey(key: String) -> NSDate? {
        return self.objectForKey(key) as? NSDate
    }

    public func wmf_appLaunchDate() -> NSDate? {
        return self.wmf_dateForKey(WMFAppLaunchDateKey)
    }
    
    public func wmf_setAppLaunchDate(date: NSDate) {
        self.setObject(date, forKey: WMFAppLaunchDateKey)
        self.synchronize()
    }
    
    public func wmf_appBecomeActiveDate() -> NSDate? {
        return self.wmf_dateForKey(WMFAppBecomeActiveDateKey)
    }
    
    public func wmf_setAppBecomeActiveDate(date: NSDate?) {
        if let date = date {
            self.setObject(date, forKey: WMFAppBecomeActiveDateKey)
        }else{
            self.removeObjectForKey(WMFAppBecomeActiveDateKey)
        }
        self.synchronize()
    }
    
    public func wmf_appResignActiveDate() -> NSDate? {
        return self.wmf_dateForKey(WMFAppResignActiveDateKey)
    }
    
    public func wmf_setAppResignActiveDate(date: NSDate?) {
        if let date = date {
            self.setObject(date, forKey: WMFAppResignActiveDateKey)
        }else{
            self.removeObjectForKey(WMFAppResignActiveDateKey)
        }
        self.synchronize()
    }
    
    public func wmf_openArticleURL() -> NSURL? {
        if let url = self.URLForKey(WMFOpenArticleURLKey) {
            return url
        }else if let data = self.dataForKey(WMFOpenArticleTitleKey){
            if let title = NSKeyedUnarchiver.unarchiveObjectWithData(data) as? MWKTitle {
                self.wmf_setOpenArticleURL(title.mobileURL)
                return title.mobileURL
            }else{
                return nil
            }
        }else{
            return nil
        }
    }
    
    public func wmf_setOpenArticleURL(url: NSURL?) {
        guard let url = url else{
            self.removeObjectForKey(WMFOpenArticleURLKey)
            self.removeObjectForKey(WMFOpenArticleTitleKey)
            self.synchronize()
            return
        }
        guard !url.wmf_isNonStandardURL else{
            return;
        }
        
        self.setURL(url, forKey: WMFOpenArticleURLKey)
        self.synchronize()
    }

    public func wmf_setSendUsageReports(enabled: Bool) {
        self.setObject(NSNumber(bool: enabled), forKey: "SendUsageReports")
        self.synchronize()

    }

    public func wmf_sendUsageReports() -> Bool {
        if let enabled = self.objectForKey("SendUsageReports") as? NSNumber {
            return enabled.boolValue
        }else{
            return false
        }
    }
    
    public func wmf_setAppInstallDateIfNil(date: NSDate) {
        let previous = self.wmf_appInstallDate()
        
        if previous == nil {
            self.setObject(date, forKey: "AppInstallDate")
            self.synchronize()
        }
    }
    
    public func wmf_appInstallDate() -> NSDate? {
        if let date = self.objectForKey("AppInstallDate") as? NSDate {
            return date
        }else{
            return nil
        }
    }
    
    public func wmf_setDaysInstalled(daysInstalled: NSNumber) {
        self.setObject(daysInstalled, forKey: "DailyLoggingStatsDaysInstalled")
        self.synchronize()
    }

    public func wmf_daysInstalled() -> NSNumber? {
        return self.objectForKey("DailyLoggingStatsDaysInstalled") as? NSNumber
    }

    public func wmf_setShowSearchLanguageBar(enabled: Bool) {
        self.setObject(NSNumber(bool: enabled), forKey: "ShowLanguageBar")
        self.synchronize()
        
    }
    
    public func wmf_showSearchLanguageBar() -> Bool {
        if let enabled = self.objectForKey("ShowLanguageBar") as? NSNumber {
            return enabled.boolValue
        }else{
            return false
        }
    }
    
    public func wmf_currentSearchLanguageDomain() -> NSURL? {
        if let url = self.URLForKey(WMFSearchURLKey) {
            return url
        }else if let language = self.objectForKey(WMFSearchLanguageKey) as? String {
            let url = NSURL.wmf_URLWithDefaultSiteAndlanguage(language)
            self.wmf_setCurrentSearchLanguageDomain(url)
            return url
        }else{
            return nil
        }
    }
    
    public func wmf_setCurrentSearchLanguageDomain(url: NSURL?) {
        guard let url = url else{
            self.removeObjectForKey(WMFSearchURLKey)
            self.synchronize()
            return
        }
        guard !url.wmf_isNonStandardURL else{
            return;
        }
        
        self.setURL(url, forKey: WMFSearchURLKey)
        self.synchronize()
    }

    public func wmf_setReadingFontSize(fontSize: NSNumber) {
        self.setObject(fontSize, forKey: "ReadingFontSize")
        self.synchronize()
        
    }
    
    public func wmf_readingFontSize() -> NSNumber {
        if let fontSize = self.objectForKey("ReadingFontSize") as? NSNumber {
            return fontSize
        }else{
            return NSNumber(integer:100) //default is 100%
        }
    }
    
    public func wmf_setDidShowTableOfContentsAndFindInPageIconPopovers(shown: Bool) {
        self.setObject(NSNumber(bool: shown), forKey: "ShowTableOfContentsAndFindInPageIconPopovers")
        self.synchronize()
        
    }
    
    public func wmf_didShowTableOfContentsAndFindInPageIconPopovers() -> Bool {
        if let enabled = self.objectForKey("ShowTableOfContentsAndFindInPageIconPopovers") as? NSNumber {
            return enabled.boolValue
        }else{
            return false
        }
    }

    public func wmf_setTableOfContentsIsVisibleInline(visibleInline: Bool) {
        self.setObject(NSNumber(bool: visibleInline), forKey: "TableOfContentsIsVisibleInline")
        self.synchronize()
        
    }
    
    public func wmf_isTableOfContentsVisibleInline() -> Bool {
        if let enabled = self.objectForKey("TableOfContentsIsVisibleInline") as? NSNumber {
            return enabled.boolValue
        }else{
            return true
        }
    }
    
    public func wmf_setDidFinishLegacySavedArticleImageMigration(didFinish: Bool) {
        self.setBool(didFinish, forKey: "DidFinishLegacySavedArticleImageMigration")
        self.synchronize()
    }
    
    public func wmf_didFinishLegacySavedArticleImageMigration() -> Bool {
        return self.boolForKey("DidFinishLegacySavedArticleImageMigration")
    }
    
    public func wmf_setDidMigrateHistoryList(didFinish: Bool) {
        self.setBool(didFinish, forKey: WMFMigrateHistoryListKey)
        self.synchronize()
    }
    
    public func wmf_didMigrateHistoryList() -> Bool {
        return self.boolForKey(WMFMigrateHistoryListKey)
    }

    public func wmf_setDidMigrateSavedPageList(didFinish: Bool) {
        self.setBool(didFinish, forKey: WMFMigrateSavedPageListKey)
        self.synchronize()
    }
    
    public func wmf_didMigrateSavedPageList() -> Bool {
        return self.boolForKey(WMFMigrateSavedPageListKey)
    }

    public func wmf_setDidMigrateBlackList(didFinish: Bool) {
        self.setBool(didFinish, forKey: WMFMigrateBlackListKey)
        self.synchronize()
    }
    
    public func wmf_didMigrateBlackList() -> Bool {
        return self.boolForKey(WMFMigrateBlackListKey)
    }
    
    public func wmf_setDidMigrateToSharedContainer(didFinish: Bool) {
        self.setBool(didFinish, forKey: WMFMigrateToSharedContainerKey)
        self.synchronize()
    }
    
    public func wmf_didMigrateToSharedContainer() -> Bool {
        return self.boolForKey(WMFMigrateToSharedContainerKey)
    }

    public func wmf_setDidMigrateToNewFeed(didMigrate: Bool) {
        self.setBool(didMigrate, forKey: WMFDidMigrateToCoreDataFeedKey)
        self.synchronize()
    }
    
    public func wmf_didMigrateToNewFeed() -> Bool {
        return self.boolForKey(WMFDidMigrateToCoreDataFeedKey)
    }
    
    public func wmf_mostRecentInTheNewsNotificationDate() -> NSDate? {
        return self.wmf_dateForKey(WMFMostRecentInTheNewsNotificationDateKey)
    }
    
    public func wmf_setMostRecentInTheNewsNotificationDate(date: NSDate) {
        self.setObject(date, forKey: WMFMostRecentInTheNewsNotificationDateKey)
        self.synchronize()
    }
    
    public func wmf_inTheNewsMostRecentDateNotificationCount() -> Int {
        return self.integerForKey(WMFInTheNewsMostRecentDateNotificationCountKey)
    }
    
    public func wmf_setInTheNewsMostRecentDateNotificationCount(count: Int) {
        self.setInteger(count, forKey: WMFInTheNewsMostRecentDateNotificationCountKey)
        self.synchronize()
    }
    
    public func wmf_inTheNewsNotificationsEnabled() -> Bool {
        return self.boolForKey(WMFInTheNewsNotificationsEnabled)
    }
    
    public func wmf_setInTheNewsNotificationsEnabled(enabled: Bool) {
        self.setBool(enabled, forKey: WMFInTheNewsNotificationsEnabled)
        self.synchronize()
    }

    public func wmf_setDidShowNewsNotificationCardInFeed(didShow: Bool) {
        self.setBool(didShow, forKey: WMFDidShowNewsNotificatonInFeedKey)
        self.synchronize()
    }
    
    public func wmf_didShowNewsNotificationCardInFeed() -> Bool {
        return self.boolForKey(WMFDidShowNewsNotificatonInFeedKey)
    }
}
