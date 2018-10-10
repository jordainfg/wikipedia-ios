
/**
 *  This class provides a simple interface for performing authentication tasks.
 */
public class WMFAuthenticationManager: NSObject {

    var loginSiteURL: URL {
        var url: URL?
        if let host = KeychainCredentialsManager.shared.host {
            var components = URLComponents()
            components.host = host
            components.scheme = "https"
            url = components.url
        }

        if url == nil {
            url = MWKLanguageLinkController.sharedInstance().appLanguage?.siteURL()
        }

        guard let loginSiteURL = url else {
            let fallbackURLString = "https://en.wikipedia.org"
            if let fallbackLoginURL = URL(string: fallbackURLString) {
                return fallbackLoginURL
            } else {
                preconditionFailure("Failed to construct a fallback login URL with string: \(fallbackURLString)")
            }
        }
        return loginSiteURL
    }

    /**
     *  The current logged in user. If nil, no user is logged in
     */
    @objc dynamic private(set) var loggedInUsername: String? = nil {
        didSet {
            SessionSingleton.sharedInstance().dataStore.readingListsController.authenticationDelegate = self
        }
    }
    
    /**
     *  Returns YES if a user is logged in, NO otherwise
     */
    @objc public var isLoggedIn: Bool {
        return (loggedInUsername != nil)
    }

    @objc public var hasKeychainCredentials: Bool {
        guard
            let userName = KeychainCredentialsManager.shared.username,
            userName.count > 0,
            let password = KeychainCredentialsManager.shared.password,
            password.count > 0
            else {
                return false
        }
        return true
    }
    
    fileprivate let loginInfoFetcher = WMFAuthLoginInfoFetcher()
    fileprivate let tokenFetcher = WMFAuthTokenFetcher()
    fileprivate let accountLogin = WMFAccountLogin()
    fileprivate let currentlyLoggedInUserFetcher = WMFCurrentlyLoggedInUserFetcher()
    
    /**
     *  Get the shared instance of this class
     *
     *  @return The shared Authentication Manager
     */
    @objc public static let sharedInstance = WMFAuthenticationManager()

    public enum LoginResult {
        case success(_: WMFAccountLoginResult)
        case alreadyLoggedIn(_: WMFCurrentlyLoggedInUser)
        case failure(_: Error)
    }

    public typealias LoginResultHandler = (LoginResult) -> Void
    
    public func attemptLogin(completion: @escaping LoginResultHandler) {
        self.loginWithSavedCredentials() { (loginResult) in
            switch loginResult {
            case .success(let result):
                DDLogDebug("\n\nSuccessfully logged in with saved credentials for user \(result.username).\n\n")
            case .alreadyLoggedIn(let result):
                DDLogDebug("\n\nUser \(result.name) is already logged in.\n\n")
            case .failure(let error):
                DDLogDebug("\n\nloginWithSavedCredentials failed with error \(error).\n\n")
            }
            DispatchQueue.main.async {
                completion(loginResult)
            }
        }
    }
    
    /**
     *  Login with the given username and password
     *
     *  @param username The username to authenticate
     *  @param password The password for the user
     *  @param retypePassword The password used for confirming password changes. Optional.
     *  @param oathToken Two factor password required if user's account has 2FA enabled. Optional.
     *  @param loginSuccess  The handler for success - at this point the user is logged in
     *  @param failure     The handler for any errors
     */
    public func login(username: String, password: String, retypePassword: String?, oathToken: String?, captchaID: String?, captchaWord: String?, completion: @escaping LoginResultHandler) {
        let siteURL = loginSiteURL
        self.tokenFetcher.fetchToken(ofType: .login, siteURL: loginSiteURL, success: { (token) in
            self.accountLogin.login(username: username, password: password, retypePassword: retypePassword, loginToken: token.token, oathToken: oathToken, captchaID: captchaID, captchaWord: captchaWord, siteURL: siteURL, success: { (result) in
                let normalizedUserName = result.username
                self.loggedInUsername = normalizedUserName
                KeychainCredentialsManager.shared.username = normalizedUserName
                KeychainCredentialsManager.shared.password = password
                KeychainCredentialsManager.shared.host = siteURL.host
                self.cloneSessionCookies()
                SessionSingleton.sharedInstance()?.dataStore.clearMemoryCache()
                completion(.success(result))
            }, failure: { (error) in
                completion(.failure(error))
            })
        }) { (error) in
            completion(.failure(error))
        }
    }
    
    /**
     *  Logs in a user using saved credentials in the keychain
     *
     *  @param success  The handler for success - at this point the user is logged in
     *  @param userAlreadyLoggedInHandler     The handler called if a user was found to already be logged in
     *  @param failure     The handler for any errors
     */
    public func loginWithSavedCredentials(completion: @escaping LoginResultHandler) {
        guard hasKeychainCredentials,
            let userName = KeychainCredentialsManager.shared.username,
            let password = KeychainCredentialsManager.shared.password
        else {
            let error = WMFCurrentlyLoggedInUserFetcherError.blankUsernameOrPassword
            completion(.failure(error))
            return
        }
        
        currentlyLoggedInUserFetcher.fetch(siteURL: loginSiteURL, success: { result in
            self.loggedInUsername = result.name
            completion(.alreadyLoggedIn(result))
        }, failure:{ error in
            guard !(error is URLError) else {
                self.loggedInUsername = userName
                let loginResult = WMFAccountLoginResult(status: WMFAccountLoginResult.Status.offline, username: userName, message: nil)
                completion(.success(loginResult))
                return
            }
            self.login(username: userName, password: password, retypePassword: nil, oathToken: nil, captchaID: nil, captchaWord: nil, completion: { (loginResult) in
                switch loginResult {
                case .success(let result):
                    completion(.success(result))
                case .failure(let error):
                    guard !(error is URLError) else {
                        self.loggedInUsername = userName
                        let loginResult = WMFAccountLoginResult(status: WMFAccountLoginResult.Status.offline, username: userName, message: nil)
                        completion(.success(loginResult))
                        return
                    }
                    self.loggedInUsername = nil
                    self.logout()
                    completion(.failure(error))
                default:
                    break
                }
            })
        })
    }
    
    fileprivate var logoutManager: AFHTTPSessionManager?
    
    fileprivate func resetLocalUserLoginSettings() {
        KeychainCredentialsManager.shared.username = nil
        KeychainCredentialsManager.shared.password = nil
        self.loggedInUsername = nil
        // Cookie reminders:
        //  - "HTTPCookieStorage.shared.removeCookies(since: Date.distantPast)" does NOT seem to work.
        HTTPCookieStorage.shared.cookies?.forEach { cookie in
            HTTPCookieStorage.shared.deleteCookie(cookie)
        }
        SessionSingleton.sharedInstance()?.dataStore.clearMemoryCache()
        
        SessionSingleton.sharedInstance().dataStore.readingListsController.setSyncEnabled(false, shouldDeleteLocalLists: false, shouldDeleteRemoteLists: false)
        
        // Reset so can show for next logged in user.
        UserDefaults.wmf_userDefaults().wmf_setDidShowEnableReadingListSyncPanel(false)
        UserDefaults.wmf_userDefaults().wmf_setDidShowSyncEnabledPanel(false)
    }
    
    /**
     *  Logs out any authenticated user and clears out any associated cookies
     */
    @objc public func logout(completion: @escaping () -> Void = {}) {
        let reset = {
            DDLogDebug("Deleted login tokens and other browser cookies")
            self.resetLocalUserLoginSettings()
        }
        logoutManager = AFHTTPSessionManager(baseURL: loginSiteURL)
        _ = logoutManager?.wmf_apiPOST(with: ["action": "logout", "format": "json"], success: { (task, response) in
            DDLogDebug("Successfully logged out")
            // It's best to call "action=logout" API *before* clearing local login settings...
            reset()
            completion()
        }, failure: { (task, error) in
            // ...but if "action=logout" fails we *still* want to clear local login settings, which still effectively logs the user out.
            DDLogDebug("Failed to log out: \(error)")
            reset()
            completion()
        })
    }
    
    fileprivate func cloneSessionCookies() {
        // Make the session cookies expire at same time user cookies. Just remember they still can't be
        // necessarily assumed to be valid as the server may expire them, but at least make them last as
        // long as we can to lessen number of server requests. Uses user tokens as templates for copying
        // session tokens. See "recreateCookie:usingCookieAsTemplate:" for details.
        guard let domain = MWKLanguageLinkController.sharedInstance().appLanguage?.languageCode else {
            return
        }
        let cookie1Name = "\(domain)wikiSession"
        let cookie2Name = "\(domain)wikiUserID"
        HTTPCookieStorage.shared.wmf_recreateCookie(cookie1Name, withDomain: loginSiteURL.host, usingCookieAsTemplate: cookie2Name, templateDomain: loginSiteURL.host)
        HTTPCookieStorage.shared.wmf_recreateCookie("centralauth_Session", withDomain: ".wikipedia.org", usingCookieAsTemplate: "centralauth_User", templateDomain: ".wikipedia.org")
        recreateWikidataCookies()
    }

    private func createWikidataCookies() {
        let sessionCookieName = "centralauth_Session"
        let userCookieName = "centralauth_User"
        let templateCookieDomain = ".wikipedia.org"
        HTTPCookieStorage.shared.wmf_createCookie(withName: sessionCookieName, newDomain: WikidataAPI.host, usingCookieAsTemplate: sessionCookieName, templateDomain: templateCookieDomain)
        HTTPCookieStorage.shared.wmf_createCookie(withName: userCookieName, newDomain: WikidataAPI.host, usingCookieAsTemplate: userCookieName, templateDomain: templateCookieDomain)
    }

    private func recreateWikidataCookies() {
        let sessionCookieName = "centralauth_Session"
        let userCookieName = "centralauth_User"
        let templateCookieDomain = ".wikipedia.org"
        HTTPCookieStorage.shared.wmf_recreateCookie(sessionCookieName, withDomain: WikidataAPI.host, usingCookieAsTemplate: userCookieName, templateDomain: templateCookieDomain)
        HTTPCookieStorage.shared.wmf_recreateCookie(userCookieName, withDomain: WikidataAPI.host, usingCookieAsTemplate: userCookieName, templateDomain: templateCookieDomain)
    }

    public func createWikidataCookiesIfNecessary() {
        guard let wikidataURL = WikidataAPI.urlWithoutAPIPath else {
            assertionFailure("Wikidata URL cannot be nil")
            return
        }
        guard let wikidataCookies = HTTPCookieStorage.shared.cookies(for: wikidataURL), wikidataCookies.count == 2 else {
            createWikidataCookies()
            return
        }
    }
}

extension WMFAuthenticationManager: AuthenticationDelegate {
    public func isUserLoggedInLocally() -> Bool {
        return isLoggedIn
    }
    
    public func isUserLoggedInRemotely() -> Bool {
        let taskGroup = WMFTaskGroup()
        let sessionManager = AFHTTPSessionManager(baseURL: loginSiteURL)
        var errorCode: String? = nil
        taskGroup.enter()
        _ = sessionManager.wmf_apiPOST(with: ["action": "query", "format": "json", "assert": "user", "assertuser": nil], success: { (_, response) in
            if let response = response as? [String: AnyObject], let error = response["error"] as? [String: Any], let code = error["code"] as? String {
                errorCode = code
            }
            taskGroup.leave()
        }, failure: { (_, error) in
            taskGroup.leave()
        })
        taskGroup.wait()
        return errorCode == nil
    }

}

// MARK: @objc Wikipedia login
extension WMFAuthenticationManager {
    @objc public func attemptLogin(completion: @escaping () -> Void = {}, failure: @escaping (_ error: Error) -> Void = {_ in }) {
        let completion: LoginResultHandler = { result in
            completion()
        }
        attemptLogin(completion: completion)
    }

    @objc func loginWithSavedCredentials(success: @escaping WMFAccountLoginResultBlock, userAlreadyLoggedInHandler: @escaping WMFCurrentlyLoggedInUserBlock, failure: @escaping WMFErrorHandler) {
        let completion: LoginResultHandler = { loginResult in
            switch loginResult {
            case .success(let result):
                success(result)
            case .alreadyLoggedIn(let result):
                userAlreadyLoggedInHandler(result)
            case .failure(let error):
                failure(error)
            }
        }
        loginWithSavedCredentials(completion: completion)
    }
}
