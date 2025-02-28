import Foundation
#if os(macOS)
    import PostboxMac
    import SwiftSignalKitMac
    import TelegramApiMac
#else
    import Postbox
    import TelegramApi
    import SwiftSignalKit
#endif

public func currentlySuggestedLocalization(network: Network, extractKeys: [String]) -> Signal<SuggestedLocalizationInfo?, NoError> {
    return network.request(Api.functions.help.getConfig())
        |> retryRequest
        |> mapToSignal { result -> Signal<SuggestedLocalizationInfo?, NoError> in
            switch result {
                case let .config(config):
                    if let suggestedLangCode = config.suggestedLangCode {
                        return suggestedLocalizationInfo(network: network, languageCode: suggestedLangCode, extractKeys: extractKeys) |> map(Optional.init)
                    } else {
                        return .single(nil)
                    }
            }
        }
}

public func suggestedLocalizationInfo(network: Network, languageCode: String, extractKeys: [String]) -> Signal<SuggestedLocalizationInfo, NoError> {
    return combineLatest(network.request(Api.functions.langpack.getLanguages(langPack: "")), network.request(Api.functions.langpack.getStrings(langPack: "", langCode: languageCode, keys: extractKeys)))
        |> retryRequest
        |> map { languages, strings -> SuggestedLocalizationInfo in
            var entries: [LocalizationEntry] = []
            for string in strings {
                switch string {
                    case let .langPackString(key, value):
                        entries.append(.string(key: key, value: value))
                    case let .langPackStringPluralized(_, key, zeroValue, oneValue, twoValue, fewValue, manyValue, otherValue):
                        entries.append(.pluralizedString(key: key, zero: zeroValue, one: oneValue, two: twoValue, few: fewValue, many: manyValue, other: otherValue))
                    case let .langPackStringDeleted(key):
                        entries.append(.string(key: key, value: ""))
                }
            }
            var infos: [LocalizationInfo] = languages.map(LocalizationInfo.init(apiLanguage:))
            infos += niceLocalizations
            return SuggestedLocalizationInfo(languageCode: languageCode, extractedEntries: entries, availableLocalizations: infos)
        }
}

final class CachedLocalizationInfos: PostboxCoding {
    let list: [LocalizationInfo]
    
    init(list: [LocalizationInfo]) {
        self.list = list
    }
    
    init(decoder: PostboxDecoder) {
        self.list = decoder.decodeObjectArrayWithDecoderForKey("l")
    }
    
    func encode(_ encoder: PostboxEncoder) {
        encoder.encodeObjectArray(self.list, forKey: "l")
    }
}

public func availableLocalizations(postbox: Postbox, network: Network, allowCached: Bool) -> Signal<[LocalizationInfo], NoError> {
    let cached: Signal<[LocalizationInfo], NoError>
    if allowCached {
        cached = postbox.transaction { transaction -> Signal<[LocalizationInfo], NoError> in
            if let entry = transaction.retrieveItemCacheEntry(id: ItemCacheEntryId(collectionId: Namespaces.CachedItemCollection.cachedAvailableLocalizations, key: ValueBoxKey(length: 0))) as? CachedLocalizationInfos {
                return .single(entry.list)
            }
            return .complete()
        } |> switchToLatest
    } else {
        cached = .complete()
    }
    let remote = network.request(Api.functions.langpack.getLanguages(langPack: ""))
    |> retryRequest
    |> mapToSignal { languages -> Signal<[LocalizationInfo], NoError> in
        let infos: [LocalizationInfo] = languages.map(LocalizationInfo.init(apiLanguage:))
        return postbox.transaction { transaction -> [LocalizationInfo] in
            transaction.putItemCacheEntry(id: ItemCacheEntryId(collectionId: Namespaces.CachedItemCollection.cachedAvailableLocalizations, key: ValueBoxKey(length: 0)), entry: CachedLocalizationInfos(list: infos), collectionSpec: ItemCacheCollectionSpec(lowWaterItemCount: 1, highWaterItemCount: 1))
            return infos
        }
    }
    
    return cached |> then(remote)
}

public enum DownloadLocalizationError {
    case generic
}

public func downloadLocalization(network: Network, languageCode: String) -> Signal<Localization, DownloadLocalizationError> {
    return network.request(Api.functions.langpack.getLangPack(langPack: "", langCode: languageCode))
    |> mapError { _ -> DownloadLocalizationError in
        return .generic
    }
    |> map { result -> Localization in
        let version: Int32
        var entries: [LocalizationEntry] = []
        switch result {
            case let .langPackDifference(_, _, versionValue, strings):
                version = versionValue
                for string in strings {
                    switch string {
                        case let .langPackString(key, value):
                            entries.append(.string(key: key, value: value))
                        case let .langPackStringPluralized(_, key, zeroValue, oneValue, twoValue, fewValue, manyValue, otherValue):
                            entries.append(.pluralizedString(key: key, zero: zeroValue, one: oneValue, two: twoValue, few: fewValue, many: manyValue, other: otherValue))
                        case let .langPackStringDeleted(key):
                            entries.append(.string(key: key, value: ""))
                    }
                }
        }
        
        return Localization(version: version, entries: entries)
    }
}

public enum DownloadAndApplyLocalizationError {
    case generic
}

public func downloadAndApplyLocalization(accountManager: AccountManager, postbox: Postbox, network: Network, languageCode: String) -> Signal<Void, DownloadAndApplyLocalizationError> {
    return requestLocalizationPreview(network: network, identifier: languageCode)
    |> mapError { _ -> DownloadAndApplyLocalizationError in
        return .generic
    }
    |> mapToSignal { preview -> Signal<Void, DownloadAndApplyLocalizationError> in
        var primaryAndSecondaryLocalizations: [Signal<Localization, DownloadLocalizationError>] = []
        primaryAndSecondaryLocalizations.append(downloadLocalization(network: network, languageCode: preview.languageCode))
        if let secondaryCode = preview.baseLanguageCode {
            primaryAndSecondaryLocalizations.append(downloadLocalization(network: network, languageCode: secondaryCode))
        }
        return combineLatest(primaryAndSecondaryLocalizations)
        |> mapError { _ -> DownloadAndApplyLocalizationError in
            return .generic
        }
        |> mapToSignal { components -> Signal<Void, DownloadAndApplyLocalizationError> in
            guard let primaryLocalization = components.first else {
                return .fail(.generic)
            }
            var secondaryComponent: LocalizationComponent?
            if let secondaryCode = preview.baseLanguageCode, components.count > 1 {
                secondaryComponent = LocalizationComponent(languageCode: secondaryCode, localizedName: "", localization: components[1], customPluralizationCode: nil)
            }
            return accountManager.transaction { transaction -> Signal<Void, DownloadAndApplyLocalizationError> in
                transaction.updateSharedData(SharedDataKeys.localizationSettings, { _ in
                    return LocalizationSettings(primaryComponent: LocalizationComponent(languageCode: preview.languageCode, localizedName: preview.localizedTitle, localization: primaryLocalization, customPluralizationCode: preview.customPluralizationCode), secondaryComponent: secondaryComponent)
                })
                
                return postbox.transaction { transaction -> Signal<Void, DownloadAndApplyLocalizationError> in
                    updateLocalizationListStateInteractively(transaction: transaction, { state in
                        var state = state
                        for i in 0 ..< state.availableSavedLocalizations.count {
                            if state.availableSavedLocalizations[i].languageCode == preview.languageCode {
                                state.availableSavedLocalizations.remove(at: i)
                                break
                            }
                        }
                        state.availableSavedLocalizations.insert(preview, at: 0)
                        return state
                    })
                    
                    network.context.updateApiEnvironment { current in
                        return current?.withUpdatedLangPackCode(preview.languageCode)
                    }
                    
                    return network.request(Api.functions.help.test())
                    |> `catch` { _ -> Signal<Api.Bool, NoError> in
                        return .complete()
                    }
                    |> mapToSignal { _ -> Signal<Void, NoError> in
                        return .complete()
                    }
                    |> introduceError(DownloadAndApplyLocalizationError.self)
                }
                |> introduceError(DownloadAndApplyLocalizationError.self)
                |> switchToLatest
            }
            |> introduceError(DownloadAndApplyLocalizationError.self)
            |> switchToLatest
        }
    }
}
