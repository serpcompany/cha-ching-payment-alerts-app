import Foundation
import Testing
@testable import Cha_Ching

struct APIClientURLTests {
    @Test func dashboardPeriodsAreRealQueryItemsRatherThanEncodedPathText() throws {
        let baseURL = try #require(URL(string: "https://api.example.test"))
        for period in DashboardPeriod.allCases {
            let url = try APIClient.requestURL(
                baseURL: baseURL,
                path: "/v1/dashboard",
                queryItems: [
                    URLQueryItem(name: "period", value: period.rawValue),
                    URLQueryItem(name: "dayOffset", value: "2")
                ]
            )
            let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))

            #expect(components.path == "/v1/dashboard")
            #expect(components.queryItems == [
                URLQueryItem(name: "period", value: period.rawValue),
                URLQueryItem(name: "dayOffset", value: "2")
            ])
            #expect(!components.percentEncodedPath.contains("%3F"))
        }
    }

    @Test func paymentIDsBecomeExactlyOneURLPathSegment() throws {
        let baseURL = try #require(URL(string: "https://api.example.test"))
        for id in ["stripe:ch_3Pabc123", "custom:order_42"] {
            let url = APIClient.requestURL(baseURL: baseURL, pathComponents: ["v1", "sales", id])
            let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))

            #expect(url.pathComponents.last == id)
            #expect(components.path == "/v1/sales/\(id)")
            #expect(!url.absoluteString.contains("%253A"))
            #expect(components.query == nil)
        }
    }
}
