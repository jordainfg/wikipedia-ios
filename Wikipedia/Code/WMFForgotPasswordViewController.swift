
import UIKit

class WMFForgotPasswordViewController: WMFScrollViewController {

    @IBOutlet fileprivate var titleLabel: UILabel!
    @IBOutlet fileprivate var subTitleLabel: UILabel!
    @IBOutlet fileprivate var usernameField: UITextField!
    @IBOutlet fileprivate var emailField: UITextField!
    @IBOutlet fileprivate var usernameUnderlineHeight: NSLayoutConstraint!
    @IBOutlet fileprivate var emailUnderlineHeight: NSLayoutConstraint!

    fileprivate var resetButton: UIBarButtonItem!

    let tokenFetcher = WMFAuthTokenFetcher()
    let passwordResetter = WMFPasswordResetter()

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.leftBarButtonItem = UIBarButtonItem(image: UIImage(named:"close"), style: .plain, target:self, action:#selector(closeButtonPushed(_:)))
    
        titleLabel.text = localizedStringForKeyFallingBackOnEnglish("forgot-password-title")
        subTitleLabel.text = localizedStringForKeyFallingBackOnEnglish("forgot-password-instructions")
        usernameField.placeholder = localizedStringForKeyFallingBackOnEnglish("forgot-password-username-prompt")
        emailField.placeholder = localizedStringForKeyFallingBackOnEnglish("forgot-password-email-prompt")
        
        resetButton = UIBarButtonItem(title: localizedStringForKeyFallingBackOnEnglish("forgot-password-button-title"), style: .plain, target: self, action: #selector(resetButtonPushed(_:)))
        navigationItem.rightBarButtonItem = resetButton
    
        usernameField.addTarget(self, action: #selector(textFieldDidChange(_:)), for: .editingChanged)
        emailField.addTarget(self, action: #selector(textFieldDidChange(_:)), for: .editingChanged)
    
        usernameUnderlineHeight.constant = 1.0 / UIScreen.main.scale
        emailUnderlineHeight.constant = 1.0 / UIScreen.main.scale
        
        view.wmf_configureSubviewsForDynamicType()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        enableProgressiveButton(false)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        usernameField.becomeFirstResponder()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        enableProgressiveButton(false)
    }
    
    public func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        if (textField == usernameField) {
            emailField.becomeFirstResponder()
        } else if (textField == emailField) {
            save()
        }
        return true
    }

    func textFieldDidChange(_ sender: UITextField) {
        guard
            let username = usernameField.text,
            let email = emailField.text
            else{
                enableProgressiveButton(false)
                return
        }
        enableProgressiveButton((username.characters.count > 0 || email.characters.count > 0))
    }

    func enableProgressiveButton(_ highlight: Bool) {
        resetButton.isEnabled = highlight
    }

    func resetButtonPushed(_ : UIBarButtonItem) {
        save()
    }

    fileprivate func save() {
        wmf_hideKeyboard()
        sendPasswordResetEmail(userName: usernameField.text, email: emailField.text)
    }
    
    func closeButtonPushed(_ : UIBarButtonItem) {
        dismiss(animated: true, completion: nil)
    }
    
    func sendPasswordResetEmail(userName: String?, email: String?) {
        guard let siteURL = MWKLanguageLinkController.sharedInstance().appLanguage?.siteURL() else {
            WMFAlertManager.sharedInstance.showAlert("No site url", sticky: true, dismissPreviousAlerts: true, tapCallBack: nil)
            return
        }
        
        let failure: WMFErrorHandler = {error in
            WMFAlertManager.sharedInstance.showErrorAlert(error as NSError, sticky: true, dismissPreviousAlerts: true, tapCallBack: nil)
        }
        
        tokenFetcher.fetchToken(ofType: .csrf, siteURL: siteURL, success: { tokenBlock in
            self.passwordResetter.resetPassword(
                siteURL: siteURL,
                token: tokenBlock.token,
                userName: userName,
                email: email,
                success: { result in
                    self.dismiss(animated: true, completion:nil)
                    WMFAlertManager.sharedInstance.showSuccessAlert(localizedStringForKeyFallingBackOnEnglish("forgot-password-email-sent"), sticky: true, dismissPreviousAlerts: true, tapCallBack: nil)
            }, failure:failure)
        }, failure:failure)
    }
}
