import Combine
import Foundation

struct ExchangeRateSnapshot: Codable, Equatable {
    let rates: [String: Decimal]
    let effectiveDate: String
    let fetchedAt: Date

    func convertedAmount(
        for totals: [CurrencyTotal],
        to targetCurrencyCode: String
    ) -> Double? {
        let targetCode = targetCurrencyCode.uppercased()
        guard let targetRate = rates[targetCode], targetRate > 0 else { return nil }

        var convertedTotal = Decimal.zero
        for total in totals {
            let sourceCode = total.currencyCode.uppercased()
            guard let sourceRate = rates[sourceCode], sourceRate > 0 else { return nil }
            convertedTotal += Decimal(total.amount) * targetRate / sourceRate
        }

        return NSDecimalNumber(decimal: convertedTotal).doubleValue
    }
}

@MainActor
final class ExchangeRateStore: ObservableObject {
    @Published private(set) var snapshot: ExchangeRateSnapshot?
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastRefreshFailed = false

    private static let cacheKey = "exchangeRateSnapshot.v1"
    private static let refreshInterval: TimeInterval = 12 * 60 * 60
    private static let sourceURL = URL(
        string: "https://www.ecb.europa.eu/stats/eurofxref/eurofxref-daily.xml"
    )!

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.cacheKey) {
            snapshot = try? JSONDecoder().decode(ExchangeRateSnapshot.self, from: data)
        }
    }

    var statusTitle: String {
        if isRefreshing, snapshot == nil {
            return "正在更新"
        }
        if let snapshot {
            return lastRefreshFailed
                ? "缓存 · \(snapshot.effectiveDate)"
                : "\(snapshot.effectiveDate)"
        }
        return lastRefreshFailed ? "暂不可用" : "尚未更新"
    }

    var dashboardStatusText: String? {
        guard let snapshot else {
            return isRefreshing ? "正在获取欧洲央行参考汇率…" : nil
        }
        return lastRefreshFailed
            ? "使用本机缓存汇率 · \(snapshot.effectiveDate)"
            : "欧洲央行参考汇率 · \(snapshot.effectiveDate)"
    }

    func convertedAmount(
        for totals: [CurrencyTotal],
        to targetCurrencyCode: String
    ) -> Double? {
        guard !totals.isEmpty else { return 0 }

        let targetCode = targetCurrencyCode.uppercased()
        if totals.allSatisfy({ $0.currencyCode.uppercased() == targetCode }) {
            return totals.reduce(0) { $0 + $1.amount }
        }
        return snapshot?.convertedAmount(for: totals, to: targetCode)
    }

    func refreshIfNeeded(force: Bool = false) async {
        guard !isRefreshing else { return }
        if !force,
           let snapshot,
           Date.now.timeIntervalSince(snapshot.fetchedAt) < Self.refreshInterval {
            return
        }

        isRefreshing = true
        defer { isRefreshing = false }

        do {
            var request = URLRequest(url: Self.sourceURL)
            request.cachePolicy = .reloadRevalidatingCacheData
            request.timeoutInterval = 15

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                throw ExchangeRateError.invalidResponse
            }

            let parsed = try ECBReferenceRateParser.parse(data: data)
            let updatedSnapshot = ExchangeRateSnapshot(
                rates: parsed.rates,
                effectiveDate: parsed.effectiveDate,
                fetchedAt: .now
            )
            snapshot = updatedSnapshot
            lastRefreshFailed = false

            if let encoded = try? JSONEncoder().encode(updatedSnapshot) {
                defaults.set(encoded, forKey: Self.cacheKey)
            }
        } catch {
            lastRefreshFailed = true
        }
    }
}

private enum ExchangeRateError: Error {
    case invalidResponse
    case invalidPayload
}

private final class ECBReferenceRateParser: NSObject, XMLParserDelegate {
    private(set) var rates: [String: Decimal] = ["EUR": 1]
    private(set) var effectiveDate: String?

    static func parse(data: Data) throws -> (rates: [String: Decimal], effectiveDate: String) {
        let delegate = ECBReferenceRateParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate

        guard parser.parse(),
              let effectiveDate = delegate.effectiveDate,
              delegate.rates.count > 1 else {
            throw ExchangeRateError.invalidPayload
        }
        return (delegate.rates, effectiveDate)
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        if let time = attributeDict["time"] {
            effectiveDate = time
        }

        guard let currency = attributeDict["currency"]?.uppercased(),
              let rateText = attributeDict["rate"],
              let rate = Decimal(
                string: rateText,
                locale: Locale(identifier: "en_US_POSIX")
              ),
              rate > 0 else {
            return
        }
        rates[currency] = rate
    }
}
