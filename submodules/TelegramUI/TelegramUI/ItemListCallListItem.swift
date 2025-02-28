import Foundation
import UIKit
import Display
import AsyncDisplayKit
import SwiftSignalKit
import Postbox
import TelegramCore
import TelegramPresentationData

class ItemListCallListItem: ListViewItem, ItemListItem {
    let theme: PresentationTheme
    let strings: PresentationStrings
    let dateTimeFormat: PresentationDateTimeFormat
    let messages: [Message]
    let sectionId: ItemListSectionId
    let style: ItemListStyle
    
    init(theme: PresentationTheme, strings: PresentationStrings, dateTimeFormat: PresentationDateTimeFormat, messages: [Message], sectionId: ItemListSectionId, style: ItemListStyle) {
        self.theme = theme
        self.strings = strings
        self.dateTimeFormat = dateTimeFormat
        self.messages = messages
        self.sectionId = sectionId
        self.style = style
    }
    
    func nodeConfiguredForParams(async: @escaping (@escaping () -> Void) -> Void, params: ListViewItemLayoutParams, synchronousLoads: Bool, previousItem: ListViewItem?, nextItem: ListViewItem?, completion: @escaping (ListViewItemNode, @escaping () -> (Signal<Void, NoError>?, (ListViewItemApply) -> Void)) -> Void) {
        async {
            let node = ItemListCallListItemNode()
            let (layout, apply) = node.asyncLayout()(self, params, itemListNeighbors(item: self, topItem: previousItem as? ItemListItem, bottomItem: nextItem as? ItemListItem))
            
            node.contentSize = layout.contentSize
            node.insets = layout.insets
            
            Queue.mainQueue().async {
                completion(node, {
                    return (nil, { _ in apply() })
                })
            }
        }
    }
    
    func updateNode(async: @escaping (@escaping () -> Void) -> Void, node: @escaping () -> ListViewItemNode, params: ListViewItemLayoutParams, previousItem: ListViewItem?, nextItem: ListViewItem?, animation: ListViewItemUpdateAnimation, completion: @escaping (ListViewItemNodeLayout, @escaping (ListViewItemApply) -> Void) -> Void) {
        Queue.mainQueue().async {
            if let nodeValue = node() as? ItemListCallListItemNode {
                let makeLayout = nodeValue.asyncLayout()
                
                async {
                    let (layout, apply) = makeLayout(self, params, itemListNeighbors(item: self, topItem: previousItem as? ItemListItem, bottomItem: nextItem as? ItemListItem))
                    Queue.mainQueue().async {
                        completion(layout, { _ in
                            apply()
                        })
                    }
                }
            }
        }
    }
}

private let titleFont = Font.regular(15.0)
private let font = Font.regular(14.0)
private let typeFont = Font.medium(14.0)

private func stringForCallType(message: Message, strings: PresentationStrings) -> String {
    var string = ""
    for media in message.media {
        switch media {
            case let action as TelegramMediaAction:
                switch action.action {
                    case let .phoneCall(_, discardReason, _):
                        let incoming = message.flags.contains(.Incoming)
                        if let discardReason = discardReason {
                            switch discardReason {
                            case .busy, .disconnect:
                                string = strings.Notification_CallCanceled
                            case .missed:
                                string = incoming ? strings.Notification_CallMissed : strings.Notification_CallCanceled
                            case .hangup:
                                break
                            }
                        }
                        
                        if string.isEmpty {
                            if incoming {
                                string = strings.Notification_CallIncoming
                            } else {
                                string = strings.Notification_CallOutgoing
                            }
                        }
                    default:
                        break
                }
                    
            default:
                break
        }
    }
    return string
}

class ItemListCallListItemNode: ListViewItemNode {
    private let backgroundNode: ASDisplayNode
    private let topStripeNode: ASDisplayNode
    private let bottomStripeNode: ASDisplayNode
    
    let titleNode: TextNode
    var callNodes: [(TextNode, TextNode)]
    
    private var item: ItemListCallListItem?
    
    override var canBeSelected: Bool {
        return false
    }
    
    init() {
        self.backgroundNode = ASDisplayNode()
        self.backgroundNode.isLayerBacked = true
        self.backgroundNode.backgroundColor = .white
        
        self.topStripeNode = ASDisplayNode()
        self.topStripeNode.isLayerBacked = true
        
        self.bottomStripeNode = ASDisplayNode()
        self.bottomStripeNode.isLayerBacked = true
    
        self.titleNode = TextNode()
        self.titleNode.isUserInteractionEnabled = false
        
        self.callNodes = []
        
        super.init(layerBacked: false, dynamicBounce: false)
        
        self.addSubnode(self.titleNode)
    }
    
    func asyncLayout() -> (_ item: ItemListCallListItem, _ params: ListViewItemLayoutParams, _ insets: ItemListNeighbors) -> (ListViewItemNodeLayout, () -> Void) {
        let makeTitleLayout = TextNode.asyncLayout(self.titleNode)
        let currentItem = self.item
        
        return { item, params, neighbors in
            if self.callNodes.count != item.messages.count {
                for pair in self.callNodes {
                    pair.0.removeFromSupernode()
                    pair.1.removeFromSupernode()
                }
                
                self.callNodes = []
                
                for _ in item.messages {
                    let timeNode = TextNode()
                    timeNode.isUserInteractionEnabled = false
                    self.addSubnode(timeNode)
                    
                    let typeNode = TextNode()
                    typeNode.isUserInteractionEnabled = false
                    self.addSubnode(typeNode)
                    
                    self.callNodes.append((timeNode, typeNode))
                }
            }
            
            var makeNodesLayout: [((TextNodeLayoutArguments) -> (TextNodeLayout, () -> TextNode), (TextNodeLayoutArguments) -> (TextNodeLayout, () -> TextNode))] = []
            for nodes in self.callNodes {
                let makeTimeLayout = TextNode.asyncLayout(nodes.0)
                let makeTypeLayout = TextNode.asyncLayout(nodes.1)
                makeNodesLayout.append((makeTimeLayout, makeTypeLayout))
            }
    
            var updatedTheme: PresentationTheme?
            
            if currentItem?.theme !== item.theme {
                updatedTheme = item.theme
            }
            
            let contentSize: CGSize
            var contentHeight: CGFloat = 0.0
            let insets: UIEdgeInsets
            let separatorHeight = UIScreenPixel
            let itemBackgroundColor: UIColor
            let itemSeparatorColor: UIColor
            
            let leftInset = 16.0 + params.leftInset
            
            switch item.style {
                case .plain:
                    itemBackgroundColor = item.theme.list.plainBackgroundColor
                    itemSeparatorColor = item.theme.list.itemPlainSeparatorColor
                    insets = itemListNeighborsPlainInsets(neighbors)
                case .blocks:
                    itemBackgroundColor = item.theme.list.itemBlocksBackgroundColor
                    itemSeparatorColor = item.theme.list.itemBlocksSeparatorColor
                    insets = itemListNeighborsGroupedInsets(neighbors)
            }
            
            let earliestMessage = item.messages.sorted(by: {$0.timestamp < $1.timestamp}).first!
            let titleText = stringForDate(timestamp: earliestMessage.timestamp, strings: item.strings)
            let (titleLayout, titleApply) = makeTitleLayout(TextNodeLayoutArguments(attributedString: NSAttributedString(string: titleText, font: titleFont, textColor: item.theme.list.itemPrimaryTextColor), backgroundColor: nil, maximumNumberOfLines: 1, truncationType: .end, constrainedSize: CGSize(width: params.width - params.rightInset - 20.0 - leftInset, height: CGFloat.greatestFiniteMagnitude), alignment: .natural, cutout: nil, insets: UIEdgeInsets()))
            
            contentHeight += titleLayout.size.height + 18.0
            
            var index = 0
            var nodesLayout: [(TextNodeLayout, TextNodeLayout)] = []
            var nodesApply: [(() -> TextNode, () -> TextNode)] = []
            for message in item.messages {
                let makeTimeLayout = makeNodesLayout[index].0
                let time = stringForMessageTimestamp(timestamp: message.timestamp, dateTimeFormat: item.dateTimeFormat)
                let (timeLayout, timeApply) = makeTimeLayout(TextNodeLayoutArguments(attributedString: NSAttributedString(string: time, font: font, textColor: item.theme.list.itemPrimaryTextColor), backgroundColor: nil, maximumNumberOfLines: 1, truncationType: .end, constrainedSize: CGSize(width: params.width - params.rightInset - 20.0 - leftInset, height: CGFloat.greatestFiniteMagnitude), alignment: .natural, cutout: nil, insets: UIEdgeInsets()))
                
                let makeTypeLayout = makeNodesLayout[index].1
                let type = stringForCallType(message: message, strings: item.strings)
                let (typeLayout, typeApply) = makeTypeLayout(TextNodeLayoutArguments(attributedString: NSAttributedString(string: type, font: typeFont, textColor: item.theme.list.itemPrimaryTextColor), backgroundColor: nil, maximumNumberOfLines: 1, truncationType: .end, constrainedSize: CGSize(width: params.width - params.rightInset - 20.0 - leftInset, height: CGFloat.greatestFiniteMagnitude), alignment: .natural, cutout: nil, insets: UIEdgeInsets()))
                
                nodesLayout.append((timeLayout, typeLayout))
                nodesApply.append((timeApply, typeApply))
             
                contentHeight += timeLayout.size.height + 12.0
                
                index += 1
            }
            
            contentSize = CGSize(width: params.width, height: contentHeight)
            
            let layout = ListViewItemNodeLayout(contentSize: contentSize, insets: insets)
            
            return (layout, { [weak self] in
                if let strongSelf = self {
                    strongSelf.item = item
                    
                    if let _ = updatedTheme {
                        strongSelf.topStripeNode.backgroundColor = itemSeparatorColor
                        strongSelf.bottomStripeNode.backgroundColor = itemSeparatorColor
                        strongSelf.backgroundNode.backgroundColor = itemBackgroundColor
                    }
                    
                    let _ = titleApply()
                    
                    for apply in nodesApply {
                        let _ = apply.0()
                        let _ = apply.1()
                    }
                    
                    switch item.style {
                    case .plain:
                        if strongSelf.backgroundNode.supernode != nil {
                            strongSelf.backgroundNode.removeFromSupernode()
                        }
                        if strongSelf.topStripeNode.supernode != nil {
                            strongSelf.topStripeNode.removeFromSupernode()
                        }
                        if strongSelf.bottomStripeNode.supernode == nil {
                            strongSelf.insertSubnode(strongSelf.bottomStripeNode, at: 0)
                        }
                        
                        strongSelf.bottomStripeNode.frame = CGRect(origin: CGPoint(x: leftInset, y: contentSize.height - separatorHeight), size: CGSize(width: params.width - leftInset, height: separatorHeight))
                    case .blocks:
                        if strongSelf.backgroundNode.supernode == nil {
                            strongSelf.insertSubnode(strongSelf.backgroundNode, at: 0)
                        }
                        if strongSelf.topStripeNode.supernode == nil {
                            strongSelf.insertSubnode(strongSelf.topStripeNode, at: 1)
                        }
                        if strongSelf.bottomStripeNode.supernode == nil {
                            strongSelf.insertSubnode(strongSelf.bottomStripeNode, at: 2)
                        }
                        switch neighbors.top {
                        case .sameSection(false):
                            strongSelf.topStripeNode.isHidden = true
                        default:
                            strongSelf.topStripeNode.isHidden = false
                        }
                        let bottomStripeInset: CGFloat
                        switch neighbors.bottom {
                        case .sameSection(false):
                            bottomStripeInset = leftInset
                        default:
                            bottomStripeInset = 0.0
                        }
                        
                        strongSelf.backgroundNode.frame = CGRect(origin: CGPoint(x: 0.0, y: -min(insets.top, separatorHeight)), size: CGSize(width: params.width, height: contentSize.height + min(insets.top, separatorHeight) + min(insets.bottom, separatorHeight)))
                        strongSelf.topStripeNode.frame = CGRect(origin: CGPoint(x: 0.0, y: -min(insets.top, separatorHeight)), size: CGSize(width: params.width, height: separatorHeight))
                        strongSelf.bottomStripeNode.frame = CGRect(origin: CGPoint(x: bottomStripeInset, y: contentSize.height - separatorHeight), size: CGSize(width: params.width - bottomStripeInset, height: separatorHeight))
                    }
                    
                    strongSelf.titleNode.frame = CGRect(origin: CGPoint(x: leftInset, y: 8.0), size: titleLayout.size)
                    
                    var index = 0
                    var yOffset = strongSelf.titleNode.frame.maxY + 10.0
                    for nodes in strongSelf.callNodes {
                        let layout = nodesLayout[index]
                        nodes.0.frame = CGRect(origin: CGPoint(x: leftInset, y: yOffset), size: layout.0.size)
                        nodes.1.frame = CGRect(origin: CGPoint(x: leftInset + 75.0, y: yOffset), size: layout.1.size)
                        
                        yOffset += layout.0.size.height + 12.0
                        index += 1
                    }
                }
            })
        }
    }
    
    override func animateInsertion(_ currentTimestamp: Double, duration: Double, short: Bool) {
        self.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.4)
    }
    
    override func animateAdded(_ currentTimestamp: Double, duration: Double) {
        self.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.2)
    }
    
    override func animateRemoved(_ currentTimestamp: Double, duration: Double) {
        self.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.15, removeOnCompletion: false)
    }
}

