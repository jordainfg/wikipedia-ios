import Foundation

public struct WMFDonateConfig: Codable {
    let version: Int
    public let currencyMinimumDonation: [String: Decimal]
    public let currencyMaximumDonation: [String: Decimal]
    public let currencyAmountPresets: [String: [Decimal]]
    public let currencyTransactionFees: [String: Decimal]
    public let countryCodeEmailOptInRequired: [String]
    var cachedDate: Date?
    
    public func transactionFee(for currencyCode: String) -> Decimal? {
        return currencyTransactionFees[currencyCode] ?? currencyTransactionFees["default"]
    }

    public func getMaxAmount(for currencyCode: String) -> Decimal {
        var max = currencyMaximumDonation[currencyCode] ?? Decimal()

        if max.isZero {
            if let defaultMin = currencyMinimumDonation["USD"], let defaultMax = currencyMaximumDonation["USD"], let currencyMax = currencyMinimumDonation[currencyCode] {
                max = currencyMax / defaultMin * defaultMax
            }
        }
        return max
    }
}
