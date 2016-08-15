import UIKit
import MessageUI

extension NSError {
    
    public func alertMessage() -> String {
        if(self.wmf_isNetworkConnectionError()){
            return localizedStringForKeyFallingBackOnEnglish("alert-no-internet")
        }else{
            return self.localizedDescription
        }
    }
    
    public func alertType() -> TSMessageNotificationType {
        if(self.wmf_isNetworkConnectionError()){
            return .Warning
        }else{
            return .Error
        }
    }

}


public class WMFAlertManager: NSObject, TSMessageViewProtocol, MFMailComposeViewControllerDelegate {
    
    public static let sharedInstance = WMFAlertManager()

    override init() {
        TSMessage.addCustomDesignFromFileWithName("AlertDesign.json")
        super.init()
    }
    
    public func showAlert(message: String, sticky:Bool, dismissPreviousAlerts:Bool, tapCallBack: dispatch_block_t?) {
    
         if (message ?? "").isEmpty {
             return
         }
         self.showAlert(dismissPreviousAlerts, alertBlock: { () -> Void in
            TSMessage.showNotificationInViewController(nil,
                title: message,
                subtitle: nil,
                image: nil,
                type: .Message,
                duration: sticky ? -1 : 2,
                callback: tapCallBack,
                buttonTitle: nil,
                buttonCallback: {},
                atPosition: .Top,
                canBeDismissedByUser: true)
        })
    }

    public func showSuccessAlert(message: String, sticky:Bool,dismissPreviousAlerts:Bool, tapCallBack: dispatch_block_t?) {
        
        self.showAlert(dismissPreviousAlerts, alertBlock: { () -> Void in
            TSMessage.showNotificationInViewController(nil,
                title: message,
                subtitle: nil,
                image: nil,
                type: .Success,
                duration: sticky ? -1 : 2,
                callback: tapCallBack,
                buttonTitle: nil,
                buttonCallback: {},
                atPosition: .Top,
                canBeDismissedByUser: true)

        })
    }

    public func showWarningAlert(message: String, sticky:Bool,dismissPreviousAlerts:Bool, tapCallBack: dispatch_block_t?) {
        
        self.showAlert(dismissPreviousAlerts, alertBlock: { () -> Void in
            TSMessage.showNotificationInViewController(nil,
                title: message,
                subtitle: nil,
                image: nil,
                type: .Warning,
                duration: sticky ? -1 : 2,
                callback: tapCallBack,
                buttonTitle: nil,
                buttonCallback: {},
                atPosition: .Top,
                canBeDismissedByUser: true)
        })
    }

    public func showErrorAlert(error: NSError, sticky:Bool,dismissPreviousAlerts:Bool, tapCallBack: dispatch_block_t?) {
        
        self.showAlert(dismissPreviousAlerts, alertBlock: { () -> Void in
            TSMessage.showNotificationInViewController(nil,
                title: error.alertMessage(),
                subtitle: nil,
                image: nil,
                type: error.alertType(),
                duration: sticky ? -1 : 2,
                callback: tapCallBack,
                buttonTitle: nil,
                buttonCallback: {},
                atPosition: .Top,
                canBeDismissedByUser: true)
        })
    }
    
    public func showErrorAlertWithMessage(message: String, sticky:Bool,dismissPreviousAlerts:Bool, tapCallBack: dispatch_block_t?) {
        
        self.showAlert(dismissPreviousAlerts, alertBlock: { () -> Void in
            TSMessage.showNotificationInViewController(nil,
                title: message,
                subtitle: nil,
                image: nil,
                type: .Error,
                duration: sticky ? -1 : 2,
                callback: tapCallBack,
                buttonTitle: nil,
                buttonCallback: {},
                atPosition: .Top,
                canBeDismissedByUser: true)
        })
    }

    func showAlert(dismissPreviousAlerts:Bool, alertBlock: dispatch_block_t){
        
        if(dismissPreviousAlerts){
            TSMessage.dismissAllNotificationsWithCompletion({ () -> Void in
                alertBlock()
            })
        }else{
            alertBlock()
        }
    }
    
    public func dismissAlert() {
        
        TSMessage.dismissActiveNotification()
    }

    public func dismissAllAlerts() {
        
        TSMessage.dismissAllNotifications()
    }

    public func customizeMessageView(messageView: TSMessageView!) {
        
        
    }
    
    public func showEmailFeedbackAlertViewWithError(error: NSError) {
        let message = localizedStringForKeyFallingBackOnEnglish("request-feedback-on-error")
        showErrorAlertWithMessage(message, sticky: true, dismissPreviousAlerts: true) {
            self.dismissAllAlerts()
            if MFMailComposeViewController.canSendMail() {
                guard let rootVC = UIApplication.sharedApplication().keyWindow?.rootViewController else {
                    return
                }
                let vc = MFMailComposeViewController()
                vc.setSubject("Bug:\(WikipediaAppUtils.versionedUserAgent())")
                vc.setToRecipients(["mobile-ios-wikipedia@wikimedia.org"])
                vc.mailComposeDelegate = self
                vc.setMessageBody("Domain:\t\(error.domain)\nCode:\t\(error.code)\nDescription:\t\(error.localizedDescription)\n\n\n\nVersion:\t\(WikipediaAppUtils.versionedUserAgent())", isHTML: false)
                rootVC.presentViewController(vc, animated: true, completion: nil)
            } else {
                self.showErrorAlertWithMessage(localizedStringForKeyFallingBackOnEnglish("no-email-account-alert"), sticky: false, dismissPreviousAlerts: false, tapCallBack: nil)
            }
        }
    }
    
    public func mailComposeController(controller: MFMailComposeViewController, didFinishWithResult result: MFMailComposeResult, error: NSError?) {
        controller.dismissViewControllerAnimated(true, completion: nil)
    }
}
