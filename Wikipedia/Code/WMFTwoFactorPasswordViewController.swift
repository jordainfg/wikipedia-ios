
import UIKit

class WMFTwoFactorPasswordViewController: WMFScrollViewController, UITextFieldDelegate {
    
    @IBOutlet fileprivate var titleLabel: UILabel!
    @IBOutlet fileprivate var subTitleLabel: UILabel!
    @IBOutlet fileprivate var tokenLabel: UILabel!
    @IBOutlet fileprivate var oathTokenFields: [UITextField]!
    
    @IBOutlet fileprivate var loginButton: WMFAuthButton!
    
    public var funnel: LoginFunnel?
    
    public var userName:String?
    public var password:String?
    public var captchaID:String?
    public var captchaWord:String?
    
    @IBAction fileprivate func loginButtonTapped(withSender sender: UIButton) {
        save()
    }
    
    fileprivate func areRequiredFieldsPopulated() -> Bool {
        return oathTokenFields.first(where:{ $0.text?.characters.count == 0 }) == nil
    }
    
    @IBAction func textFieldDidChange(_ sender: UITextField) {
        enableProgressiveButton(areRequiredFieldsPopulated())
        
        guard let text = sender.text, text.characters.count > 0 else {
            return
        }
        makeNextTextFieldFirstResponderIfBlank(currentTextField: sender)
    }
    
    fileprivate func makeNextTextFieldFirstResponderIfBlank(currentTextField: UITextField) {
        if let index = oathTokenFields.index(of: currentTextField) {
            let nextIndex = index + 1
            if nextIndex < oathTokenFields.count {
                let nextField = oathTokenFields[nextIndex]
                if nextField.text?.characters.count == 0 {
                    nextField.becomeFirstResponder()
                }
            }
        }
    }
    
    func enableProgressiveButton(_ highlight: Bool) {
        loginButton.isEnabled = highlight
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        enableProgressiveButton(false)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        oathTokenFields.first?.becomeFirstResponder()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        enableProgressiveButton(false)
    }
    
    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        guard let text = textField.text else {
            return false
        }
        return ((text + string).characters.count <= 1)
    }
    
    func textFieldDidBeginEditing(_ textField: UITextField) {
        // In the storyboard we've set the text fields' to "Clear when editing begins", but
        // the "Editing changed" handler "textFieldDidChange" isn't called when this clearing
        // happens, so update progressive buttons' enabled state here too.
        enableProgressiveButton(areRequiredFieldsPopulated())
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.leftBarButtonItem = UIBarButtonItem(image: UIImage(named:"close"), style: .plain, target:self, action:#selector(closeButtonPushed(_:)))
        
        loginButton.setTitle(localizedStringForKeyFallingBackOnEnglish("two-factor-login-continue"), for: .normal)
        
        titleLabel.text = localizedStringForKeyFallingBackOnEnglish("two-factor-login-title")
        subTitleLabel.text = localizedStringForKeyFallingBackOnEnglish("two-factor-login-instructions")
        tokenLabel.text = localizedStringForKeyFallingBackOnEnglish("field-token-title")

        view.wmf_configureSubviewsForDynamicType()
    }
    
    func closeButtonPushed(_ : UIBarButtonItem) {
        dismiss(animated: true, completion: nil)
    }
    
    fileprivate func token() -> String {
        return oathTokenFields.reduce("", { $0 + ($1.text ?? "") })
    }
    
    fileprivate func save() {
        wmf_hideKeyboard()
        enableProgressiveButton(false)
        WMFAlertManager.sharedInstance.dismissAlert()
        
        guard
            let userName = userName,
            let password = password
        else {
            return
        }

        WMFAuthenticationManager.sharedInstance
            .login(username: userName,
                   password: password,
                   retypePassword: nil,
                   oathToken: token(),
                   captchaID: captchaID,
                   captchaWord: captchaWord,
                   success: { _ in
                    let loggedInMessage = localizedStringForKeyFallingBackOnEnglish("main-menu-account-title-logged-in").replacingOccurrences(of: "$1", with: userName)
                    WMFAlertManager.sharedInstance.showSuccessAlert(loggedInMessage, sticky: false, dismissPreviousAlerts: true, tapCallBack: nil)
                    self.dismiss(animated: true, completion: nil)
                    self.funnel?.logSuccess()
            }, failure: { error in
                
                if let error = error as? WMFAccountLoginError {
                    switch error {
                    case .temporaryPasswordNeedsChange:
                        self.showChangeTempPasswordViewController()
                        return
                    default: break
                    }
                }
                
                self.enableProgressiveButton(true)
                WMFAlertManager.sharedInstance.showErrorAlert(error as NSError, sticky: true, dismissPreviousAlerts: true, tapCallBack: nil)
                self.funnel?.logError(error.localizedDescription)
                self.oathTokenFields.forEach {$0.text = nil}
                self.oathTokenFields.first?.becomeFirstResponder()
            })
    }
    
    func showChangeTempPasswordViewController() {
        guard
            let presenter = presentingViewController,
            let changePasswordVC = WMFChangePasswordViewController.wmf_initialViewControllerFromClassStoryboard()
        else {
            assert(false, "Expected view controller(s) not found")
            return
        }
        dismiss(animated: true, completion: {
            changePasswordVC.userName = self.userName
            let navigationController = UINavigationController.init(rootViewController: changePasswordVC)
            presenter.present(navigationController, animated: true, completion: nil)
        })
    }
}
