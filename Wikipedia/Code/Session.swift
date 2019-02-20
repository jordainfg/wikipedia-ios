import Foundation

@objc(WMFSession) public class Session: NSObject {
    public struct Request {
        public enum Method {
            case get
            case post
            case put
            case delete

            var stringValue: String {
                switch self {
                case .post:
                    return "POST"
                case .put:
                    return "PUT"
                case .delete:
                    return "DELETE"
                case .get:
                    fallthrough
                default:
                    return "GET"
                }
            }
        }

        public enum Encoding {
            case json
            case form
        }

    }
    
    public var xWMFUUID: String? = nil // event logging uuid, set if enabled, nil if disabled
    
    private static let defaultCookieStorage: HTTPCookieStorage = {
        let storage = HTTPCookieStorage.shared
        storage.cookieAcceptPolicy = .always
        return storage
    }()
    
    public func cloneCentralAuthCookies() {
        // centralauth_ cookies work for any central auth domain - this call copies the centralauth_* cookies from .wikipedia.org to an explicit list of domains. This is  hardcoded because we only want to copy ".wikipedia.org" cookies regardless of WMFDefaultSiteDomain
        defaultURLSession.configuration.httpCookieStorage?.copyCookiesWithNamePrefix("centralauth_", for: configuration.centralAuthCookieSourceDomain, to: configuration.centralAuthCookieTargetDomains)
        cacheQueue.async(flags: .barrier) {
            self._isAuthenticated = nil
        }
    }
    
    public func removeAllCookies() {
        guard let storage = defaultURLSession.configuration.httpCookieStorage else {
            return
        }
        // Cookie reminders:
        //  - "HTTPCookieStorage.shared.removeCookies(since: Date.distantPast)" does NOT seem to work.
        storage.cookies?.forEach { cookie in
            storage.deleteCookie(cookie)
        }
        cacheQueue.async(flags: .barrier) {
            self._isAuthenticated = nil
        }
    }
    
    @objc public static var defaultConfiguration: URLSessionConfiguration {
        let config = URLSessionConfiguration.default
        config.httpCookieStorage = Session.defaultCookieStorage
        return config
    }
    
    @objc public static let urlSession: URLSession = {
        return URLSession(configuration: Session.defaultConfiguration)
    }()
    
    private let configuration: Configuration
    
    public required init(configuration: Configuration) {
        self.configuration = configuration
    }
    
    @objc public static let shared = Session(configuration: Configuration.current)
    
    public let defaultURLSession = Session.urlSession
    
    public let wifiOnlyURLSession: URLSession = {
        var config = Session.defaultConfiguration
        config.allowsCellularAccess = false
        return URLSession(configuration: config)
    }()
    
    internal let queue: OperationQueue = { // DEPRECATED: requestWithCSRF could be updated to not use an operation for cancellation and instread use the use the cancellation mechanism defined in the fetcher
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 16
        return queue
    }()
    
    public func hasValidCentralAuthCookies(for domain: String) -> Bool {
        guard let storage = defaultURLSession.configuration.httpCookieStorage else {
            return false
        }
        let cookies = storage.cookiesWithNamePrefix("centralauth_", for: domain)
        guard !cookies.isEmpty else {
            return false
        }
        let now = Date()
        for cookie in cookies {
            if let cookieExpirationDate = cookie.expiresDate, cookieExpirationDate < now {
                return false
            }
        }
        return true
    }

    private var cacheQueue = DispatchQueue(label: "session-cache-queue", qos: .default, attributes: [.concurrent], autoreleaseFrequency: .workItem, target: nil)
    private var _isAuthenticated: Bool?
    @objc public var isAuthenticated: Bool {
        var read: Bool?
        cacheQueue.sync {
            read = _isAuthenticated
        }
        if let auth = read {
            return auth
        }
        let hasValid = hasValidCentralAuthCookies(for: configuration.centralAuthCookieSourceDomain)
        cacheQueue.async(flags: .barrier) {
            self._isAuthenticated = hasValid
        }
        return hasValid
    }
    
    @objc(requestToGetURL:)
    public func request(toGET requestURL: URL?) -> URLRequest? {
        guard let requestURL = requestURL else {
            return nil
        }
        return request(with: requestURL, method: .get)
    }

    public func request(with requestURL: URL, method: Session.Request.Method = .get, bodyParameters: Any? = nil, bodyEncoding: Session.Request.Encoding = .json) -> URLRequest? {
        var request = URLRequest(url: requestURL)
        request.httpMethod = method.stringValue
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Accept")
        request.setValue("gzip", forHTTPHeaderField: "Accept-Encoding")
        request.setValue(WikipediaAppUtils.versionedUserAgent(), forHTTPHeaderField: "User-Agent")
        request.setValue(NSLocale.wmf_acceptLanguageHeaderForPreferredLanguages, forHTTPHeaderField: "Accept-Language")
        if let xWMFUUID = xWMFUUID {
            request.setValue(xWMFUUID, forHTTPHeaderField: "X-WMF-UUID")
        }
        guard let bodyParameters = bodyParameters else {
            return request
        }
        
        switch bodyEncoding {
        case .json:
            do {
                request.httpBody = try JSONSerialization.data(withJSONObject: bodyParameters, options: [])
                request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
            } catch let error {
                DDLogError("error serializing JSON: \(error)")
            }
        case .form:
            guard let bodyParametersDictionary = bodyParameters as? [String: Any] else {
                break
            }
            let queryString = URLComponents.percentEncodedQueryStringFrom(bodyParametersDictionary)
            request.httpBody = queryString.data(using: String.Encoding.utf8)
            request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        }
        return request
    }
    
    @discardableResult public func jsonDictionaryTask(with url: URL?, method: Session.Request.Method = .get, bodyParameters: Any? = nil, bodyEncoding: Session.Request.Encoding = .json, completionHandler: @escaping ([String: Any]?, HTTPURLResponse?, Error?) -> Swift.Void) -> URLSessionDataTask? {
        guard let url = url else {
            return nil
        }
        guard let request = request(with: url, method: method, bodyParameters: bodyParameters, bodyEncoding: bodyEncoding) else {
            return nil
        }
        return jsonDictionaryTask(with: request, completionHandler: completionHandler)
    }
    
    public func dataTask(with url: URL?, method: Session.Request.Method = .get, bodyParameters: Any? = nil, bodyEncoding: Session.Request.Encoding = .json, completionHandler: @escaping (Data?, URLResponse?, Error?) -> Swift.Void) -> URLSessionDataTask? {
        guard let url = url else {
            return nil
        }
        guard let request = request(with: url, method: method, bodyParameters: bodyParameters, bodyEncoding: bodyEncoding) else {
            return nil
        }
        return defaultURLSession.dataTask(with: request, completionHandler: completionHandler)
    }
    
    /**
     Shared response handling for common status codes. Currently logs the user out and removes local credentials if a 401 is received.
    */
    private func handleResponse(_ response: URLResponse?) {
        guard let response = response, let httpResponse = response as? HTTPURLResponse else {
            return
        }
        switch httpResponse.statusCode {
        case 401:
            WMFAuthenticationManager.sharedInstance.logout(initiatedBy: .server) {
                self.removeAllCookies()
            }
        default:
            break
        }
    }
    
    /**
     Creates a URLSessionTask that will handle the response by decoding it to the decodable type T. If the response isn't 200, or decoding to T fails, it'll attempt to decode the response to codable type E (typically an error response).
     - parameters:
         - url: The url for the request
         - method: The HTTP method for the request
         - bodyParameters: The body parameters for the request
         - bodyEncoding: The body encoding for the request body parameters
         - completionHandler: Called after the request completes
         - result: The result object decoded from JSON
         - errorResult: The error result object decoded from JSON
         - response: The URLResponse
         - error: Any network or parsing error
     */
    @discardableResult public func jsonDecodableTaskWithDecodableError<T: Decodable, E: Decodable>(with url: URL?, method: Session.Request.Method = .get, bodyParameters: Any? = nil, bodyEncoding: Session.Request.Encoding = .json, completionHandler: @escaping (_ result: T?, _ errorResult: E?, _ response: URLResponse?, _ error: Error?) -> Swift.Void) -> URLSessionDataTask? {
        guard let task = dataTask(with: url, method: method, bodyParameters: bodyParameters, bodyEncoding: bodyEncoding, completionHandler: { (data, response, error) in
            self.handleResponse(response)
            guard let data = data else {
                completionHandler(nil, nil, response, error)
                return
            }
            let decoder = JSONDecoder()
            let handleErrorResponse = {
                do {
                    let errorResult: E = try decoder.decode(E.self, from: data)
                    completionHandler(nil, errorResult, response, nil)
                } catch let errorResultParsingError {
                    completionHandler(nil, nil, response, errorResultParsingError)
                }
            }
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                handleErrorResponse()
                return
            }
//            #if DEBUG
//                let stringData = String(data: data, encoding: .utf8)
//                DDLogDebug("codable response:\n\(String(describing:response?.url)):\n\(String(describing: stringData))")
//            #endif
            do {
                let result: T = try decoder.decode(T.self, from: data)
                completionHandler(result, nil, response, error)
            } catch let resultParsingError {
                DDLogError("Error parsing codable response: \(resultParsingError)")
                handleErrorResponse()
            }
        }) else {
            completionHandler(nil, nil, nil, RequestError.invalidParameters)
            return nil
        }
        task.resume()
        return task
    }

    /**
     Creates a URLSessionTask that will handle the response by decoding it to the decodable type T.
     - parameters:
     - url: The url for the request
     - method: The HTTP method for the request
     - bodyParameters: The body parameters for the request
     - bodyEncoding: The body encoding for the request body parameters
     - completionHandler: Called after the request completes
     - result: The result object decoded from JSON
     - response: The URLResponse
     - error: Any network or parsing error
     */
    public func jsonDecodableTask<T: Decodable>(with url: URL?, method: Session.Request.Method = .get, bodyParameters: Any? = nil, bodyEncoding: Session.Request.Encoding = .json, completionHandler: @escaping (_ result: T?, _ response: URLResponse?,  _ error: Error?) -> Swift.Void) {
        guard let task = dataTask(with: url, method: method, bodyParameters: bodyParameters, bodyEncoding: bodyEncoding, completionHandler: { (data, response, error) in
            self.handleResponse(response)
            guard let data = data else {
                completionHandler(nil, response, error)
                return
            }
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                completionHandler(nil, response, nil)
                return
            }
            do {
                let decoder = JSONDecoder()
                let result: T = try decoder.decode(T.self, from: data)
                completionHandler(result, response, error)
            } catch let resultParsingError {
                DDLogError("Error parsing codable response: \(resultParsingError)")
                completionHandler(nil, response, resultParsingError)
            }
        }) else {
            completionHandler(nil, nil, RequestError.invalidParameters)
            return
        }
        task.resume()
    }
    
    @discardableResult private func jsonDictionaryTask(with request: URLRequest, completionHandler: @escaping ([String: Any]?, HTTPURLResponse?, Error?) -> Swift.Void) -> URLSessionDataTask {
        return defaultURLSession.dataTask(with: request, completionHandler: { (data, response, error) in
            self.handleResponse(response)
            guard let data = data else {
                completionHandler(nil, response as? HTTPURLResponse, error)
                return
            }
            do {
                guard !data.isEmpty, let responseObject = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
                    completionHandler(nil, response as? HTTPURLResponse, nil)
                    return
                }
                completionHandler(responseObject, response as? HTTPURLResponse, nil)
            } catch let error {
                DDLogError("Error parsing JSON: \(error)")
                completionHandler(nil, response as? HTTPURLResponse, error)
            }
        })
    }

    @objc(getJSONDictionaryFromURL:ignoreCache:completionHandler:)
    @discardableResult public func getJSONDictionary(from url: URL?, ignoreCache: Bool = false, completionHandler: @escaping ([String: Any]?, HTTPURLResponse?, Error?) -> Swift.Void) -> URLSessionTask? {
        guard let url = url else {
            completionHandler(nil, nil, RequestError.invalidParameters)
            return nil
        }
        guard var request = self.request(with: url, method: .get) else {
            completionHandler(nil, nil, RequestError.invalidParameters)
            return nil
        }
        if ignoreCache {
            request.cachePolicy = .reloadIgnoringLocalCacheData
        }
        let task = jsonDictionaryTask(with: request, completionHandler: completionHandler)
        task.resume()
        return task
    }
    
    @objc(postFormEncodedBodyParametersToURL:bodyParameters:completionHandler:)
    @discardableResult public func postFormEncodedBodyParametersToURL(to url: URL?, bodyParameters: [String: String]? = nil, completionHandler: @escaping ([String: Any]?, HTTPURLResponse?, Error?) -> Swift.Void) -> URLSessionTask? {
        guard let url = url else {
            completionHandler(nil, nil, RequestError.invalidParameters)
            return nil
        }
        guard let request = self.request(with: url, method: .post, bodyParameters: bodyParameters, bodyEncoding: .form) else {
            completionHandler(nil, nil, RequestError.invalidParameters)
            return nil
        }
        let task = jsonDictionaryTask(with: request, completionHandler: completionHandler)
        task.resume()
        return task
    }
    
    @discardableResult public func apiTask(with articleURL: URL, path: [String], completionHandler: @escaping ([String: Any]?, URLResponse?, Error?) -> Swift.Void) -> URLSessionDataTask? {
        guard let siteURL = articleURL.wmf_site, let title = articleURL.wmf_titleWithUnderscores else {
            // don't call the completion as this is just a method to get the task
            return nil
        }
        let builder = configuration.mobileAppsServicesAPIURLComponentsBuilderForHost(siteURL.host)
        let encodedTitle = title.addingPercentEncoding(withAllowedCharacters: CharacterSet.wmf_articleTitlePathComponentAllowed) ?? title
        let components = builder.components(byAppending: path + [encodedTitle])
        guard let summaryURL = components.url else {
            // don't call the completion as this is just a method to get the task
            return nil
        }
        
        guard var request = self.request(with: summaryURL) else {
            return nil
        }
        //The accept profile is case sensitive https://gerrit.wikimedia.org/r/#/c/356429/
        request.setValue("application/json; charset=utf-8; profile=\"https://www.mediawiki.org/wiki/Specs/Summary/1.1.2\"", forHTTPHeaderField: "Accept")
        return jsonDictionaryTask(with: request, completionHandler: completionHandler)
    }
    
    @objc(fetchAPIPath:withArticleURL:priority:completionHandler:)
    public func fetchAPI(path: [String], with articleURL: URL, priority: Float = URLSessionTask.defaultPriority, completionHandler: @escaping ([String: Any]?, URLResponse?, Error?) -> Swift.Void) {
        guard let task = apiTask(with: articleURL, path: path, completionHandler: completionHandler) else {
            completionHandler(nil, nil, RequestError.invalidParameters)
            return
        }
        task.priority = priority
        task.resume()
    }
    
    @objc(fetchMediaForArticleURL:priority:completionHandler:)
    public func fetchMedia(for articleURL: URL, priority: Float = URLSessionTask.defaultPriority, completionHandler: @escaping ([String: Any]?, URLResponse?, Error?) -> Swift.Void) {
        return fetchAPI(path: ["page", "media"], with: articleURL, completionHandler: completionHandler)
    }
    
    @objc(fetchSummaryForArticleURL:priority:completionHandler:)
    public func fetchSummary(for articleURL: URL, priority: Float = URLSessionTask.defaultPriority, completionHandler: @escaping ([String: Any]?, URLResponse?, Error?) -> Swift.Void) {
        return fetchAPI(path: ["page", "summary"], with: articleURL, completionHandler: completionHandler)
    }
    
    public func fetchArticleSummaryResponsesForArticles(withURLs articleURLs: [URL], priority: Float = URLSessionTask.defaultPriority, completion: @escaping ([String: [String: Any]]) -> Void) {
        articleURLs.asyncMapToDictionary(block: { (articleURL, asyncMapCompletion) in
            fetchSummary(for: articleURL, priority: priority, completionHandler: { (responseObject, response, error) in
                asyncMapCompletion(articleURL.wmf_articleDatabaseKey, responseObject)
            })
        }, completion: completion)
    }
    
}

public enum RequestError: LocalizedError {
    case unknown
    case invalidParameters
    case unexpectedResponse
    case noNewData
    public var errorDescription: String? {
        switch self {
        case .unexpectedResponse:
            return WMFLocalizedString("fetcher-error-unexpected-response", value: "The app received an unexpected response from the server. Please try again later.", comment: "Error shown to the user for unexpected server responses.")
        default:
            return WMFLocalizedString("fetcher-error-generic", value: "Something went wrong. Please try again later.", comment: "Error shown to the user for generic errors with no clear recovery steps for the user.")
        }
    }
}
