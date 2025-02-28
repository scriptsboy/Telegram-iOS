import Foundation
import Postbox
import SwiftSignalKit

public struct ExperimentalUISettings: Equatable, PreferencesEntry {
    public var keepChatNavigationStack: Bool
    public var skipReadHistory: Bool
    public var crashOnLongQueries: Bool
    public var chatListPhotos: Bool
    public var brr: Bool
    
    public static var defaultSettings: ExperimentalUISettings {
        return ExperimentalUISettings(keepChatNavigationStack: false, skipReadHistory: false, crashOnLongQueries: false, chatListPhotos: false, brr: false)
    }
    
    public init(keepChatNavigationStack: Bool, skipReadHistory: Bool, crashOnLongQueries: Bool, chatListPhotos: Bool, brr: Bool) {
        self.keepChatNavigationStack = keepChatNavigationStack
        self.skipReadHistory = skipReadHistory
        self.crashOnLongQueries = crashOnLongQueries
        self.chatListPhotos = chatListPhotos
        self.brr = brr
    }
    
    public init(decoder: PostboxDecoder) {
        self.keepChatNavigationStack = decoder.decodeInt32ForKey("keepChatNavigationStack", orElse: 0) != 0
        self.skipReadHistory = decoder.decodeInt32ForKey("skipReadHistory", orElse: 0) != 0
        self.crashOnLongQueries = decoder.decodeInt32ForKey("crashOnLongQueries", orElse: 0) != 0
        self.chatListPhotos = decoder.decodeInt32ForKey("chatListPhotos", orElse: 0) != 0
        self.brr = decoder.decodeInt32ForKey("nice:brr", orElse: 0) != 0
    }
    
    public func encode(_ encoder: PostboxEncoder) {
        encoder.encodeInt32(self.keepChatNavigationStack ? 1 : 0, forKey: "keepChatNavigationStack")
        encoder.encodeInt32(self.skipReadHistory ? 1 : 0, forKey: "skipReadHistory")
        encoder.encodeInt32(self.crashOnLongQueries ? 1 : 0, forKey: "crashOnLongQueries")
        encoder.encodeInt32(self.chatListPhotos ? 1 : 0, forKey: "chatListPhotos")
        encoder.encodeInt32(self.brr ? 1 : 0, forKey: "nice:brr")
    }
    
    public func isEqual(to: PreferencesEntry) -> Bool {
        if let to = to as? ExperimentalUISettings {
            return self == to
        } else {
            return false
        }
    }
}

public func updateExperimentalUISettingsInteractively(accountManager: AccountManager, _ f: @escaping (ExperimentalUISettings) -> ExperimentalUISettings) -> Signal<Void, NoError> {
    return accountManager.transaction { transaction -> Void in
        transaction.updateSharedData(ApplicationSpecificSharedDataKeys.experimentalUISettings, { entry in
            let currentSettings: ExperimentalUISettings
            if let entry = entry as? ExperimentalUISettings {
                currentSettings = entry
            } else {
                currentSettings = .defaultSettings
            }
            return f(currentSettings)
        })
    }
}
