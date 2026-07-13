import Foundation

enum AppNetworkSession {
  static let requestTimeout: TimeInterval = 30
  static let resourceTimeout: TimeInterval = 60

  static func makeConfiguration() -> URLSessionConfiguration {
    let configuration = URLSessionConfiguration.default
    configuration.timeoutIntervalForRequest = requestTimeout
    configuration.timeoutIntervalForResource = resourceTimeout
    configuration.waitsForConnectivity = false
    return configuration
  }

  static func makeSession() -> URLSession {
    URLSession(configuration: makeConfiguration())
  }
}
