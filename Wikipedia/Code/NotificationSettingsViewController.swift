import UIKit
import UserNotifications
import WMF

protocol NotificationSettingsItem {
    var title: String { get }
}

struct NotificationSettingsSwitchItem: NotificationSettingsItem {
    let title: String
    let switchChecker: () -> Bool
    let switchAction: (Bool) -> Void
}

struct NotificationSettingsButtonItem: NotificationSettingsItem {
    let title: String
    let buttonAction: () -> Void
}

struct NotificationSettingsSection {
    let headerTitle:String
    let items: [NotificationSettingsItem]
}

class NotificationSettingsViewController: UIViewController, UITableViewDataSource, UITableViewDelegate, WMFAnalyticsContextProviding, WMFAnalyticsContentTypeProviding {

    @IBOutlet weak var tableView: UITableView!
    
    
    var sections = [NotificationSettingsSection]()
    var observationToken: NSObjectProtocol?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.contentInset = UIEdgeInsets(top: 10, left: 0, bottom: 0, right: 0);
        tableView.register(WMFSettingsTableViewCell.wmf_classNib(), forCellReuseIdentifier: WMFSettingsTableViewCell.identifier())
        tableView.delegate = self
        tableView.dataSource = self
        observationToken = NotificationCenter.default.addObserver(forName: NSNotification.Name.UIApplicationDidBecomeActive, object: nil, queue: OperationQueue.main) { [weak self] (note) in
            self?.updateSections()
        }
    }
    
    deinit {
        if let token = observationToken {
            NotificationCenter.default.removeObserver(token)
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
       super.viewWillAppear(animated)
       updateSections()
    }
    
    func analyticsContext() -> String {
        return "notification"
    }
    
    func analyticsContentType() -> String {
        return "current events"
    }
    
    func sectionsForSystemSettingsAuthorized() -> [NotificationSettingsSection] {
        var updatedSections = [NotificationSettingsSection]()
        
        let infoItems: [NotificationSettingsItem] = [NotificationSettingsButtonItem(title: localizedStringForKeyFallingBackOnEnglish("settings-notifications-learn-more"), buttonAction: { [weak self] in
            let title = localizedStringForKeyFallingBackOnEnglish("welcome-notifications-tell-me-more-title")
            let message = "\(localizedStringForKeyFallingBackOnEnglish("welcome-notifications-tell-me-more-storage"))\n\n\(localizedStringForKeyFallingBackOnEnglish("welcome-notifications-tell-me-more-creation"))"
            let alertController = UIAlertController(title: title, message: message, preferredStyle: UIAlertControllerStyle.alert)
            alertController.addAction(UIAlertAction(title: localizedStringForKeyFallingBackOnEnglish("welcome-explore-tell-me-more-done-button"), style: UIAlertActionStyle.default, handler: { (action) in
            }))
            self?.present(alertController, animated: true, completion: nil)
        })]
        
        let infoSection = NotificationSettingsSection(headerTitle: localizedStringForKeyFallingBackOnEnglish("settings-notifications-info"), items: infoItems)
        updatedSections.append(infoSection)
        
        let notificationSettingsItems: [NotificationSettingsItem] = [NotificationSettingsSwitchItem(title: localizedStringForKeyFallingBackOnEnglish("settings-notifications-trending"), switchChecker: { () -> Bool in
            return UserDefaults.wmf_userDefaults().wmf_inTheNewsNotificationsEnabled()
            }, switchAction: { (isOn) in
                //This (and everything else that references UNUserNotificationCenter in this class) should be moved into WMFNotificationsController
                if #available(iOS 10.0, *) {
                    if (isOn) {
                        WMFNotificationsController.shared().requestAuthenticationIfNecessary(completionHandler: { (granted, error) in
                            if let error = error as? NSError {
                                self.wmf_showAlertWithError(error)
                            }
                        })
                    } else {
                        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
                    }
                }
                
                if isOn {
                    PiwikTracker.sharedInstance()?.wmf_logActionEnable(inContext: self, contentType: self)
                }else{
                    PiwikTracker.sharedInstance()?.wmf_logActionDisable(inContext: self, contentType: self)
                }
            UserDefaults.wmf_userDefaults().wmf_setInTheNewsNotificationsEnabled(isOn)
        })]
        let notificationSettingsSection = NotificationSettingsSection(headerTitle: localizedStringForKeyFallingBackOnEnglish("settings-notifications-push-notifications"), items: notificationSettingsItems)
        
        updatedSections.append(notificationSettingsSection)
        return updatedSections
    }
    
    func sectionsForSystemSettingsUnauthorized()  -> [NotificationSettingsSection] {
        let unauthorizedItems: [NotificationSettingsItem] = [NotificationSettingsButtonItem(title: localizedStringForKeyFallingBackOnEnglish("settings-notifications-system-turn-on"), buttonAction: {
            guard let URL = URL(string: UIApplicationOpenSettingsURLString) else {
                return
            }
            UIApplication.shared.openURL(URL)
        })]
        return [NotificationSettingsSection(headerTitle: localizedStringForKeyFallingBackOnEnglish("settings-notifications-info"), items: unauthorizedItems)]
    }
    
    func updateSections() {
        tableView.reloadData()
        if #available(iOS 10.0, *) {
            UNUserNotificationCenter.current().getNotificationSettings { (settings) in
                DispatchQueue.main.async(execute: { 
                    switch settings.authorizationStatus {
                    case .authorized:
                        fallthrough
                    case .notDetermined:
                        self.sections = self.sectionsForSystemSettingsAuthorized()
                        break
                    case .denied:
                        self.sections = self.sectionsForSystemSettingsUnauthorized()
                        break
                    }
                    self.tableView.reloadData()
                })
            }
        }
    }
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return sections.count
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return sections[section].items.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: WMFSettingsTableViewCell.identifier(), for: indexPath) as? WMFSettingsTableViewCell else {
            return UITableViewCell()
        }
        
        let item = sections[indexPath.section].items[indexPath.item]
        cell.title = item.title
        cell.iconName = nil
        
        if let switchItem = item as? NotificationSettingsSwitchItem {
            cell.disclosureType = .switch
            cell.disclosureSwitch.isOn = switchItem.switchChecker()
            cell.disclosureSwitch.addTarget(self, action: #selector(self.handleSwitchValueChange(_:)), for: .valueChanged)
        } else {
            cell.disclosureType = .viewController
        }
        
        
        return cell
    }
    
    func handleSwitchValueChange(_ sender: UISwitch) {
        // FIXME: hardcoded item below
        let item = sections[1].items[0]
        if let switchItem = item as? NotificationSettingsSwitchItem {
            switchItem.switchAction(sender.isOn)
        }
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let header = WMFTableHeaderLabelView.wmf_viewFromClassNib()
        header?.text = sections[section].headerTitle
        return header;
    }
    
    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        let header = WMFTableHeaderLabelView.wmf_viewFromClassNib()
        header?.text = sections[section].headerTitle
        return header!.height(withExpectedWidth: self.view.frame.width)
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard let item = sections[indexPath.section].items[indexPath.item] as? NotificationSettingsButtonItem else {
            return
        }
        
        item.buttonAction()
        tableView.deselectRow(at: indexPath, animated: true)
    }
    
    
    func tableView(_ tableView: UITableView, shouldHighlightRowAt indexPath: IndexPath) -> Bool {
        return sections[indexPath.section].items[indexPath.item] as? NotificationSettingsSwitchItem == nil
    }
}
