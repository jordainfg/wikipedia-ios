import Foundation

enum NotificationsCenterAction: Equatable {
    case markAsReadOrUnread(NotificationsCenterActionData)
    case custom(NotificationsCenterActionData)
    case notificationSubscriptionSettings(NotificationsCenterActionData)

    var actionData: NotificationsCenterActionData? {
        switch self {
        case .notificationSubscriptionSettings(let data), .markAsReadOrUnread(let data), .custom(let data):
            return data
        }
    }
}

struct NotificationsCenterActionData: Equatable {
    let text: String
    let url: URL?
    let iconType: NotificationsCenterIconType?
    let destinationText: String?
}
