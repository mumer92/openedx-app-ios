//
//  Config.swift
//  Core
//
//  Created by Muhammad Umer on 11/11/2023.
//

import Foundation

public protocol ConfigProtocol {
    var baseURL: URL { get }
    var oAuthClientId: String { get }
    var tokenType: TokenType { get }
    var feedbackEmail: String { get }
    var appStoreLink: String { get }
    var agreement: AgreementConfig { get }
    var firebase: FirebaseConfig { get }
    var features: FeaturesConfig { get }
}

public enum TokenType: String {
    case jwt = "JWT"
    case bearer = "BEARER"
}

private enum ConfigKeys: String {
    case baseURL = "API_HOST_URL"
    case oAuthClientID = "OAUTH_CLIENT_ID"
    case tokenType = "TOKEN_TYPE"
    case feedbackEmailAddress = "FEEDBACK_EMAIL_ADDRESS"
    case environmentDisplayName = "ENVIRONMENT_DISPLAY_NAME"
    case platformName = "PLATFORM_NAME"
    case organizationCode = "ORGANIZATION_CODE"
    case appstoreID = "APP_STORE_ID"
}

public class Config {
    public static let shared: Config = {
        let config = Config()
        config.loadConfigPlist()
        return config
    }()
    
    internal var properties: [String: Any] = [:]
    
    internal init(properties: [String: Any] = [:]) {
        self.properties = properties
    }
    
    internal convenience init() {
        self.init(properties: [:])
        loadConfigPlist()
    }
    
    private func loadConfigPlist() {
        guard let path = Bundle.main.path(forResource: "config", ofType: "plist"),
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let dict = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else { return }
        
        properties = dict
    }
    
    internal subscript(key: String) -> Any? {
        return properties[key]
    }
    
    func dict(for key: String) -> [String: Any]? {
        return properties[key] as? [String: Any]
    }
    
    func value<T>(for key: String) -> T? {
        return properties[key] as? T
    }
    
    func value(for key: String) -> Any? {
        return properties[key]
    }
    
    func value(for key: String, dict: [String: Any]) -> String? {
        return dict[key] as? String ?? nil
    }
    
    func string(for key: String) -> String? {
        return value(for: key) as? String ?? nil
    }
    
    func string(for key: String, dict: [String: Any]) -> String? {
        return value(for: key, dict: dict)
    }
    
    func bool(for key: String) -> Bool {
        return value(for: key) as? Bool ?? false
    }
}

extension Config: ConfigProtocol {
    public var baseURL: URL {
        return URL(string: string(for: ConfigKeys.baseURL.rawValue)!)!
    }
    
    public var oAuthClientId: String {
        return string(for: ConfigKeys.oAuthClientID.rawValue) ?? ""
    }
    
    public var tokenType: TokenType {
        if let tokenTypeValue = string(for: ConfigKeys.tokenType.rawValue),
           let tokenType = TokenType(rawValue: tokenTypeValue) {
            return tokenType
        } else {
            return .jwt
        }
    }
    
    public var feedbackEmail: String {
        return string(for: ConfigKeys.feedbackEmailAddress.rawValue) ?? ""
    }
    
    private var appStoreId: String {
        return string(for: ConfigKeys.appstoreID.rawValue) ?? "0000000000"
    }
    
    public var appStoreLink: String {
        "itms-apps://itunes.apple.com/app/id\(appStoreId)?mt=8"
    }
}

// Mark - For testing and SwiftUI preview
#if DEBUG
public class ConfigMock: Config {
    private let config: [String: Any] = [
        "API_HOST_URL": "https://www.example.com",
        "OAUTH_CLIENT_ID": "oauth_client_id",
        "FEEDBACK_EMAIL_ADDRESS": "example@mail.com",
        "TOKEN_TYPE": "JWT",
        "WHATS_NEW_ENABLED": false,
        "AGREEMENT_URLS": [
            "PRIVACY_POLICY_URL": "https://www.example.com/privacy",
            "TOS_URL": "https://www.example.com/tos"
        ]
    ]
    
    public init() {
        super.init(properties: config)
    }
}
#endif