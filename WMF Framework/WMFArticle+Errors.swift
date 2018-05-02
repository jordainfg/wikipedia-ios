import Foundation


public enum ArticleError: Int32, Error {
    case none = 0
    case saveToDiskFailed = 1
}

extension ArticleError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .none:
            return nil
        case .saveToDiskFailed:
            return WMFLocalizedString("reading-lists-article-save-to-disk-failed", value: "Device limited exceeded, unable to sync article", comment: "Text of the alert label informing the user that article couldn't be saved due to insufficient storage available")
        }
    }
    public var failureReason: String? {
        switch self {
        case .none:
            return nil
        case .saveToDiskFailed:
            return nil
        }
    }
    public var recoverySuggestion: String? {
        switch self {
        case .none:
            return nil
        case .saveToDiskFailed:
            return WMFLocalizedString("reading-lists-article-save-to-disk-recovery-suggestion", value: "Clear some space on your device and try again", comment: "Recovery suggestion to clear space on the user's device to allow articles to download")
        }
    }
}


extension WMFArticle {
    @objc public func updatePropertiesForError(_ nsError: NSError?) {
        guard let nsError = nsError else {
            error = .none
            return
        }
        if nsError.domain == NSCocoaErrorDomain && nsError.code == NSFileWriteOutOfSpaceError {
            error = .saveToDiskFailed
        }
    }
    
    public var error: ArticleError {
        get {
            return ArticleError(rawValue: errorCodeNumber?.int32Value ?? 0) ?? .none
        }
        set {
            guard newValue != .none else {
                errorCodeNumber = nil
                return
            }
            errorCodeNumber = NSNumber(value: newValue.rawValue)
        }
    }
}
