import Foundation
import UIKit
import TelegramCore

func chatInputStateStringWithAppliedEntities(_ text: String, entities: [MessageTextEntity]) -> NSAttributedString {
    var nsString: NSString?
    let string = NSMutableAttributedString(string: text)
    var skipEntity = false
    let stringLength = string.length
    for i in 0 ..< entities.count {
        if skipEntity {
            skipEntity = false
            continue
        }
        let entity = entities[i]
        var range = NSRange(location: entity.range.lowerBound, length: entity.range.upperBound - entity.range.lowerBound)
        if nsString == nil {
            nsString = text as NSString
        }
        if range.location + range.length > stringLength {
            range.location = max(0, stringLength - range.length)
            range.length = stringLength - range.location
        }
        switch entity.type {
            case .Url, .Email, .PhoneNumber, .Mention, .Hashtag, .BotCommand:
                break
            case .Bold:
                string.addAttribute(ChatTextInputAttributes.bold, value: true as NSNumber, range: range)
            case .Italic:
                string.addAttribute(ChatTextInputAttributes.italic, value: true as NSNumber, range: range)
            case let .TextMention(peerId):
                string.addAttribute(ChatTextInputAttributes.textMention, value: ChatTextInputTextMentionAttribute(peerId: peerId), range: range)
            case let .TextUrl(url):
                string.addAttribute(ChatTextInputAttributes.textUrl, value: ChatTextInputTextUrlAttribute(url: url), range: range)
            case .Code, .Pre:
                string.addAttribute(ChatTextInputAttributes.monospace, value: true as NSNumber, range: range)
            case .Strikethrough:
                string.addAttribute(ChatTextInputAttributes.strikethrough, value: true as NSNumber, range: range)
            case .Underline:
                string.addAttribute(ChatTextInputAttributes.underline, value: true as NSNumber, range: range)
            default:
                break
        }
    }
    return string
}

func stringWithAppliedEntities(_ text: String, entities: [MessageTextEntity], baseColor: UIColor, linkColor: UIColor, baseFont: UIFont, linkFont: UIFont, boldFont: UIFont, italicFont: UIFont, boldItalicFont: UIFont, fixedFont: UIFont, blockQuoteFont: UIFont, underlineLinks: Bool = true, external: Bool = false) -> NSAttributedString {
    var nsString: NSString?
    let string = NSMutableAttributedString(string: text, attributes: [NSAttributedStringKey.font: baseFont, NSAttributedStringKey.foregroundColor: baseColor])
    var skipEntity = false
    var underlineAllLinks = false
    if linkColor.isEqual(baseColor) {
        underlineAllLinks = true
    }
    var fontAttributes: [NSRange: ChatTextFontAttributes] = [:]
    
    var rangeOffset: Int = 0
    for i in 0 ..< entities.count {
        if skipEntity {
            skipEntity = false
            continue
        }
        let stringLength = string.length
        let entity = entities[i]
        var range = NSRange(location: entity.range.lowerBound + rangeOffset, length: entity.range.upperBound - entity.range.lowerBound)
        if nsString == nil {
            nsString = text as NSString
        }
        if range.location + range.length > stringLength {
            range.location = max(0, stringLength - range.length)
            range.length = stringLength - range.location
        }
        switch entity.type {
            case .Url:
                string.addAttribute(NSAttributedStringKey.foregroundColor, value: linkColor, range: range)
                if underlineLinks {
                    string.addAttribute(NSAttributedStringKey.underlineStyle, value: NSUnderlineStyle.styleSingle.rawValue as NSNumber, range: range)
                }
                if nsString == nil {
                    nsString = text as NSString
                }
                string.addAttribute(NSAttributedStringKey(rawValue: TelegramTextAttributes.URL), value: nsString!.substring(with: range), range: range)
            case .Email:
                string.addAttribute(NSAttributedStringKey.foregroundColor, value: linkColor, range: range)
                if nsString == nil {
                    nsString = text as NSString
                }
                if underlineLinks && underlineAllLinks {
                    string.addAttribute(NSAttributedStringKey.underlineStyle, value: NSUnderlineStyle.styleSingle.rawValue as NSNumber, range: range)
                }
                string.addAttribute(NSAttributedStringKey(rawValue: TelegramTextAttributes.URL), value: "mailto:\(nsString!.substring(with: range))", range: range)
            case .PhoneNumber:
                string.addAttribute(NSAttributedStringKey.foregroundColor, value: linkColor, range: range)
                if nsString == nil {
                    nsString = text as NSString
                }
                if underlineLinks && underlineAllLinks {
                    string.addAttribute(NSAttributedStringKey.underlineStyle, value: NSUnderlineStyle.styleSingle.rawValue as NSNumber, range: range)
                }
                string.addAttribute(NSAttributedStringKey(rawValue: TelegramTextAttributes.URL), value: "tel:\(nsString!.substring(with: range))", range: range)
            case let .TextUrl(url):
                string.addAttribute(NSAttributedStringKey.foregroundColor, value: linkColor, range: range)
                if nsString == nil {
                    nsString = text as NSString
                }
                if underlineLinks && underlineAllLinks {
                    string.addAttribute(NSAttributedStringKey.underlineStyle, value: NSUnderlineStyle.styleSingle.rawValue as NSNumber, range: range)
                }
                if external {
                    string.addAttribute(NSAttributedStringKey.link, value: url, range: range)
                } else {
                    string.addAttribute(NSAttributedStringKey(rawValue: TelegramTextAttributes.URL), value: url, range: range)
                }
            case .Bold:
                if let fontAttribute = fontAttributes[range] {
                    fontAttributes[range] = fontAttribute.union(.bold)
                } else {
                    fontAttributes[range] = .bold
                }
            case .Italic:
                if let fontAttribute = fontAttributes[range] {
                    fontAttributes[range] = fontAttribute.union(.italic)
                } else {
                    fontAttributes[range] = .italic
                }
            case .Mention:
                string.addAttribute(NSAttributedStringKey.foregroundColor, value: linkColor, range: range)
                if underlineLinks && underlineAllLinks {
                    string.addAttribute(NSAttributedStringKey.underlineStyle, value: NSUnderlineStyle.styleSingle.rawValue as NSNumber, range: range)
                }
                if linkFont !== baseFont {
                    string.addAttribute(NSAttributedStringKey.font, value: linkFont, range: range)
                }
                if nsString == nil {
                    nsString = text as NSString
                }
                string.addAttribute(NSAttributedStringKey(rawValue: TelegramTextAttributes.PeerTextMention), value: nsString!.substring(with: range), range: range)
            case .Strikethrough:
                string.addAttribute(NSAttributedStringKey.strikethroughStyle, value: NSUnderlineStyle.styleSingle.rawValue as NSNumber, range: range)
            case .Underline:
                string.addAttribute(NSAttributedStringKey.underlineStyle, value: NSUnderlineStyle.styleSingle.rawValue as NSNumber, range: range)
            case let .TextMention(peerId):
                string.addAttribute(NSAttributedStringKey.foregroundColor, value: linkColor, range: range)
                if underlineLinks && underlineAllLinks {
                    string.addAttribute(NSAttributedStringKey.underlineStyle, value: NSUnderlineStyle.styleSingle.rawValue as NSNumber, range: range)
                }
                if linkFont !== baseFont {
                    string.addAttribute(NSAttributedStringKey.font, value: linkFont, range: range)
                }
                let mention = nsString!.substring(with: range)
                string.addAttribute(NSAttributedStringKey(rawValue: TelegramTextAttributes.PeerMention), value: TelegramPeerMention(peerId: peerId, mention: mention), range: range)
            case .Hashtag:
                if nsString == nil {
                    nsString = text as NSString
                }
                let hashtag = nsString!.substring(with: range)
                if i + 1 != entities.count {
                    if case .Mention = entities[i + 1].type {
                        let nextRange = NSRange(location: entities[i + 1].range.lowerBound, length: entities[i + 1].range.upperBound - entities[i + 1].range.lowerBound)
                        if nextRange.location == range.location + range.length + 1 && nsString!.character(at: range.location + range.length) == 43 {
                            let peerName: String = nsString!.substring(with: NSRange(location: nextRange.location + 1, length: nextRange.length - 1))
                            
                            skipEntity = true
                            let combinedRange = NSRange(location: range.location, length: nextRange.location + nextRange.length - range.location)
                            string.addAttribute(NSAttributedStringKey.foregroundColor, value: linkColor, range: combinedRange)
                            if linkColor.isEqual(baseColor) {
                                string.addAttribute(NSAttributedStringKey.underlineStyle, value: NSUnderlineStyle.styleSingle.rawValue as NSNumber, range: combinedRange)
                            }
                            string.addAttribute(NSAttributedStringKey(rawValue: TelegramTextAttributes.Hashtag), value: TelegramHashtag(peerName: peerName, hashtag: hashtag), range: combinedRange)
                        }
                    }
                }
                if !skipEntity {
                    string.addAttribute(NSAttributedStringKey.foregroundColor, value: linkColor, range: range)
                    if underlineLinks && underlineAllLinks {
                        string.addAttribute(NSAttributedStringKey.underlineStyle, value: NSUnderlineStyle.styleSingle.rawValue as NSNumber, range: range)
                    }
                    string.addAttribute(NSAttributedStringKey(rawValue: TelegramTextAttributes.Hashtag), value: TelegramHashtag(peerName: nil, hashtag: hashtag), range: range)
                }
            case .BotCommand:
                string.addAttribute(NSAttributedStringKey.foregroundColor, value: linkColor, range: range)
                if underlineLinks && underlineAllLinks {
                    string.addAttribute(NSAttributedStringKey.underlineStyle, value: NSUnderlineStyle.styleSingle.rawValue as NSNumber, range: range)
                }
                if nsString == nil {
                    nsString = text as NSString
                }
                string.addAttribute(NSAttributedStringKey(rawValue: TelegramTextAttributes.BotCommand), value: nsString!.substring(with: range), range: range)
            case .Pre:
                string.addAttribute(NSAttributedStringKey.font, value: fixedFont, range: range)
                if nsString == nil {
                    nsString = text as NSString
                }
                string.addAttribute(NSAttributedStringKey(rawValue: TelegramTextAttributes.Pre), value: nsString!.substring(with: range), range: range)
            case .Code:
                string.addAttribute(NSAttributedStringKey.font, value: fixedFont, range: range)
                if nsString == nil {
                    nsString = text as NSString
                }
                string.addAttribute(NSAttributedStringKey(rawValue: TelegramTextAttributes.Code), value: nsString!.substring(with: range), range: range)            
            case .BlockQuote:
                if let fontAttribute = fontAttributes[range] {
                    fontAttributes[range] = fontAttribute.union(.blockQuote)
                } else {
                    fontAttributes[range] = .blockQuote
                }
                
                let paragraphBreak = "\n"
                string.insert(NSAttributedString(string: paragraphBreak), at: range.lowerBound)
            
                let paragraphRange = NSRange(location: range.lowerBound + paragraphBreak.count, length: range.upperBound - range.lowerBound)
                
                let paragraphStyle = NSMutableParagraphStyle()
                paragraphStyle.headIndent = 10.0
                paragraphStyle.tabStops = [NSTextTab(textAlignment: .left, location: paragraphStyle.headIndent, options: [:])]
                string.addAttribute(NSAttributedStringKey.paragraphStyle, value: paragraphStyle, range: paragraphRange)
            
                string.insert(NSAttributedString(string: paragraphBreak), at: paragraphRange.upperBound)
                rangeOffset += paragraphBreak.count
            case let .Custom(type):
                if type == ApplicationSpecificEntityType.Timecode {
                    string.addAttribute(NSAttributedStringKey.foregroundColor, value: linkColor, range: range)
                    if underlineLinks && underlineAllLinks {
                        string.addAttribute(NSAttributedStringKey.underlineStyle, value: NSUnderlineStyle.styleSingle.rawValue as NSNumber, range: range)
                    }
                    if nsString == nil {
                        nsString = text as NSString
                    }
                    let text = nsString!.substring(with: range)
                    if let time = parseTimecodeString(text) {
                        string.addAttribute(NSAttributedStringKey(rawValue: TelegramTextAttributes.Timecode), value: TelegramTimecode(time: time, text: text), range: range)
                    }
                }
            default:
                break
        }
        
        for (range, fontAttributes) in fontAttributes {
            var font: UIFont?
            if fontAttributes.contains(.blockQuote) {
                font = blockQuoteFont
            } else if fontAttributes == [.bold, .italic] {
                font = boldItalicFont
            } else if fontAttributes == [.bold] {
                font = boldFont
            } else if fontAttributes == [.italic] {
                font = italicFont
            }
            if let font = font {
                string.addAttribute(NSAttributedStringKey.font, value: font, range: range)
            }
        }
    }
    return string
}
