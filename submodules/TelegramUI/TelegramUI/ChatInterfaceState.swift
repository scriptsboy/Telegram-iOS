import Foundation
import UIKit
import Postbox
import TelegramCore

struct ChatInterfaceSelectionState: PostboxCoding, Equatable {
    let selectedIds: Set<MessageId>
    
    static func ==(lhs: ChatInterfaceSelectionState, rhs: ChatInterfaceSelectionState) -> Bool {
        return lhs.selectedIds == rhs.selectedIds
    }
    
    init(selectedIds: Set<MessageId>) {
        self.selectedIds = selectedIds
    }
    
    init(decoder: PostboxDecoder) {
        if let data = decoder.decodeBytesForKeyNoCopy("i") {
            self.selectedIds = Set(MessageId.decodeArrayFromBuffer(data))
        } else {
            self.selectedIds = Set()
        }
    }
    
    func encode(_ encoder: PostboxEncoder) {
        let buffer = WriteBuffer()
        MessageId.encodeArrayToBuffer(Array(selectedIds), buffer: buffer)
        encoder.encodeBytes(buffer, forKey: "i")
    }
}

private enum ChatTextInputStateTextAttributeType: PostboxCoding, Equatable {
    case bold
    case italic
    case monospace
    case textMention(PeerId)
    case textUrl(String)
    
    init(decoder: PostboxDecoder) {
        switch decoder.decodeInt32ForKey("t", orElse: 0) {
            case 0:
                self = .bold
            case 1:
                self = .italic
            case 2:
                self = .monospace
            case 3:
                self = .textMention(PeerId(decoder.decodeInt64ForKey("peerId", orElse: 0)))
            case 4:
                self = .textUrl(decoder.decodeStringForKey("url", orElse: ""))
            default:
                assertionFailure()
                self = .bold
        }
    }
    
    func encode(_ encoder: PostboxEncoder) {
        switch self {
            case .bold:
                encoder.encodeInt32(0, forKey: "t")
            case .italic:
                encoder.encodeInt32(1, forKey: "t")
            case .monospace:
                encoder.encodeInt32(2, forKey: "t")
            case let .textMention(id):
                encoder.encodeInt32(3, forKey: "t")
                encoder.encodeInt64(id.toInt64(), forKey: "peerId")
            case let .textUrl(url):
                encoder.encodeInt32(4, forKey: "t")
                encoder.encodeString(url, forKey: "url")
        }
    }
    
    static func ==(lhs: ChatTextInputStateTextAttributeType, rhs: ChatTextInputStateTextAttributeType) -> Bool {
        switch lhs {
            case .bold:
                if case .bold = rhs {
                    return true
                } else {
                    return false
                }
            case .italic:
                if case .italic = rhs {
                    return true
                } else {
                    return false
                }
            case .monospace:
                if case .monospace = rhs {
                    return true
                } else {
                    return false
                }
            case let .textMention(id):
                if case .textMention(id) = rhs {
                    return true
                } else {
                    return false
                }
            case let .textUrl(url):
                if case .textUrl(url) = rhs {
                    return true
                } else {
                    return false
                }
        }
    }
}

private struct ChatTextInputStateTextAttribute: PostboxCoding, Equatable {
    let type: ChatTextInputStateTextAttributeType
    let range: Range<Int>
    
    init(type: ChatTextInputStateTextAttributeType, range: Range<Int>) {
        self.type = type
        self.range = range
    }
    
    init(decoder: PostboxDecoder) {
        self.type = decoder.decodeObjectForKey("type", decoder: { ChatTextInputStateTextAttributeType(decoder: $0) }) as! ChatTextInputStateTextAttributeType
        self.range = Int(decoder.decodeInt32ForKey("range0", orElse: 0)) ..< Int(decoder.decodeInt32ForKey("range1", orElse: 0))
    }
    
    func encode(_ encoder: PostboxEncoder) {
        encoder.encodeObject(self.type, forKey: "type")
        encoder.encodeInt32(Int32(self.range.lowerBound), forKey: "range0")
        encoder.encodeInt32(Int32(self.range.upperBound), forKey: "range1")
    }
    
    static func ==(lhs: ChatTextInputStateTextAttribute, rhs: ChatTextInputStateTextAttribute) -> Bool {
        return lhs.type == rhs.type && lhs.range == rhs.range
    }
}

private struct ChatTextInputStateText: PostboxCoding, Equatable {
    let text: String
    fileprivate let attributes: [ChatTextInputStateTextAttribute]
    
    init() {
        self.text = ""
        self.attributes = []
    }
    
    init(text: String, attributes: [ChatTextInputStateTextAttribute]) {
        self.text = text
        self.attributes = attributes
    }
    
    init(attributedText: NSAttributedString) {
        self.text = attributedText.string
        var parsedAttributes: [ChatTextInputStateTextAttribute] = []
        attributedText.enumerateAttributes(in: NSRange(location: 0, length: attributedText.length), options: [], using: { attributes, range, _ in
            for (key, value) in attributes {
                if key == ChatTextInputAttributes.bold {
                    parsedAttributes.append(ChatTextInputStateTextAttribute(type: .bold, range: range.location ..< (range.location + range.length)))
                } else if key == ChatTextInputAttributes.italic {
                    parsedAttributes.append(ChatTextInputStateTextAttribute(type: .italic, range: range.location ..< (range.location + range.length)))
                } else if key == ChatTextInputAttributes.monospace {
                    parsedAttributes.append(ChatTextInputStateTextAttribute(type: .monospace, range: range.location ..< (range.location + range.length)))
                } else if key == ChatTextInputAttributes.textMention, let value = value as? ChatTextInputTextMentionAttribute {
                    parsedAttributes.append(ChatTextInputStateTextAttribute(type: .textMention(value.peerId), range: range.location ..< (range.location + range.length)))
                } else if key == ChatTextInputAttributes.textUrl, let value = value as? ChatTextInputTextUrlAttribute {
                    parsedAttributes.append(ChatTextInputStateTextAttribute(type: .textUrl(value.url), range: range.location ..< (range.location + range.length)))
                }
            }
        })
        self.attributes = parsedAttributes
    }
    
    init(decoder: PostboxDecoder) {
        self.text = decoder.decodeStringForKey("text", orElse: "")
        self.attributes = decoder.decodeObjectArrayWithDecoderForKey("attributes")
    }
    
    func encode(_ encoder: PostboxEncoder) {
        encoder.encodeString(self.text, forKey: "text")
        encoder.encodeObjectArray(self.attributes, forKey: "attributes")
    }
    
    static func ==(lhs: ChatTextInputStateText, rhs: ChatTextInputStateText) -> Bool {
        return lhs.text == rhs.text && lhs.attributes == rhs.attributes
    }
    
    func attributedText() -> NSAttributedString {
        let result = NSMutableAttributedString(string: self.text)
        for attribute in self.attributes {
            switch attribute.type {
                case .bold:
                    result.addAttribute(ChatTextInputAttributes.bold, value: true as NSNumber, range: NSRange(location: attribute.range.lowerBound, length: attribute.range.count))
                case .italic:
                    result.addAttribute(ChatTextInputAttributes.italic, value: true as NSNumber, range: NSRange(location: attribute.range.lowerBound, length: attribute.range.count))
                case .monospace:
                    result.addAttribute(ChatTextInputAttributes.monospace, value: true as NSNumber, range: NSRange(location: attribute.range.lowerBound, length: attribute.range.count))
                case let .textMention(id):
                    result.addAttribute(ChatTextInputAttributes.textMention, value: ChatTextInputTextMentionAttribute(peerId: id), range: NSRange(location: attribute.range.lowerBound, length: attribute.range.count))
                case let .textUrl(url):
                    result.addAttribute(ChatTextInputAttributes.textUrl, value: ChatTextInputTextUrlAttribute(url: url), range: NSRange(location: attribute.range.lowerBound, length: attribute.range.count))
            }
        }
        return result
    }
}

public struct ChatTextInputState: PostboxCoding, Equatable {
    let inputText: NSAttributedString
    let selectionRange: Range<Int>
    
    public static func ==(lhs: ChatTextInputState, rhs: ChatTextInputState) -> Bool {
        return lhs.inputText.isEqual(to: rhs.inputText) && lhs.selectionRange == rhs.selectionRange
    }
    
    init() {
        self.inputText = NSAttributedString()
        self.selectionRange = 0 ..< 0
    }
    
    init(inputText: NSAttributedString, selectionRange: Range<Int>) {
        self.inputText = inputText
        self.selectionRange = selectionRange
    }
    
    init(inputText: NSAttributedString) {
        self.inputText = inputText
        let length = inputText.length
        self.selectionRange = length ..< length
    }
    
    public init(decoder: PostboxDecoder) {
        self.inputText = ((decoder.decodeObjectForKey("at", decoder: { ChatTextInputStateText(decoder: $0) }) as? ChatTextInputStateText) ?? ChatTextInputStateText()).attributedText()
        self.selectionRange = Int(decoder.decodeInt32ForKey("as0", orElse: 0)) ..< Int(decoder.decodeInt32ForKey("as1", orElse: 0))
    }
    
    public func encode(_ encoder: PostboxEncoder) {
        encoder.encodeObject(ChatTextInputStateText(attributedText: self.inputText), forKey: "at")
        
        encoder.encodeInt32(Int32(self.selectionRange.lowerBound), forKey: "as0")
        encoder.encodeInt32(Int32(self.selectionRange.upperBound), forKey: "as1")
    }
}

struct ChatEditMessageState: PostboxCoding, Equatable {
    let messageId: MessageId
    let inputState: ChatTextInputState
    let disableUrlPreview: String?
    
    init(messageId: MessageId, inputState: ChatTextInputState, disableUrlPreview: String?) {
        self.messageId = messageId
        self.inputState = inputState
        self.disableUrlPreview = disableUrlPreview
    }
    
    init(decoder: PostboxDecoder) {
        self.messageId = MessageId(peerId: PeerId(decoder.decodeInt64ForKey("mp", orElse: 0)), namespace: decoder.decodeInt32ForKey("mn", orElse: 0), id: decoder.decodeInt32ForKey("mi", orElse: 0))
        if let inputState = decoder.decodeObjectForKey("is", decoder: { return ChatTextInputState(decoder: $0) }) as? ChatTextInputState {
            self.inputState = inputState
        } else {
            self.inputState = ChatTextInputState()
        }
        self.disableUrlPreview = decoder.decodeOptionalStringForKey("dup")
    }
    
    func encode(_ encoder: PostboxEncoder) {
        encoder.encodeInt64(self.messageId.peerId.toInt64(), forKey: "mp")
        encoder.encodeInt32(self.messageId.namespace, forKey: "mn")
        encoder.encodeInt32(self.messageId.id, forKey: "mi")
        encoder.encodeObject(self.inputState, forKey: "is")
        if let disableUrlPreview = self.disableUrlPreview {
            encoder.encodeString(disableUrlPreview, forKey: "dup")
        } else {
            encoder.encodeNil(forKey: "dup")
        }
    }
    
    static func ==(lhs: ChatEditMessageState, rhs: ChatEditMessageState) -> Bool {
        return lhs.messageId == rhs.messageId && lhs.inputState == rhs.inputState && lhs.disableUrlPreview == rhs.disableUrlPreview
    }
    
    func withUpdatedInputState(_ inputState: ChatTextInputState) -> ChatEditMessageState {
        return ChatEditMessageState(messageId: self.messageId, inputState: inputState, disableUrlPreview: self.disableUrlPreview)
    }
    
    func withUpdatedDisableUrlPreview(_ disableUrlPreview: String?) -> ChatEditMessageState {
        return ChatEditMessageState(messageId: self.messageId, inputState: self.inputState, disableUrlPreview: disableUrlPreview)
    }
}

final class ChatEmbeddedInterfaceState: PeerChatListEmbeddedInterfaceState {
    let timestamp: Int32
    let text: NSAttributedString
    
    init(timestamp: Int32, text: NSAttributedString) {
        self.timestamp = timestamp
        self.text = text
    }
    
    init(decoder: PostboxDecoder) {
        self.timestamp = decoder.decodeInt32ForKey("d", orElse: 0)
        self.text = ((decoder.decodeObjectForKey("at", decoder: { ChatTextInputStateText(decoder: $0) }) as? ChatTextInputStateText) ?? ChatTextInputStateText()).attributedText()
    }
    
    func encode(_ encoder: PostboxEncoder) {
        encoder.encodeInt32(self.timestamp, forKey: "d")
        encoder.encodeObject(ChatTextInputStateText(attributedText: self.text), forKey: "at")
    }
    
    public func isEqual(to: PeerChatListEmbeddedInterfaceState) -> Bool {
        if let to = to as? ChatEmbeddedInterfaceState {
            return self.timestamp == to.timestamp && self.text.isEqual(to: to.text)
        } else {
            return false
        }
    }
}

struct ChatInterfaceMessageActionsState: PostboxCoding, Equatable {
    var closedButtonKeyboardMessageId: MessageId?
    var processedSetupReplyMessageId: MessageId?
    var closedPinnedMessageId: MessageId?
    var closedPeerSpecificPackSetup: Bool = false
    var dismissedAddContactPhoneNumber: String?
    
    var isEmpty: Bool {
        return self.closedButtonKeyboardMessageId == nil && self.processedSetupReplyMessageId == nil && self.closedPinnedMessageId == nil && self.closedPeerSpecificPackSetup == false && self.dismissedAddContactPhoneNumber == nil
    }
    
    init() {
        self.closedButtonKeyboardMessageId = nil
        self.processedSetupReplyMessageId = nil
        self.closedPinnedMessageId = nil
        self.closedPeerSpecificPackSetup = false
        self.dismissedAddContactPhoneNumber = nil
    }
    
    init(closedButtonKeyboardMessageId: MessageId?, processedSetupReplyMessageId: MessageId?, closedPinnedMessageId: MessageId?, closedPeerSpecificPackSetup: Bool, dismissedAddContactPhoneNumber: String?) {
        self.closedButtonKeyboardMessageId = closedButtonKeyboardMessageId
        self.processedSetupReplyMessageId = processedSetupReplyMessageId
        self.closedPinnedMessageId = closedPinnedMessageId
        self.closedPeerSpecificPackSetup = closedPeerSpecificPackSetup
        self.dismissedAddContactPhoneNumber = dismissedAddContactPhoneNumber
    }
    
    init(decoder: PostboxDecoder) {
        if let closedMessageIdPeerId = decoder.decodeOptionalInt64ForKey("cb.p"), let closedMessageIdNamespace = decoder.decodeOptionalInt32ForKey("cb.n"), let closedMessageIdId = decoder.decodeOptionalInt32ForKey("cb.i") {
            self.closedButtonKeyboardMessageId = MessageId(peerId: PeerId(closedMessageIdPeerId), namespace: closedMessageIdNamespace, id: closedMessageIdId)
        } else {
            self.closedButtonKeyboardMessageId = nil
        }
        
        if let processedMessageIdPeerId = decoder.decodeOptionalInt64ForKey("pb.p"), let processedMessageIdNamespace = decoder.decodeOptionalInt32ForKey("pb.n"), let processedMessageIdId = decoder.decodeOptionalInt32ForKey("pb.i") {
            self.processedSetupReplyMessageId = MessageId(peerId: PeerId(processedMessageIdPeerId), namespace: processedMessageIdNamespace, id: processedMessageIdId)
        } else {
            self.processedSetupReplyMessageId = nil
        }
        
        if let closedPinnedMessageIdPeerId = decoder.decodeOptionalInt64ForKey("cp.p"), let closedPinnedMessageIdNamespace = decoder.decodeOptionalInt32ForKey("cp.n"), let closedPinnedMessageIdId = decoder.decodeOptionalInt32ForKey("cp.i") {
            self.closedPinnedMessageId = MessageId(peerId: PeerId(closedPinnedMessageIdPeerId), namespace: closedPinnedMessageIdNamespace, id: closedPinnedMessageIdId)
        } else {
            self.closedPinnedMessageId = nil
        }
        
        self.closedPeerSpecificPackSetup = decoder.decodeInt32ForKey("cpss", orElse: 0) != 0
    }
    
    func encode(_ encoder: PostboxEncoder) {
        if let closedButtonKeyboardMessageId = self.closedButtonKeyboardMessageId {
            encoder.encodeInt64(closedButtonKeyboardMessageId.peerId.toInt64(), forKey: "cb.p")
            encoder.encodeInt32(closedButtonKeyboardMessageId.namespace, forKey: "cb.n")
            encoder.encodeInt32(closedButtonKeyboardMessageId.id, forKey: "cb.i")
        } else {
            encoder.encodeNil(forKey: "cb.p")
            encoder.encodeNil(forKey: "cb.n")
            encoder.encodeNil(forKey: "cb.i")
        }
        
        if let processedSetupReplyMessageId = self.processedSetupReplyMessageId {
            encoder.encodeInt64(processedSetupReplyMessageId.peerId.toInt64(), forKey: "pb.p")
            encoder.encodeInt32(processedSetupReplyMessageId.namespace, forKey: "pb.n")
            encoder.encodeInt32(processedSetupReplyMessageId.id, forKey: "pb.i")
        } else {
            encoder.encodeNil(forKey: "pb.p")
            encoder.encodeNil(forKey: "pb.n")
            encoder.encodeNil(forKey: "pb.i")
        }
        
        if let closedPinnedMessageId = self.closedPinnedMessageId {
            encoder.encodeInt64(closedPinnedMessageId.peerId.toInt64(), forKey: "cp.p")
            encoder.encodeInt32(closedPinnedMessageId.namespace, forKey: "cp.n")
            encoder.encodeInt32(closedPinnedMessageId.id, forKey: "cp.i")
        } else {
            encoder.encodeNil(forKey: "cp.p")
            encoder.encodeNil(forKey: "cp.n")
            encoder.encodeNil(forKey: "cp.i")
        }
        
        encoder.encodeInt32(self.closedPeerSpecificPackSetup ? 1 : 0, forKey: "cpss")
        
        if let dismissedAddContactPhoneNumber = self.dismissedAddContactPhoneNumber {
            encoder.encodeString(dismissedAddContactPhoneNumber, forKey: "dismissedAddContactPhoneNumber")
        } else {
            encoder.encodeNil(forKey: "dismissedAddContactPhoneNumber")
        }
    }
}

struct ChatInterfaceHistoryScrollState: PostboxCoding, Equatable {
    let messageIndex: MessageIndex
    let relativeOffset: Double
    
    init(messageIndex: MessageIndex, relativeOffset: Double) {
        self.messageIndex = messageIndex
        self.relativeOffset = relativeOffset
    }
    
    init(decoder: PostboxDecoder) {
        self.messageIndex = MessageIndex(id: MessageId(peerId: PeerId(decoder.decodeInt64ForKey("m.p", orElse: 0)), namespace: decoder.decodeInt32ForKey("m.n", orElse: 0), id: decoder.decodeInt32ForKey("m.i", orElse: 0)), timestamp: decoder.decodeInt32ForKey("m.t", orElse: 0))
        self.relativeOffset = decoder.decodeDoubleForKey("ro", orElse: 0.0)
    }
    
    func encode(_ encoder: PostboxEncoder) {
        encoder.encodeInt32(self.messageIndex.timestamp, forKey: "m.t")
        encoder.encodeInt64(self.messageIndex.id.peerId.toInt64(), forKey: "m.p")
        encoder.encodeInt32(self.messageIndex.id.namespace, forKey: "m.n")
        encoder.encodeInt32(self.messageIndex.id.id, forKey: "m.i")
        encoder.encodeDouble(self.relativeOffset, forKey: "ro")
    }
    
    static func ==(lhs: ChatInterfaceHistoryScrollState, rhs: ChatInterfaceHistoryScrollState) -> Bool {
        if lhs.messageIndex != rhs.messageIndex {
            return false
        }
        if !lhs.relativeOffset.isEqual(to: rhs.relativeOffset) {
            return false
        }
        return true
    }
}

public final class ChatInterfaceState: SynchronizeableChatInterfaceState, Equatable {
    let timestamp: Int32
    let composeInputState: ChatTextInputState
    let composeDisableUrlPreview: String?
    let replyMessageId: MessageId?
    let forwardMessageIds: [MessageId]?
    let editMessage: ChatEditMessageState?
    let selectionState: ChatInterfaceSelectionState?
    let messageActionsState: ChatInterfaceMessageActionsState
    let historyScrollState: ChatInterfaceHistoryScrollState?
    let mediaRecordingMode: ChatTextInputMediaRecordingButtonMode
    let silentPosting: Bool
    let forwardAsCopy: Bool
    let inputLanguage: String?
    
    public var associatedMessageIds: [MessageId] {
        var ids: [MessageId] = []
        if let editMessage = self.editMessage {
            ids.append(editMessage.messageId)
        }
        return ids
    }
    
    public var chatListEmbeddedState: PeerChatListEmbeddedInterfaceState? {
        if self.composeInputState.inputText.length != 0 && self.timestamp != 0 {
            return ChatEmbeddedInterfaceState(timestamp: self.timestamp, text: self.composeInputState.inputText)
        } else {
            return nil
        }
    }
    
    public var synchronizeableInputState: SynchronizeableChatInputState? {
        if self.composeInputState.inputText.length == 0 {
            return nil
        } else {
            return SynchronizeableChatInputState(replyToMessageId: self.replyMessageId, text: self.composeInputState.inputText.string, entities: generateChatInputTextEntities(self.composeInputState.inputText), timestamp: self.timestamp)
        }
    }
    
    public var historyScrollMessageIndex: MessageIndex? {
        return self.historyScrollState?.messageIndex
    }
    
    public func withUpdatedSynchronizeableInputState(_ state: SynchronizeableChatInputState?) -> SynchronizeableChatInterfaceState {
        var result = self.withUpdatedComposeInputState(ChatTextInputState(inputText: chatInputStateStringWithAppliedEntities(state?.text ?? "", entities: state?.entities ?? []))).withUpdatedReplyMessageId(state?.replyToMessageId)
        if let timestamp = state?.timestamp {
            result = result.withUpdatedTimestamp(timestamp)
        }
        return result
    }
    
    var effectiveInputState: ChatTextInputState {
        if let editMessage = self.editMessage {
            return editMessage.inputState
        } else {
            return self.composeInputState
        }
    }
    
    public init() {
        self.timestamp = 0
        self.composeInputState = ChatTextInputState()
        self.composeDisableUrlPreview = nil
        self.replyMessageId = nil
        self.forwardMessageIds = nil
        self.editMessage = nil
        self.selectionState = nil
        self.messageActionsState = ChatInterfaceMessageActionsState()
        self.historyScrollState = nil
        self.mediaRecordingMode = .audio
        self.silentPosting = false
        self.forwardAsCopy = false
        self.inputLanguage = nil
    }
    
    init(timestamp: Int32, composeInputState: ChatTextInputState, composeDisableUrlPreview: String?, replyMessageId: MessageId?, forwardMessageIds: [MessageId]?, editMessage: ChatEditMessageState?, selectionState: ChatInterfaceSelectionState?, messageActionsState: ChatInterfaceMessageActionsState, historyScrollState: ChatInterfaceHistoryScrollState?, mediaRecordingMode: ChatTextInputMediaRecordingButtonMode, silentPosting: Bool, forwardAsCopy: Bool = false, inputLanguage: String?) {
        self.timestamp = timestamp
        self.composeInputState = composeInputState
        self.composeDisableUrlPreview = composeDisableUrlPreview
        self.replyMessageId = replyMessageId
        self.forwardMessageIds = forwardMessageIds
        self.editMessage = editMessage
        self.selectionState = selectionState
        self.messageActionsState = messageActionsState
        self.historyScrollState = historyScrollState
        self.mediaRecordingMode = mediaRecordingMode
        self.silentPosting = silentPosting
        self.forwardAsCopy = forwardAsCopy
        self.inputLanguage = inputLanguage
    }
    
    public init(decoder: PostboxDecoder) {
        self.timestamp = decoder.decodeInt32ForKey("ts", orElse: 0)
        if let inputState = decoder.decodeObjectForKey("is", decoder: { return ChatTextInputState(decoder: $0) }) as? ChatTextInputState {
            self.composeInputState = inputState
        } else {
            self.composeInputState = ChatTextInputState()
        }
        if let composeDisableUrlPreview = decoder.decodeOptionalStringForKey("dup") {
            self.composeDisableUrlPreview = composeDisableUrlPreview
        } else {
            self.composeDisableUrlPreview = nil
        }
        let replyMessageIdPeerId: Int64? = decoder.decodeOptionalInt64ForKey("r.p")
        let replyMessageIdNamespace: Int32? = decoder.decodeOptionalInt32ForKey("r.n")
        let replyMessageIdId: Int32? = decoder.decodeOptionalInt32ForKey("r.i")
        if let replyMessageIdPeerId = replyMessageIdPeerId, let replyMessageIdNamespace = replyMessageIdNamespace, let replyMessageIdId = replyMessageIdId {
            self.replyMessageId = MessageId(peerId: PeerId(replyMessageIdPeerId), namespace: replyMessageIdNamespace, id: replyMessageIdId)
        } else {
            self.replyMessageId = nil
        }
        if let forwardMessageIdsData = decoder.decodeBytesForKeyNoCopy("fm") {
            self.forwardMessageIds = MessageId.decodeArrayFromBuffer(forwardMessageIdsData)
        } else {
            self.forwardMessageIds = nil
        }
        if let editMessage = decoder.decodeObjectForKey("em", decoder: { ChatEditMessageState(decoder: $0) }) as? ChatEditMessageState {
            self.editMessage = editMessage
        } else {
            self.editMessage = nil
        }
        if let selectionState = decoder.decodeObjectForKey("ss", decoder: { return ChatInterfaceSelectionState(decoder: $0) }) as? ChatInterfaceSelectionState {
            self.selectionState = selectionState
        } else {
            self.selectionState = nil
        }
        
        if let messageActionsState = decoder.decodeObjectForKey("as", decoder: { ChatInterfaceMessageActionsState(decoder: $0) }) as? ChatInterfaceMessageActionsState {
            self.messageActionsState = messageActionsState
        } else {
            self.messageActionsState = ChatInterfaceMessageActionsState()
        }
        
        self.historyScrollState = decoder.decodeObjectForKey("hss", decoder: { ChatInterfaceHistoryScrollState(decoder: $0) }) as? ChatInterfaceHistoryScrollState
        
        self.mediaRecordingMode = ChatTextInputMediaRecordingButtonMode(rawValue: decoder.decodeInt32ForKey("mrm", orElse: 0))!
        
        self.silentPosting = decoder.decodeInt32ForKey("sip", orElse: 0) != 0
        self.forwardAsCopy = decoder.decodeInt32ForKey("fwdcpy", orElse: 0) != 0
        self.inputLanguage = decoder.decodeOptionalStringForKey("inputLanguage")
    }
    
    public func encode(_ encoder: PostboxEncoder) {
        encoder.encodeInt32(self.timestamp, forKey: "ts")
        encoder.encodeObject(self.composeInputState, forKey: "is")
        if let composeDisableUrlPreview = self.composeDisableUrlPreview {
            encoder.encodeString(composeDisableUrlPreview, forKey: "dup")
        } else {
            encoder.encodeNil(forKey: "dup")
        }
        if let replyMessageId = self.replyMessageId {
            encoder.encodeInt64(replyMessageId.peerId.toInt64(), forKey: "r.p")
            encoder.encodeInt32(replyMessageId.namespace, forKey: "r.n")
            encoder.encodeInt32(replyMessageId.id, forKey: "r.i")
        } else {
            encoder.encodeNil(forKey: "r.p")
            encoder.encodeNil(forKey: "r.n")
            encoder.encodeNil(forKey: "r.i")
        }
        if let forwardMessageIds = self.forwardMessageIds {
            let buffer = WriteBuffer()
            MessageId.encodeArrayToBuffer(forwardMessageIds, buffer: buffer)
            encoder.encodeBytes(buffer, forKey: "fm")
        } else {
            encoder.encodeNil(forKey: "fm")
        }
        if let editMessage = self.editMessage {
            encoder.encodeObject(editMessage, forKey: "em")
        } else {
            encoder.encodeNil(forKey: "em")
        }
        if let selectionState = self.selectionState {
            encoder.encodeObject(selectionState, forKey: "ss")
        } else {
            encoder.encodeNil(forKey: "ss")
        }
        if self.messageActionsState.isEmpty {
            encoder.encodeNil(forKey: "as")
        } else {
            encoder.encodeObject(self.messageActionsState, forKey: "as")
        }
        if let historyScrollState = self.historyScrollState {
            encoder.encodeObject(historyScrollState, forKey: "hss")
        } else {
            encoder.encodeNil(forKey: "hss")
        }
        encoder.encodeInt32(self.mediaRecordingMode.rawValue, forKey: "mrm")
        encoder.encodeInt32(self.silentPosting ? 1 : 0, forKey: "sip")
        encoder.encodeInt32(self.forwardAsCopy ? 1 : 0, forKey: "fwdcpy")
        if let inputLanguage = self.inputLanguage {
            encoder.encodeString(inputLanguage, forKey: "inputLanguage")
        } else {
            encoder.encodeNil(forKey: "inputLanguage")
        }
    }
    
    public func isEqual(to: PeerChatInterfaceState) -> Bool {
        if let to = to as? ChatInterfaceState, self == to {
            return true
        } else {
            return false
        }
    }
    
    public static func ==(lhs: ChatInterfaceState, rhs: ChatInterfaceState) -> Bool {
        if lhs.composeDisableUrlPreview != rhs.composeDisableUrlPreview {
            return false
        }
        if let lhsForwardMessageIds = lhs.forwardMessageIds, let rhsForwardMessageIds = rhs.forwardMessageIds {
            if lhsForwardMessageIds != rhsForwardMessageIds {
                return false
            }
        } else if (lhs.forwardMessageIds != nil) != (rhs.forwardMessageIds != nil) {
            return false
        }
        if lhs.messageActionsState != rhs.messageActionsState {
            return false
        }
        if lhs.historyScrollState != rhs.historyScrollState {
            return false
        }
        if lhs.mediaRecordingMode != rhs.mediaRecordingMode {
            return false
        }
        if lhs.silentPosting != rhs.silentPosting {
            return false
        }
        if lhs.forwardAsCopy != rhs.forwardAsCopy {
            return false
        }
        if lhs.inputLanguage != rhs.inputLanguage {
            return false
        }
        return lhs.composeInputState == rhs.composeInputState && lhs.replyMessageId == rhs.replyMessageId && lhs.selectionState == rhs.selectionState && lhs.editMessage == rhs.editMessage
    }
    
    func withUpdatedComposeInputState(_ inputState: ChatTextInputState) -> ChatInterfaceState {
        let updatedComposeInputState = inputState
        
        return ChatInterfaceState(timestamp: self.timestamp, composeInputState: updatedComposeInputState, composeDisableUrlPreview: self.composeDisableUrlPreview, replyMessageId: self.replyMessageId, forwardMessageIds: self.forwardMessageIds, editMessage: self.editMessage, selectionState: self.selectionState, messageActionsState: self.messageActionsState, historyScrollState: self.historyScrollState, mediaRecordingMode: self.mediaRecordingMode, silentPosting: self.silentPosting, forwardAsCopy: self.forwardAsCopy, inputLanguage: self.inputLanguage)
    }
    
    func withUpdatedComposeDisableUrlPreview(_ disableUrlPreview: String?) -> ChatInterfaceState {
        return ChatInterfaceState(timestamp: self.timestamp, composeInputState: self.composeInputState, composeDisableUrlPreview: disableUrlPreview, replyMessageId: self.replyMessageId, forwardMessageIds: self.forwardMessageIds, editMessage: self.editMessage, selectionState: self.selectionState, messageActionsState: self.messageActionsState, historyScrollState: self.historyScrollState, mediaRecordingMode: self.mediaRecordingMode, silentPosting: self.silentPosting, forwardAsCopy: self.forwardAsCopy, inputLanguage: self.inputLanguage)
    }
    
    func withUpdatedEffectiveInputState(_ inputState: ChatTextInputState) -> ChatInterfaceState {
        var updatedEditMessage = self.editMessage
        var updatedComposeInputState = self.composeInputState
        if let editMessage = self.editMessage {
            updatedEditMessage = editMessage.withUpdatedInputState(inputState)
        } else {
            updatedComposeInputState = inputState
        }
        
        return ChatInterfaceState(timestamp: self.timestamp, composeInputState: updatedComposeInputState, composeDisableUrlPreview: self.composeDisableUrlPreview, replyMessageId: self.replyMessageId, forwardMessageIds: self.forwardMessageIds, editMessage: updatedEditMessage, selectionState: self.selectionState, messageActionsState: self.messageActionsState, historyScrollState: self.historyScrollState, mediaRecordingMode: self.mediaRecordingMode, silentPosting: self.silentPosting, forwardAsCopy: self.forwardAsCopy, inputLanguage: self.inputLanguage)
    }
    
    func withUpdatedReplyMessageId(_ replyMessageId: MessageId?) -> ChatInterfaceState {
        return ChatInterfaceState(timestamp: self.timestamp, composeInputState: self.composeInputState, composeDisableUrlPreview: self.composeDisableUrlPreview, replyMessageId: replyMessageId, forwardMessageIds: self.forwardMessageIds, editMessage: self.editMessage, selectionState: self.selectionState, messageActionsState: self.messageActionsState, historyScrollState: self.historyScrollState, mediaRecordingMode: self.mediaRecordingMode, silentPosting: self.silentPosting, forwardAsCopy: self.forwardAsCopy, inputLanguage: self.inputLanguage)
    }
    
    func withUpdatedForwardMessageIds(_ forwardMessageIds: [MessageId]?) -> ChatInterfaceState {
        return ChatInterfaceState(timestamp: self.timestamp, composeInputState: self.composeInputState, composeDisableUrlPreview: self.composeDisableUrlPreview, replyMessageId: self.replyMessageId, forwardMessageIds: forwardMessageIds, editMessage: self.editMessage, selectionState: self.selectionState, messageActionsState: self.messageActionsState, historyScrollState: self.historyScrollState, mediaRecordingMode: self.mediaRecordingMode, silentPosting: self.silentPosting, forwardAsCopy: self.forwardAsCopy, inputLanguage: self.inputLanguage)
    }
    
    func withUpdatedSelectedMessages(_ messageIds: [MessageId]) -> ChatInterfaceState {
        var selectedIds = Set<MessageId>()
        if let selectionState = self.selectionState {
            selectedIds.formUnion(selectionState.selectedIds)
        }
        for messageId in messageIds {
            selectedIds.insert(messageId)
        }
        return ChatInterfaceState(timestamp: self.timestamp, composeInputState: self.composeInputState, composeDisableUrlPreview: self.composeDisableUrlPreview, replyMessageId: self.replyMessageId, forwardMessageIds: self.forwardMessageIds, editMessage: self.editMessage, selectionState: ChatInterfaceSelectionState(selectedIds: selectedIds), messageActionsState: self.messageActionsState, historyScrollState: self.historyScrollState, mediaRecordingMode: self.mediaRecordingMode, silentPosting: self.silentPosting, forwardAsCopy: self.forwardAsCopy, inputLanguage: self.inputLanguage)
    }
    
    func withToggledSelectedMessages(_ messageIds: [MessageId], value: Bool) -> ChatInterfaceState {
        var selectedIds = Set<MessageId>()
        if let selectionState = self.selectionState {
            selectedIds.formUnion(selectionState.selectedIds)
        }
        for messageId in messageIds {
            if value {
                selectedIds.insert(messageId)
            } else {
                selectedIds.remove(messageId)
            }
        }
        return ChatInterfaceState(timestamp: self.timestamp, composeInputState: self.composeInputState, composeDisableUrlPreview: self.composeDisableUrlPreview, replyMessageId: self.replyMessageId, forwardMessageIds: self.forwardMessageIds, editMessage: self.editMessage, selectionState: ChatInterfaceSelectionState(selectedIds: selectedIds), messageActionsState: self.messageActionsState, historyScrollState: self.historyScrollState, mediaRecordingMode: self.mediaRecordingMode, silentPosting: self.silentPosting, forwardAsCopy: self.forwardAsCopy, inputLanguage: self.inputLanguage)
    }
    
    func withoutSelectionState() -> ChatInterfaceState {
        return ChatInterfaceState(timestamp: self.timestamp, composeInputState: self.composeInputState, composeDisableUrlPreview: self.composeDisableUrlPreview, replyMessageId: self.replyMessageId, forwardMessageIds: self.forwardMessageIds, editMessage: self.editMessage, selectionState: nil, messageActionsState: self.messageActionsState, historyScrollState: self.historyScrollState, mediaRecordingMode: self.mediaRecordingMode, silentPosting: self.silentPosting, forwardAsCopy: self.forwardAsCopy, inputLanguage: self.inputLanguage)
    }
    
    func withUpdatedTimestamp(_ timestamp: Int32) -> ChatInterfaceState {
        return ChatInterfaceState(timestamp: timestamp, composeInputState: self.composeInputState, composeDisableUrlPreview: self.composeDisableUrlPreview, replyMessageId: self.replyMessageId, forwardMessageIds: self.forwardMessageIds, editMessage: self.editMessage, selectionState: self.selectionState, messageActionsState: self.messageActionsState, historyScrollState: self.historyScrollState, mediaRecordingMode: self.mediaRecordingMode, silentPosting: self.silentPosting, forwardAsCopy: self.forwardAsCopy, inputLanguage: self.inputLanguage)
    }
    
    func withUpdatedEditMessage(_ editMessage: ChatEditMessageState?) -> ChatInterfaceState {
        return ChatInterfaceState(timestamp: self.timestamp, composeInputState: self.composeInputState, composeDisableUrlPreview: self.composeDisableUrlPreview, replyMessageId: self.replyMessageId, forwardMessageIds: self.forwardMessageIds, editMessage: editMessage, selectionState: self.selectionState, messageActionsState: self.messageActionsState, historyScrollState: self.historyScrollState, mediaRecordingMode: self.mediaRecordingMode, silentPosting: self.silentPosting, forwardAsCopy: self.forwardAsCopy, inputLanguage: self.inputLanguage)
    }
    
    func withUpdatedMessageActionsState(_ f: (ChatInterfaceMessageActionsState) -> ChatInterfaceMessageActionsState) -> ChatInterfaceState {
        return ChatInterfaceState(timestamp: self.timestamp, composeInputState: self.composeInputState, composeDisableUrlPreview: self.composeDisableUrlPreview, replyMessageId: self.replyMessageId, forwardMessageIds: self.forwardMessageIds, editMessage: self.editMessage, selectionState: self.selectionState, messageActionsState: f(self.messageActionsState), historyScrollState: self.historyScrollState, mediaRecordingMode: self.mediaRecordingMode, silentPosting: self.silentPosting, forwardAsCopy: self.forwardAsCopy, inputLanguage: self.inputLanguage)
    }
    
    func withUpdatedHistoryScrollState(_ historyScrollState: ChatInterfaceHistoryScrollState?) -> ChatInterfaceState {
        return ChatInterfaceState(timestamp: self.timestamp, composeInputState: self.composeInputState, composeDisableUrlPreview: self.composeDisableUrlPreview, replyMessageId: self.replyMessageId, forwardMessageIds: self.forwardMessageIds, editMessage: self.editMessage, selectionState: self.selectionState, messageActionsState: self.messageActionsState, historyScrollState: historyScrollState, mediaRecordingMode: self.mediaRecordingMode, silentPosting: self.silentPosting, forwardAsCopy: self.forwardAsCopy, inputLanguage: self.inputLanguage)
    }
    
    func withUpdatedMediaRecordingMode(_ mediaRecordingMode: ChatTextInputMediaRecordingButtonMode) -> ChatInterfaceState {
        return ChatInterfaceState(timestamp: self.timestamp, composeInputState: self.composeInputState, composeDisableUrlPreview: self.composeDisableUrlPreview, replyMessageId: self.replyMessageId, forwardMessageIds: self.forwardMessageIds, editMessage: self.editMessage, selectionState: self.selectionState, messageActionsState: self.messageActionsState, historyScrollState: self.historyScrollState, mediaRecordingMode: mediaRecordingMode, silentPosting: self.silentPosting, forwardAsCopy: self.forwardAsCopy, inputLanguage: self.inputLanguage)
    }
    
    public func withUpdatedSilentPosting(_ silentPosting: Bool) -> ChatInterfaceState {
        return ChatInterfaceState(timestamp: self.timestamp, composeInputState: self.composeInputState, composeDisableUrlPreview: self.composeDisableUrlPreview, replyMessageId: self.replyMessageId, forwardMessageIds: self.forwardMessageIds, editMessage: self.editMessage, selectionState: self.selectionState, messageActionsState: self.messageActionsState, historyScrollState: self.historyScrollState, mediaRecordingMode: self.mediaRecordingMode, silentPosting: silentPosting, forwardAsCopy: self.forwardAsCopy, inputLanguage: self.inputLanguage)
    }
    
    public func withUpdatedInputLanguage(_ inputLanguage: String?) -> ChatInterfaceState {
        return ChatInterfaceState(timestamp: self.timestamp, composeInputState: self.composeInputState, composeDisableUrlPreview: self.composeDisableUrlPreview, replyMessageId: self.replyMessageId, forwardMessageIds: self.forwardMessageIds, editMessage: self.editMessage, selectionState: self.selectionState, messageActionsState: self.messageActionsState, historyScrollState: self.historyScrollState, mediaRecordingMode: self.mediaRecordingMode, silentPosting: self.silentPosting, forwardAsCopy: self.forwardAsCopy, inputLanguage: inputLanguage)
    }
    
    public func withUpdatedForwardAsCopy(_ forwardAsCopy: Bool) -> ChatInterfaceState {
        return ChatInterfaceState(timestamp: self.timestamp, composeInputState: self.composeInputState, composeDisableUrlPreview: self.composeDisableUrlPreview, replyMessageId: self.replyMessageId, forwardMessageIds: self.forwardMessageIds, editMessage: self.editMessage, selectionState: self.selectionState, messageActionsState: self.messageActionsState, historyScrollState: self.historyScrollState, mediaRecordingMode: self.mediaRecordingMode, silentPosting: self.silentPosting, forwardAsCopy: forwardAsCopy, inputLanguage: self.inputLanguage)
    }
}
