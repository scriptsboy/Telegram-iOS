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

import TelegramCorePrivateModule

enum PendingMessageUploadedContent {
    case text(String)
    case media(Api.InputMedia, String)
    case forward(ForwardSourceInfoAttribute)
    case chatContextResult(OutgoingChatContextResultMessageAttribute)
    case secretMedia(Api.InputEncryptedFile, Int32, SecretFileEncryptionKey)
    case messageScreenshot
}

enum PendingMessageReuploadInfo {
    case reuploadFile(FileMediaReference)
}

struct PendingMessageUploadedContentAndReuploadInfo {
    let content: PendingMessageUploadedContent
    let reuploadInfo: PendingMessageReuploadInfo?
}

enum PendingMessageUploadedContentResult {
    case progress(Float)
    case content(PendingMessageUploadedContentAndReuploadInfo)
}

enum PendingMessageUploadedContentType {
    case none
    case text
    case media
}

enum PendingMessageUploadError {
    case generic
}

func messageContentToUpload(network: Network, postbox: Postbox, auxiliaryMethods: AccountAuxiliaryMethods, transformOutgoingMessageMedia: TransformOutgoingMessageMedia?, messageMediaPreuploadManager: MessageMediaPreuploadManager, revalidationContext: MediaReferenceRevalidationContext, forceReupload: Bool, isGrouped: Bool, message: Message) -> (Signal<PendingMessageUploadedContentResult, PendingMessageUploadError>, PendingMessageUploadedContentType) {
    return messageContentToUpload(network: network, postbox: postbox, auxiliaryMethods: auxiliaryMethods, transformOutgoingMessageMedia: transformOutgoingMessageMedia, messageMediaPreuploadManager: messageMediaPreuploadManager, revalidationContext: revalidationContext, forceReupload: forceReupload, isGrouped: isGrouped, peerId: message.id.peerId, messageId: message.id, attributes: message.attributes, text: message.text, media: message.media)
}

func messageContentToUpload(network: Network, postbox: Postbox, auxiliaryMethods: AccountAuxiliaryMethods, transformOutgoingMessageMedia: TransformOutgoingMessageMedia?, messageMediaPreuploadManager: MessageMediaPreuploadManager, revalidationContext: MediaReferenceRevalidationContext, forceReupload: Bool, isGrouped: Bool, peerId: PeerId, messageId: MessageId?, attributes: [MessageAttribute], text: String, media: [Media]) -> (Signal<PendingMessageUploadedContentResult, PendingMessageUploadError>, PendingMessageUploadedContentType) {
    var contextResult: OutgoingChatContextResultMessageAttribute?
    var autoremoveAttribute: AutoremoveTimeoutMessageAttribute?
    for attribute in attributes {
        if let attribute = attribute as? OutgoingChatContextResultMessageAttribute {
            if peerId.namespace != Namespaces.Peer.SecretChat {
                contextResult = attribute
            }
        } else if let attribute = attribute as? AutoremoveTimeoutMessageAttribute {
            autoremoveAttribute = attribute
        }
    }
    
    var forwardInfo: ForwardSourceInfoAttribute?
    for attribute in attributes {
        if let attribute = attribute as? ForwardSourceInfoAttribute {
            if peerId.namespace != Namespaces.Peer.SecretChat {
                forwardInfo = attribute
            }
        }
    }
    
    if let media = media.first as? TelegramMediaAction, media.action == .historyScreenshot {
        return (.single(.content(PendingMessageUploadedContentAndReuploadInfo(content: .messageScreenshot, reuploadInfo: nil))), .none)
    } else if let forwardInfo = forwardInfo {
        return (.single(.content(PendingMessageUploadedContentAndReuploadInfo(content: .forward(forwardInfo), reuploadInfo: nil))), .text)
    } else if let contextResult = contextResult {
        return (.single(.content(PendingMessageUploadedContentAndReuploadInfo(content: .chatContextResult(contextResult), reuploadInfo: nil))), .text)
    } else if let media = media.first, let mediaResult = mediaContentToUpload(network: network, postbox: postbox, auxiliaryMethods: auxiliaryMethods, transformOutgoingMessageMedia: transformOutgoingMessageMedia, messageMediaPreuploadManager: messageMediaPreuploadManager, revalidationContext: revalidationContext, forceReupload: forceReupload, isGrouped: isGrouped, peerId: peerId, media: media, text: text, autoremoveAttribute: autoremoveAttribute, messageId: messageId, attributes: attributes) {
        return (mediaResult, .media)
    } else {
        return (.single(.content(PendingMessageUploadedContentAndReuploadInfo(content: .text(text), reuploadInfo: nil))), .text)
    }
}

func mediaContentToUpload(network: Network, postbox: Postbox, auxiliaryMethods: AccountAuxiliaryMethods, transformOutgoingMessageMedia: TransformOutgoingMessageMedia?, messageMediaPreuploadManager: MessageMediaPreuploadManager, revalidationContext: MediaReferenceRevalidationContext, forceReupload: Bool, isGrouped: Bool, peerId: PeerId, media: Media, text: String, autoremoveAttribute: AutoremoveTimeoutMessageAttribute?, messageId: MessageId?, attributes: [MessageAttribute]) -> Signal<PendingMessageUploadedContentResult, PendingMessageUploadError>? {
    if let image = media as? TelegramMediaImage, let largest = largestImageRepresentation(image.representations) {
        if peerId.namespace == Namespaces.Peer.SecretChat, let resource = largest.resource as? SecretFileMediaResource {
            return .single(.content(PendingMessageUploadedContentAndReuploadInfo(content: .secretMedia(.inputEncryptedFile(id: resource.fileId, accessHash: resource.accessHash), resource.decryptedSize, resource.key), reuploadInfo: nil)))
        }
        if peerId.namespace != Namespaces.Peer.SecretChat, let reference = image.reference, case let .cloud(id, accessHash, maybeFileReference) = reference, let fileReference = maybeFileReference {
            return .single(.content(PendingMessageUploadedContentAndReuploadInfo(content: .media(Api.InputMedia.inputMediaPhoto(flags: 0, id: Api.InputPhoto.inputPhoto(id: id, accessHash: accessHash, fileReference: Buffer(data: fileReference)), ttlSeconds: nil), text), reuploadInfo: nil)))
        } else {
            return uploadedMediaImageContent(network: network, postbox: postbox, transformOutgoingMessageMedia: transformOutgoingMessageMedia, forceReupload: forceReupload, isGrouped: isGrouped, peerId: peerId, image: image, messageId: messageId, text: text, attributes: attributes, autoremoveAttribute: autoremoveAttribute)
        }
    } else if let file = media as? TelegramMediaFile {
        if let resource = file.resource as? CloudDocumentMediaResource {
            if peerId.namespace == Namespaces.Peer.SecretChat {
                for attribute in file.attributes {
                    if case let .Sticker(sticker) = attribute {
                        if let _ = sticker.packReference {
                            return .single(.content(PendingMessageUploadedContentAndReuploadInfo(content: PendingMessageUploadedContent.text(text), reuploadInfo: nil)))
                        }
                    }
                }
                return uploadedMediaFileContent(network: network, postbox: postbox, auxiliaryMethods: auxiliaryMethods, transformOutgoingMessageMedia: transformOutgoingMessageMedia, messageMediaPreuploadManager: messageMediaPreuploadManager, forceReupload: true, isGrouped: isGrouped, peerId: peerId, messageId: messageId, text: text, attributes: attributes, file: file)
            } else {
                if forceReupload {
                    let mediaReference: AnyMediaReference
                    if file.isSticker {
                        mediaReference = .standalone(media: file)
                    } else {
                        mediaReference = .savedGif(media: file)
                    }
                    return revalidateMediaResourceReference(postbox: postbox, network: network, revalidationContext: revalidationContext, info: TelegramCloudMediaResourceFetchInfo(reference: mediaReference.resourceReference(file.resource), preferBackgroundReferenceRevalidation: false, continueInBackground: false), resource: resource)
                    |> mapError { _ -> PendingMessageUploadError in
                        return .generic
                    }
                    |> mapToSignal { validatedResource -> Signal<PendingMessageUploadedContentResult, PendingMessageUploadError> in
                        if let validatedResource = validatedResource.updatedResource as? TelegramCloudMediaResourceWithFileReference, let reference = validatedResource.fileReference {
                            return .single(.content(PendingMessageUploadedContentAndReuploadInfo(content: .media(Api.InputMedia.inputMediaDocument(flags: 0, id: Api.InputDocument.inputDocument(id: resource.fileId, accessHash: resource.accessHash, fileReference: Buffer(data: reference)), ttlSeconds: nil), text), reuploadInfo: nil)))
                        } else {
                            return .fail(.generic)
                        }
                    }
                }
                return .single(.content(PendingMessageUploadedContentAndReuploadInfo(content: .media(Api.InputMedia.inputMediaDocument(flags: 0, id: Api.InputDocument.inputDocument(id: resource.fileId, accessHash: resource.accessHash, fileReference: Buffer(data: resource.fileReference ?? Data())), ttlSeconds: nil), text), reuploadInfo: nil)))
            }
        } else {
            return uploadedMediaFileContent(network: network, postbox: postbox, auxiliaryMethods: auxiliaryMethods, transformOutgoingMessageMedia: transformOutgoingMessageMedia, messageMediaPreuploadManager: messageMediaPreuploadManager, forceReupload: forceReupload, isGrouped: isGrouped, peerId: peerId, messageId: messageId, text: text, attributes: attributes, file: file)
        }
    } else if let contact = media as? TelegramMediaContact {
        let input = Api.InputMedia.inputMediaContact(phoneNumber: contact.phoneNumber, firstName: contact.firstName, lastName: contact.lastName, vcard: contact.vCardData ?? "")
        return .single(.content(PendingMessageUploadedContentAndReuploadInfo(content: .media(input, text), reuploadInfo: nil)))
    } else if let map = media as? TelegramMediaMap {
        let input: Api.InputMedia
        if let liveBroadcastingTimeout = map.liveBroadcastingTimeout {
            input = .inputMediaGeoLive(flags: 1 << 1, geoPoint: Api.InputGeoPoint.inputGeoPoint(lat: map.latitude, long: map.longitude), period: liveBroadcastingTimeout)
        } else if let venue = map.venue {
            input = .inputMediaVenue(geoPoint: Api.InputGeoPoint.inputGeoPoint(lat: map.latitude, long: map.longitude), title: venue.title, address: venue.address ?? "", provider: venue.provider ?? "", venueId: venue.id ?? "", venueType: venue.type ?? "")
        } else {
            input = .inputMediaGeoPoint(geoPoint: Api.InputGeoPoint.inputGeoPoint(lat: map.latitude, long: map.longitude))
        }
        return .single(.content(PendingMessageUploadedContentAndReuploadInfo(content: .media(input, text), reuploadInfo: nil)))
    } else if let poll = media as? TelegramMediaPoll {
        if peerId.namespace == Namespaces.Peer.SecretChat {
            return .fail(.generic)
        }
        let inputPoll = Api.InputMedia.inputMediaPoll(poll: Api.Poll.poll(id: 0, flags: 0, question: poll.text, answers: poll.options.map({ $0.apiOption })))
        return .single(.content(PendingMessageUploadedContentAndReuploadInfo(content: .media(inputPoll, text), reuploadInfo: nil)))
    } else {
        return nil
    }
}

private enum PredownloadedResource {
    case localReference(CachedSentMediaReferenceKey?)
    case media(Media)
    case none
}

private func maybePredownloadedImageResource(postbox: Postbox, peerId: PeerId, resource: MediaResource, forceRefresh: Bool) -> Signal<PredownloadedResource, PendingMessageUploadError> {
    if peerId.namespace == Namespaces.Peer.SecretChat {
        return .single(.none)
    }
    
    return Signal<Signal<PredownloadedResource, PendingMessageUploadError>, PendingMessageUploadError> { subscriber in
        let data = postbox.mediaBox.resourceData(resource, option: .complete(waitUntilFetchStatus: false)).start(next: { data in
            if data.complete {
                if data.size < 5 * 1024 * 1024, let fileData = try? Data(contentsOf: URL(fileURLWithPath: data.path), options: .mappedRead) {
                    let md5 = IncrementalMD5()
                    fileData.withUnsafeBytes { (bytes: UnsafePointer<Int8>) -> Void in
                        var offset = 0
                        let bufferSize = 32 * 1024
                        
                        while offset < fileData.count {
                            let partSize = min(fileData.count - offset, bufferSize)
                            md5.update(bytes.advanced(by: offset), count: Int32(partSize))
                            offset += bufferSize
                        }
                    }
                    
                    let res = md5.complete()
                    
                    let reference: CachedSentMediaReferenceKey = .image(hash: res)
                    if forceRefresh {
                        subscriber.putNext(.single(.localReference(reference)))
                    } else {
                        subscriber.putNext(cachedSentMediaReference(postbox: postbox, key: reference)
                            |> mapError { _ -> PendingMessageUploadError in return .generic } |> map { media -> PredownloadedResource in
                            if let media = media {
                                return .media(media)
                            } else {
                                return .localReference(reference)
                            }
                        })
                    }
                    subscriber.putCompletion()
                } else {
                    subscriber.putNext(.single(.localReference(nil)))
                    subscriber.putCompletion()
                }
            }
        })
        let fetched = postbox.mediaBox.fetchedResource(resource, parameters: nil).start(error: { _ in
            subscriber.putError(.generic)
        })
        
        return ActionDisposable {
            data.dispose()
            fetched.dispose()
        }
    }
    |> switchToLatest
}

private func maybePredownloadedFileResource(postbox: Postbox, auxiliaryMethods: AccountAuxiliaryMethods, peerId: PeerId, resource: MediaResource, forceRefresh: Bool) -> Signal<PredownloadedResource, PendingMessageUploadError> {
    if peerId.namespace == Namespaces.Peer.SecretChat {
        return .single(.none)
    }
    
    return auxiliaryMethods.fetchResourceMediaReferenceHash(resource)
    |> mapToSignal { hash -> Signal<PredownloadedResource, NoError> in
        if let hash = hash {
            let reference: CachedSentMediaReferenceKey = .file(hash: hash)
            if forceRefresh {
                return .single(.localReference(reference))
            }
            return cachedSentMediaReference(postbox: postbox, key: reference) |> map { media -> PredownloadedResource in
                if let media = media {
                    return .media(media)
                } else {
                    return .localReference(reference)
                }
            }
        } else {
            return .single(.localReference(nil))
        }
    }
    |> mapError { _ -> PendingMessageUploadError in return .generic }
}

private func maybeCacheUploadedResource(postbox: Postbox, key: CachedSentMediaReferenceKey?, result: PendingMessageUploadedContentResult, media: Media) -> Signal<PendingMessageUploadedContentResult, PendingMessageUploadError> {
    if let key = key {
        return postbox.transaction { transaction -> PendingMessageUploadedContentResult in
            storeCachedSentMediaReference(transaction: transaction, key: key, media: media)
            return result
        } |> mapError { _ -> PendingMessageUploadError in return .generic }
    } else {
        return .single(result)
    }
}

private func uploadedMediaImageContent(network: Network, postbox: Postbox, transformOutgoingMessageMedia: TransformOutgoingMessageMedia?, forceReupload: Bool, isGrouped: Bool, peerId: PeerId, image: TelegramMediaImage, messageId: MessageId?, text: String, attributes: [MessageAttribute], autoremoveAttribute: AutoremoveTimeoutMessageAttribute?) -> Signal<PendingMessageUploadedContentResult, PendingMessageUploadError> {
    guard let largestRepresentation = largestImageRepresentation(image.representations) else {
        return .single(.content(PendingMessageUploadedContentAndReuploadInfo(content: .text(text), reuploadInfo: nil)))
    }
    
    let predownloadedResource: Signal<PredownloadedResource, PendingMessageUploadError> = maybePredownloadedImageResource(postbox: postbox, peerId: peerId, resource: largestRepresentation.resource, forceRefresh: forceReupload)
    return predownloadedResource
    |> mapToSignal { result -> Signal<PendingMessageUploadedContentResult, PendingMessageUploadError> in
        var referenceKey: CachedSentMediaReferenceKey?
        switch result {
            case let .media(media):
                if !forceReupload, let image = media as? TelegramMediaImage, let reference = image.reference, case let .cloud(id, accessHash, maybeFileReference) = reference, let fileReference = maybeFileReference {
                    var flags: Int32 = 0
                    var ttlSeconds: Int32?
                    if let autoremoveAttribute = autoremoveAttribute {
                        flags |= 1 << 0
                        ttlSeconds = autoremoveAttribute.timeout
                    }
                    return .single(.progress(1.0))
                    |> then(
                        .single(.content(PendingMessageUploadedContentAndReuploadInfo(content: .media(.inputMediaPhoto(flags: flags, id: .inputPhoto(id: id, accessHash: accessHash, fileReference: Buffer(data: fileReference)), ttlSeconds: ttlSeconds), text), reuploadInfo: nil)))
                    )
                }
            case let .localReference(key):
                referenceKey = key
            case .none:
                referenceKey = nil
        }
        
        var alreadyTransformed = false
        for attribute in attributes {
            if let attribute = attribute as? OutgoingMessageInfoAttribute {
                if attribute.flags.contains(.transformedMedia) {
                    alreadyTransformed = true
                }
            }
        }
        let transform: Signal<UploadedMediaTransform, NoError>
        if let transformOutgoingMessageMedia = transformOutgoingMessageMedia, let messageId = messageId, !alreadyTransformed {
            transform = .single(.pending)
            |> then(
                transformOutgoingMessageMedia(postbox, network, .standalone(media: image), false)
                |> mapToSignal { mediaReference -> Signal<UploadedMediaTransform, NoError> in
                    return postbox.transaction { transaction -> UploadedMediaTransform in
                        if let media = mediaReference?.media {
                            if let id = media.id {
                                let _ = transaction.updateMedia(id, update: media)
                                transaction.updateMessage(messageId, update: { currentMessage in
                                    var storeForwardInfo: StoreMessageForwardInfo?
                                    if let forwardInfo = currentMessage.forwardInfo {
                                        storeForwardInfo = StoreMessageForwardInfo(authorId: forwardInfo.author?.id, sourceId: forwardInfo.source?.id, sourceMessageId: forwardInfo.sourceMessageId, date: forwardInfo.date, authorSignature: nil)
                                    }
                                    var updatedAttributes = currentMessage.attributes
                                    if let index = updatedAttributes.index(where: { $0 is OutgoingMessageInfoAttribute }){
                                        let attribute = updatedAttributes[index] as! OutgoingMessageInfoAttribute
                                        updatedAttributes[index] = attribute.withUpdatedFlags(attribute.flags.union([.transformedMedia]))
                                    } else {
                                        updatedAttributes.append(OutgoingMessageInfoAttribute(uniqueId: arc4random64(), flags: [.transformedMedia], acknowledged: false))
                                    }
                                    return .update(StoreMessage(id: currentMessage.id, globallyUniqueId: currentMessage.globallyUniqueId, groupingKey: currentMessage.groupingKey, timestamp: currentMessage.timestamp, flags: StoreMessageFlags(currentMessage.flags), tags: currentMessage.tags, globalTags: currentMessage.globalTags, localTags: currentMessage.localTags, forwardInfo: storeForwardInfo, authorId: currentMessage.author?.id, text: currentMessage.text, attributes: updatedAttributes, media: currentMessage.media))
                                })
                            }
                            return .done(media)
                        } else {
                            return .done(image)
                        }
                    }
                }
            )
        } else {
            transform = .single(.done(image))
        }
        
        return transform
        |> mapError { _ -> PendingMessageUploadError in
            return .generic
        }
        |> mapToSignal { transformResult -> Signal<PendingMessageUploadedContentResult, PendingMessageUploadError> in
            switch transformResult {
            case .pending:
                return .single(.progress(0.0))
            case let .done(transformedMedia):
                let transformedImage = (transformedMedia as? TelegramMediaImage) ?? image
                guard let largestRepresentation = largestImageRepresentation(transformedImage.representations) else {
                    return .fail(.generic)
                }
                let imageReference: AnyMediaReference
                if let partialReference = transformedImage.partialReference {
                    imageReference = partialReference.mediaReference(transformedImage)
                } else {
                    imageReference = .standalone(media: transformedImage)
                }
                return multipartUpload(network: network, postbox: postbox, source: .resource(imageReference.resourceReference(largestRepresentation.resource)), encrypt: peerId.namespace == Namespaces.Peer.SecretChat, tag: TelegramMediaResourceFetchTag(statsCategory: .image), hintFileSize: nil, hintFileIsLarge: false)
                |> mapError { _ -> PendingMessageUploadError in return .generic }
                |> mapToSignal { next -> Signal<PendingMessageUploadedContentResult, PendingMessageUploadError> in
                    switch next {
                        case let .progress(progress):
                            return .single(.progress(progress))
                        case let .inputFile(file):
                            var flags: Int32 = 0
                            var ttlSeconds: Int32?
                            if let autoremoveAttribute = autoremoveAttribute {
                                flags |= 1 << 1
                                ttlSeconds = autoremoveAttribute.timeout
                            }
                            return postbox.transaction { transaction -> Api.InputPeer? in
                                return transaction.getPeer(peerId).flatMap(apiInputPeer)
                            }
                            |> mapError { _ -> PendingMessageUploadError in return .generic }
                            |> mapToSignal { inputPeer -> Signal<PendingMessageUploadedContentResult, PendingMessageUploadError> in
                                if let inputPeer = inputPeer {
                                    if autoremoveAttribute != nil {
                                        return .single(.content(PendingMessageUploadedContentAndReuploadInfo(content: .media(.inputMediaUploadedPhoto(flags: flags, file: file, stickers: nil, ttlSeconds: ttlSeconds), text), reuploadInfo: nil)))
                                    }
                                    
                                    return network.request(Api.functions.messages.uploadMedia(peer: inputPeer, media: Api.InputMedia.inputMediaUploadedPhoto(flags: flags, file: file, stickers: nil, ttlSeconds: ttlSeconds)))
                                    |> mapError { _ -> PendingMessageUploadError in return .generic }
                                    |> mapToSignal { result -> Signal<PendingMessageUploadedContentResult, PendingMessageUploadError> in
                                        switch result {
                                            case let .messageMediaPhoto(_, photo, _):
                                                if let photo = photo, let mediaImage = telegramMediaImageFromApiPhoto(photo), let reference = mediaImage.reference, case let .cloud(id, accessHash, maybeFileReference) = reference, let fileReference = maybeFileReference {
                                                    var flags: Int32 = 0
                                                    var ttlSeconds: Int32?
                                                    if let autoremoveAttribute = autoremoveAttribute {
                                                        flags |= 1 << 0
                                                        ttlSeconds = autoremoveAttribute.timeout
                                                    }
                                                    return maybeCacheUploadedResource(postbox: postbox, key: referenceKey, result: .content(PendingMessageUploadedContentAndReuploadInfo(content: .media(.inputMediaPhoto(flags: flags, id: .inputPhoto(id: id, accessHash: accessHash, fileReference: Buffer(data: fileReference)), ttlSeconds: ttlSeconds), text), reuploadInfo: nil)), media: mediaImage)
                                                }
                                            default:
                                                break
                                        }
                                        return .fail(.generic)
                                    }
                                } else {
                                    return .fail(.generic)
                                }
                            }
                        case let .inputSecretFile(file, size, key):
                            return .single(.content(PendingMessageUploadedContentAndReuploadInfo(content: .secretMedia(file, size, key), reuploadInfo: nil)))
                    }
                }
            }
        }
    }
}

func inputDocumentAttributesFromFileAttributes(_ fileAttributes: [TelegramMediaFileAttribute]) -> [Api.DocumentAttribute] {
    var attributes: [Api.DocumentAttribute] = []
    for attribute in fileAttributes {
        switch attribute {
            case .Animated:
                attributes.append(.documentAttributeAnimated)
            case let .FileName(fileName):
                attributes.append(.documentAttributeFilename(fileName: fileName))
            case let .ImageSize(size):
                attributes.append(.documentAttributeImageSize(w: Int32(size.width), h: Int32(size.height)))
            case let .Sticker(displayText, packReference, maskCoords):
                var stickerSet: Api.InputStickerSet = .inputStickerSetEmpty
                var flags: Int32 = 0
                if let packReference = packReference {
                    switch packReference {
                        case let .id(id, accessHash):
                            stickerSet = .inputStickerSetID(id: id, accessHash: accessHash)
                        case let .name(name):
                            stickerSet = .inputStickerSetShortName(shortName: name)
                        default:
                            stickerSet = .inputStickerSetEmpty
                    }
                }
                var inputMaskCoords: Api.MaskCoords?
                if let maskCoords = maskCoords {
                    flags |= 1 << 0
                    inputMaskCoords = .maskCoords(n: maskCoords.n, x: maskCoords.x, y: maskCoords.y, zoom: maskCoords.zoom)
                }
                attributes.append(.documentAttributeSticker(flags: flags, alt: displayText, stickerset: stickerSet, maskCoords: inputMaskCoords))
            case .HasLinkedStickers:
                attributes.append(.documentAttributeHasStickers)
            case let .Video(duration, size, videoFlags):
                var flags: Int32 = 0
                if videoFlags.contains(.instantRoundVideo) {
                    flags |= (1 << 0)
                }
                if videoFlags.contains(.supportsStreaming) {
                    flags |= (1 << 1)
                }
                
                attributes.append(.documentAttributeVideo(flags: flags, duration: Int32(duration), w: Int32(size.width), h: Int32(size.height)))
            case let .Audio(isVoice, duration, title, performer, waveform):
                var flags: Int32 = 0
                if isVoice {
                    flags |= Int32(1 << 10)
                }
                if let _ = title {
                    flags |= Int32(1 << 0)
                }
                if let _ = performer {
                    flags |= Int32(1 << 1)
                }
                var waveformBuffer: Buffer?
                if let waveform = waveform {
                    flags |= Int32(1 << 2)
                    waveformBuffer = Buffer(data: waveform.makeData())
                }
                attributes.append(.documentAttributeAudio(flags: flags, duration: Int32(duration), title: title, performer: performer, waveform: waveformBuffer))
        }
    }
    return attributes
}

private enum UploadedMediaTransform {
    case pending
    case done(Media?)
}

private enum UploadedMediaThumbnailResult {
    case file(Api.InputFile)
    case none
}

private enum UploadedMediaFileAndThumbnail {
    case pending
    case done(TelegramMediaFile, UploadedMediaThumbnailResult)
}

private func uploadedThumbnail(network: Network, postbox: Postbox, resourceReference: MediaResourceReference) -> Signal<Api.InputFile?, PendingMessageUploadError> {
    return multipartUpload(network: network, postbox: postbox, source: .resource(resourceReference), encrypt: false, tag: TelegramMediaResourceFetchTag(statsCategory: .image), hintFileSize: nil, hintFileIsLarge: false)
    |> mapError { _ -> PendingMessageUploadError in return .generic }
    |> mapToSignal { result -> Signal<Api.InputFile?, PendingMessageUploadError> in
        switch result {
            case .progress:
                return .complete()
            case let .inputFile(inputFile):
                return .single(inputFile)
            case .inputSecretFile:
                return .single(nil)
        }
    }
}

public func statsCategoryForFileWithAttributes(_ attributes: [TelegramMediaFileAttribute]) -> MediaResourceStatsCategory {
    for attribute in attributes {
        switch attribute {
            case .Audio:
                return .audio
            case .Video:
                return .video
            default:
                break
        }
    }
    return .file
}

private func uploadedMediaFileContent(network: Network, postbox: Postbox, auxiliaryMethods: AccountAuxiliaryMethods, transformOutgoingMessageMedia: TransformOutgoingMessageMedia?, messageMediaPreuploadManager: MessageMediaPreuploadManager, forceReupload: Bool, isGrouped: Bool, peerId: PeerId, messageId: MessageId?, text: String, attributes: [MessageAttribute], file: TelegramMediaFile) -> Signal<PendingMessageUploadedContentResult, PendingMessageUploadError> {
    return maybePredownloadedFileResource(postbox: postbox, auxiliaryMethods: auxiliaryMethods, peerId: peerId, resource: file.resource, forceRefresh: forceReupload)
    |> mapToSignal { result -> Signal<PendingMessageUploadedContentResult, PendingMessageUploadError> in
        var referenceKey: CachedSentMediaReferenceKey?
        switch result {
            case let .media(media):
                if !forceReupload, let file = media as? TelegramMediaFile, let resource = file.resource as? CloudDocumentMediaResource, let fileReference = resource.fileReference {
                    return .single(.progress(1.0))
                    |> then(
                        .single(.content(PendingMessageUploadedContentAndReuploadInfo(content: .media(Api.InputMedia.inputMediaDocument(flags: 0, id: Api.InputDocument.inputDocument(id: resource.fileId, accessHash: resource.accessHash, fileReference: Buffer(data: fileReference)), ttlSeconds: nil), text), reuploadInfo: nil)))
                    )
                }
            case let .localReference(key):
                referenceKey = key
            case .none:
                referenceKey = nil
        }
        
        var hintFileIsLarge = false
        var hintSize: Int?
        if let size = file.size {
            hintSize = size
        } else if let resource = file.resource as? LocalFileReferenceMediaResource, let size = resource.size {
            hintSize = Int(size)
        }
        if (file.resource.headerSize != 0 || file.mimeType.hasPrefix("video/mp4")) && !file.isAnimated {
            hintFileIsLarge = true
        }
        let fileReference: AnyMediaReference
        if let partialReference = file.partialReference {
            fileReference = partialReference.mediaReference(file)
        } else {
            fileReference = .standalone(media: file)
        }
        let upload = messageMediaPreuploadManager.upload(network: network, postbox: postbox, source: .resource(fileReference.resourceReference(file.resource)), encrypt: peerId.namespace == Namespaces.Peer.SecretChat, tag: TelegramMediaResourceFetchTag(statsCategory: statsCategoryForFileWithAttributes(file.attributes)), hintFileSize: hintSize, hintFileIsLarge: hintFileIsLarge)
        |> mapError { _ -> PendingMessageUploadError in return .generic
        }
        var alreadyTransformed = false
        for attribute in attributes {
            if let attribute = attribute as? OutgoingMessageInfoAttribute {
                if attribute.flags.contains(.transformedMedia) {
                    alreadyTransformed = true
                }
            }
        }
    
        let transform: Signal<UploadedMediaTransform, NoError>
        if let transformOutgoingMessageMedia = transformOutgoingMessageMedia, let messageId = messageId, !alreadyTransformed {
            transform = .single(.pending)
            |> then(transformOutgoingMessageMedia(postbox, network, .standalone(media: file), false)
            |> mapToSignal { mediaReference -> Signal<UploadedMediaTransform, NoError> in
                return postbox.transaction { transaction -> UploadedMediaTransform in
                    if let media = mediaReference?.media {
                        if let id = media.id {
                            let _ = transaction.updateMedia(id, update: media)
                            transaction.updateMessage(messageId, update: { currentMessage in
                                var storeForwardInfo: StoreMessageForwardInfo?
                                if let forwardInfo = currentMessage.forwardInfo {
                                    storeForwardInfo = StoreMessageForwardInfo(authorId: forwardInfo.author?.id, sourceId: forwardInfo.source?.id, sourceMessageId: forwardInfo.sourceMessageId, date: forwardInfo.date, authorSignature: nil)
                                }
                                var updatedAttributes = currentMessage.attributes
                                if let index = updatedAttributes.index(where: { $0 is OutgoingMessageInfoAttribute }){
                                    let attribute = updatedAttributes[index] as! OutgoingMessageInfoAttribute
                                    updatedAttributes[index] = attribute.withUpdatedFlags(attribute.flags.union([.transformedMedia]))
                                } else {
                                    updatedAttributes.append(OutgoingMessageInfoAttribute(uniqueId: arc4random64(), flags: [.transformedMedia], acknowledged: false))
                                }
                                return .update(StoreMessage(id: currentMessage.id, globallyUniqueId: currentMessage.globallyUniqueId, groupingKey: currentMessage.groupingKey, timestamp: currentMessage.timestamp, flags: StoreMessageFlags(currentMessage.flags), tags: currentMessage.tags, globalTags: currentMessage.globalTags, localTags: currentMessage.localTags, forwardInfo: storeForwardInfo, authorId: currentMessage.author?.id, text: currentMessage.text, attributes: updatedAttributes, media: currentMessage.media))
                            })
                        }
                        return .done(media)
                    } else {
                        return .done(file)
                    }
                }
            })
        } else {
            transform = .single(.done(file))
        }
    
        let transformedFileAndThumbnail: Signal<UploadedMediaFileAndThumbnail, PendingMessageUploadError> = .single(.pending)
        |> then(transform
        |> mapToSignalPromotingError { media -> Signal<UploadedMediaFileAndThumbnail, PendingMessageUploadError> in
            switch media {
                case .pending:
                    return .single(.pending)
                case let .done(media):
                    if let media = media as? TelegramMediaFile, let smallestThumbnail = smallestImageRepresentation(media.previewRepresentations) {
                        if peerId.namespace == Namespaces.Peer.SecretChat {
                            return .single(.done(media, .none))
                        } else {
                            let fileReference: AnyMediaReference
                            if let partialReference = media.partialReference {
                                fileReference = partialReference.mediaReference(media)
                            } else {
                                fileReference = .standalone(media: media)
                            }
                            
                            return uploadedThumbnail(network: network, postbox: postbox, resourceReference: fileReference.resourceReference(smallestThumbnail.resource))
                            |> mapError { _ -> PendingMessageUploadError in return .generic }
                            |> map { result in
                                if let result = result {
                                    return .done(media, .file(result))
                                } else {
                                    return .done(media, .none)
                                }
                            }
                        }
                    } else {
                        return .single(.done(file, .none))
                    }
            }
        })
    
        return combineLatest(upload, transformedFileAndThumbnail)
        |> mapToSignal { content, fileAndThumbnailResult -> Signal<PendingMessageUploadedContentResult, PendingMessageUploadError> in
            switch content {
                case let .progress(progress):
                    return .single(.progress(progress))
                case let .inputFile(inputFile):
                    if case let .done(file, thumbnail) = fileAndThumbnailResult {
                        var flags: Int32 = 0
                        
                        var thumbnailFile: Api.InputFile?
                        if case let .file(file) = thumbnail {
                            thumbnailFile = file
                        }
                        
                        if let _ = thumbnailFile {
                            flags |= 1 << 2
                        }
                        
                        var ttlSeconds: Int32?
                        for attribute in attributes {
                            if let attribute = attribute as? AutoremoveTimeoutMessageAttribute {
                                flags |= 1 << 1
                                ttlSeconds = attribute.timeout
                            }
                        }
                        
                        if !file.isAnimated {
                            flags |= 1 << 3
                        }
                        
                        
                        if ttlSeconds != nil  {
                            return .single(.content(PendingMessageUploadedContentAndReuploadInfo(content: .media(.inputMediaUploadedDocument(flags: flags, file: inputFile, thumb: thumbnailFile, mimeType: file.mimeType, attributes: inputDocumentAttributesFromFileAttributes(file.attributes), stickers: nil, ttlSeconds: ttlSeconds), text), reuploadInfo: nil)))
                        }
                        
                        if !isGrouped {
                            return .single(.content(PendingMessageUploadedContentAndReuploadInfo(content: .media(.inputMediaUploadedDocument(flags: flags, file: inputFile, thumb: thumbnailFile, mimeType: file.mimeType, attributes: inputDocumentAttributesFromFileAttributes(file.attributes), stickers: nil, ttlSeconds: ttlSeconds), text), reuploadInfo: nil)))
                        }
                        
                        return postbox.transaction { transaction -> Api.InputPeer? in
                            return transaction.getPeer(peerId).flatMap(apiInputPeer)
                        }
                        |> mapError { _ -> PendingMessageUploadError in return .generic }
                        |> mapToSignal { inputPeer -> Signal<PendingMessageUploadedContentResult, PendingMessageUploadError> in
                            if let inputPeer = inputPeer {
                                return network.request(Api.functions.messages.uploadMedia(peer: inputPeer, media: .inputMediaUploadedDocument(flags: flags, file: inputFile, thumb: thumbnailFile, mimeType: file.mimeType, attributes: inputDocumentAttributesFromFileAttributes(file.attributes), stickers: nil, ttlSeconds: ttlSeconds)))
                                |> mapError { _ -> PendingMessageUploadError in return .generic }
                                |> mapToSignal { result -> Signal<PendingMessageUploadedContentResult, PendingMessageUploadError> in
                                    switch result {
                                        case let .messageMediaDocument(_, document, _):
                                            if let document = document, let mediaFile = telegramMediaFileFromApiDocument(document), let resource = mediaFile.resource as? CloudDocumentMediaResource, let fileReference = resource.fileReference {
                                                return maybeCacheUploadedResource(postbox: postbox, key: referenceKey, result: .content(PendingMessageUploadedContentAndReuploadInfo(content: .media(.inputMediaDocument(flags: 0, id: .inputDocument(id: resource.fileId, accessHash: resource.accessHash, fileReference: Buffer(data: fileReference)), ttlSeconds: nil), text), reuploadInfo: nil)), media: mediaFile)
                                            }
                                        default:
                                            break
                                    }
                                    return .fail(.generic)
                                }
                            } else {
                                return .fail(.generic)
                            }
                        }
                    } else {
                        return .complete()
                    }
                case let .inputSecretFile(file, size, key):
                    if case .done = fileAndThumbnailResult {
                        return .single(.content(PendingMessageUploadedContentAndReuploadInfo(content: .secretMedia(file, size, key), reuploadInfo: nil)))
                    } else {
                        return .complete()
                    }
            }
        }
    }
}
