import Foundation
import UIKit
import AsyncDisplayKit
import Postbox
import TelegramCore
import Display
import SwiftSignalKit
import TelegramPresentationData

private struct StickersChatInputContextPanelEntryStableId: Hashable {
    let ids: [MediaId]
    
    var hashValue: Int {
        var hash: Int = 0
        for i in 0 ..< self.ids.count {
            if i == 0 {
                hash = self.ids[i].hashValue
            } else {
                hash = hash &* 31 &+ self.ids[i].hashValue
            }
        }
        return hash
    }
    
    static func ==(lhs: StickersChatInputContextPanelEntryStableId, rhs: StickersChatInputContextPanelEntryStableId) -> Bool {
        return lhs.ids == rhs.ids
    }
}

final class StickersChatInputContextPanelInteraction {
    var previewedStickerItem: StickerPackItem?
}

private struct StickersChatInputContextPanelEntry: Identifiable, Comparable {
    let index: Int
    let theme: PresentationTheme
    let files: [TelegramMediaFile]
    let itemsInRow: Int
    
    var stableId: StickersChatInputContextPanelEntryStableId {
        return StickersChatInputContextPanelEntryStableId(ids: files.compactMap { $0.id })
    }

    static func ==(lhs: StickersChatInputContextPanelEntry, rhs: StickersChatInputContextPanelEntry) -> Bool {
        return lhs.index == rhs.index && lhs.stableId == rhs.stableId
    }

    static func <(lhs: StickersChatInputContextPanelEntry, rhs: StickersChatInputContextPanelEntry) -> Bool {
        return lhs.index < rhs.index
    }
    
    func withUpdatedTheme(_ theme: PresentationTheme) -> StickersChatInputContextPanelEntry {
        return StickersChatInputContextPanelEntry(index: self.index, theme: theme, files: self.files, itemsInRow: itemsInRow)
    }

    func item(account: Account, stickersInteraction: StickersChatInputContextPanelInteraction, interfaceInteraction: ChatPanelInterfaceInteraction) -> ListViewItem {
        return StickersChatInputContextPanelItem(account: account, theme: self.theme, index: self.index, files: self.files, itemsInRow: self.itemsInRow, stickersInteraction: stickersInteraction, interfaceInteraction: interfaceInteraction)
    }
}


private struct StickersChatInputContextPanelTransition {
    let deletions: [ListViewDeleteItem]
    let insertions: [ListViewInsertItem]
    let updates: [ListViewUpdateItem]
}

private func preparedTransition(from fromEntries: [StickersChatInputContextPanelEntry], to toEntries: [StickersChatInputContextPanelEntry], account: Account, stickersInteraction: StickersChatInputContextPanelInteraction, interfaceInteraction: ChatPanelInterfaceInteraction) -> StickersChatInputContextPanelTransition {
    let (deleteIndices, indicesAndItems, updateIndices) = mergeListsStableWithUpdates(leftList: fromEntries, rightList: toEntries)
    
    let deletions = deleteIndices.map { ListViewDeleteItem(index: $0, directionHint: nil) }
    let insertions = indicesAndItems.map { ListViewInsertItem(index: $0.0, previousIndex: $0.2, item: $0.1.item(account: account, stickersInteraction: stickersInteraction, interfaceInteraction: interfaceInteraction), directionHint: nil) }
    let updates = updateIndices.map { ListViewUpdateItem(index: $0.0, previousIndex: $0.2, item: $0.1.item(account: account, stickersInteraction: stickersInteraction, interfaceInteraction: interfaceInteraction), directionHint: nil) }
    
    return StickersChatInputContextPanelTransition(deletions: deletions, insertions: insertions, updates: updates)
}

private let itemSize = CGSize(width: 66.0, height: 66.0)

final class StickersChatInputContextPanelNode: ChatInputContextPanelNode {
    private let strings: PresentationStrings
    
    private let listView: ListView
    private var results: [TelegramMediaFile] = []
    private var currentEntries: [StickersChatInputContextPanelEntry]?
    
    private var enqueuedTransitions: [(StickersChatInputContextPanelTransition, Bool)] = []
    private var validLayout: (CGSize, CGFloat, CGFloat, ChatPresentationInterfaceState)?
    
    public var controllerInteraction: ChatControllerInteraction?
    private let stickersInteraction: StickersChatInputContextPanelInteraction
    
    private var stickerPreviewController: StickerPreviewController?
    
    override init(context: AccountContext, theme: PresentationTheme, strings: PresentationStrings) {
        self.strings = strings
        
        self.listView = ListView()
        self.listView.isOpaque = false
        self.listView.stackFromBottom = true
        self.listView.keepBottomItemOverscrollBackground = theme.list.plainBackgroundColor
        self.listView.limitHitTestToNodes = true
        self.listView.view.disablesInteractiveTransitionGestureRecognizer = true
        
        self.stickersInteraction = StickersChatInputContextPanelInteraction()
        
        super.init(context: context, theme: theme, strings: strings)
        
        self.isOpaque = false
        self.clipsToBounds = true
        
        self.addSubnode(self.listView)
    }
    
    override func didLoad() {
        super.didLoad()
        
        self.view.addGestureRecognizer(PeekControllerGestureRecognizer(contentAtPoint: { [weak self] point in
            if let strongSelf = self {
                let convertedPoint = strongSelf.listView.view.convert(point, from: strongSelf.view)
                guard strongSelf.listView.bounds.contains(convertedPoint) else {
                    return nil
                }
                
                var stickersNode: StickersChatInputContextPanelItemNode?
                strongSelf.listView.forEachVisibleItemNode({ itemNode in
                    if itemNode.frame.contains(convertedPoint), let node = itemNode as? StickersChatInputContextPanelItemNode {
                        stickersNode = node
                    }
                })
                
                if let stickersNode = stickersNode {
                    let point = strongSelf.listView.view.convert(point, to: stickersNode.view)
                    if let (item, itemNode) = stickersNode.stickerItem(at: point) {
                        return strongSelf.context.account.postbox.transaction { transaction -> Bool in
                            return getIsStickerSaved(transaction: transaction, fileId: item.file.fileId)
                        }
                        |> deliverOnMainQueue
                        |> map { isStarred -> (ASDisplayNode, PeekControllerContent)? in
                            if let strongSelf = self, let controllerInteraction = strongSelf.controllerInteraction {
                                var menuItems: [PeekControllerMenuItem] = []
                                menuItems = [
                                    PeekControllerMenuItem(title: strongSelf.strings.StickerPack_Send, color: .accent, font: .bold, action: {  _, _ in
                                        return controllerInteraction.sendSticker(.standalone(media: item.file), true, itemNode, itemNode.bounds)
                                    }),
                                    PeekControllerMenuItem(title: isStarred ? strongSelf.strings.Stickers_RemoveFromFavorites : strongSelf.strings.Stickers_AddToFavorites, color: isStarred ? .destructive : .accent, action: { _, _ in
                                        if let strongSelf = self {
                                            if isStarred {
                                                let _ = removeSavedSticker(postbox: strongSelf.context.account.postbox, mediaId: item.file.fileId).start()
                                            } else {
                                                let _ = addSavedSticker(postbox: strongSelf.context.account.postbox, network: strongSelf.context.account.network, file: item.file).start()
                                            }
                                        }
                                        return true
                                    }),
                                    PeekControllerMenuItem(title: strongSelf.strings.StickerPack_ViewPack, color: .accent, action: { _, _ in
                                        if let strongSelf = self, let controllerInteraction = strongSelf.controllerInteraction {
                                            loop: for attribute in item.file.attributes {
                                                switch attribute {
                                                case let .Sticker(_, packReference, _):
                                                    if let packReference = packReference {
                                                        let controller = StickerPackPreviewController(context: strongSelf.context, stickerPack: packReference, parentNavigationController: controllerInteraction.navigationController())
                                                        controller.sendSticker = { file, sourceNode, sourceRect in
                                                            if let strongSelf = self, let controllerInteraction = strongSelf.controllerInteraction {
                                                                return controllerInteraction.sendSticker(file, true, sourceNode, sourceRect)
                                                            } else {
                                                                return false
                                                            }
                                                        }
                                                        
                                                        controllerInteraction.navigationController()?.view.window?.endEditing(true)
                                                        controllerInteraction.presentController(controller, nil)
                                                    }
                                                    break loop
                                                default:
                                                    break
                                                }
                                            }
                                        }
                                        return true
                                    }),
                                    PeekControllerMenuItem(title: strongSelf.strings.Common_Cancel, color: .accent, action: { _, _ in return true })
                                ]
                                return (itemNode, StickerPreviewPeekContent(account: strongSelf.context.account, item: .pack(item), menu: menuItems))
                            } else {
                                return nil
                            }
                        }
                    }
                }
            }
            return nil
        }, present: { [weak self] content, sourceNode in
            if let strongSelf = self {
                let controller = PeekController(theme: PeekControllerTheme(presentationTheme: strongSelf.theme), content: content, sourceNode: {
                    return sourceNode
                })
                strongSelf.interfaceInteraction?.presentGlobalOverlayController(controller, nil)
                return controller
            }
            return nil
        }, updateContent: { [weak self] content in
            if let strongSelf = self {
                var item: StickerPackItem?
                if let content = content as? StickerPreviewPeekContent, case let .pack(contentItem) = content.item {
                    item = contentItem
                }
                strongSelf.updatePreviewingItem(item: item, animated: true)
            }
        }))
    }
    
    private func updatePreviewingItem(item: StickerPackItem?, animated: Bool) {
        if self.stickersInteraction.previewedStickerItem != item {
            self.stickersInteraction.previewedStickerItem = item
            
            self.listView.forEachItemNode { itemNode in
                if let itemNode = itemNode as? StickersChatInputContextPanelItemNode {
                    itemNode.updatePreviewing(animated: animated)
                }
            }
        }
    }
    
    func updateResults(_ results: [TelegramMediaFile]) {
        self.results = results

        self.commitResults(updateLayout: true)
    }
    
    private func commitResults(updateLayout: Bool = false) {
        guard let validLayout = self.validLayout else {
            return
        }
        
        var entries: [StickersChatInputContextPanelEntry] = []
        
        let itemsInRow = Int(floor((validLayout.0.width - validLayout.1 - validLayout.2) / itemSize.width))
        
        var files: [TelegramMediaFile] = []
        var index = entries.count
        for i in 0 ..< self.results.count {
            files.append(results[i])
            if files.count == itemsInRow {
                entries.append(StickersChatInputContextPanelEntry(index: index, theme: self.theme, files: files, itemsInRow: itemsInRow))
                index += 1
                files.removeAll()
            }
        }
        
        if !files.isEmpty {
            entries.append(StickersChatInputContextPanelEntry(index: index, theme: self.theme, files: files, itemsInRow: itemsInRow))
        }
        
        if updateLayout {
            self.updateLayout(size: validLayout.0, leftInset: validLayout.1, rightInset: validLayout.2, transition: .immediate, interfaceState: validLayout.3)
        }
        
        self.prepareTransition(from: self.currentEntries, to: entries)
    }
    
    private func prepareTransition(from: [StickersChatInputContextPanelEntry]? , to: [StickersChatInputContextPanelEntry]) {
        let firstTime = from == nil
        let transition = preparedTransition(from: from ?? [], to: to, account: self.context.account, stickersInteraction: self.stickersInteraction, interfaceInteraction: self.interfaceInteraction!)
        self.currentEntries = to
        self.enqueueTransition(transition, firstTime: firstTime)
    }
    
    private func enqueueTransition(_ transition: StickersChatInputContextPanelTransition, firstTime: Bool) {
        self.enqueuedTransitions.append((transition, firstTime))
        
        if self.validLayout != nil {
            while !self.enqueuedTransitions.isEmpty {
                self.dequeueTransition()
            }
        }
    }
    
    private func dequeueTransition() {
        if let validLayout = self.validLayout, let (transition, firstTime) = self.enqueuedTransitions.first {
            self.enqueuedTransitions.remove(at: 0)
            
            var options = ListViewDeleteAndInsertOptions()
            if firstTime {
                //options.insert(.Synchronous)
                //options.insert(.LowLatency)
            } else {
                options.insert(.AnimateTopItemPosition)
                options.insert(.AnimateCrossfade)
            }
            
            var insets = UIEdgeInsets()
            insets.top = topInsetForLayout(size: validLayout.0)
            insets.left = validLayout.1
            insets.right = validLayout.2
            
            let updateSizeAndInsets = ListViewUpdateSizeAndInsets(size: validLayout.0, insets: insets, duration: 0.0, curve: .Default(duration: nil))
            
            self.listView.transaction(deleteIndices: transition.deletions, insertIndicesAndItems: transition.insertions, updateIndicesAndItems: transition.updates, options: options, updateSizeAndInsets: updateSizeAndInsets, updateOpaqueState: nil, completion: { [weak self] _ in
                if let strongSelf = self, firstTime {
                    var topItemOffset: CGFloat?
                    strongSelf.listView.forEachItemNode { itemNode in
                        if topItemOffset == nil {
                            topItemOffset = itemNode.frame.minY
                        }
                    }
                    
                    if let topItemOffset = topItemOffset {
                        let position = strongSelf.listView.layer.position
                        strongSelf.listView.layer.animatePosition(from: CGPoint(x: position.x, y: position.y + (strongSelf.listView.bounds.size.height - topItemOffset)), to: position, duration: 0.3, timingFunction: kCAMediaTimingFunctionSpring)
                    }
                }
            })
        }
    }
    
    private func topInsetForLayout(size: CGSize) -> CGFloat {
        let minimumItemHeights: CGFloat = floor(itemSize.height * 1.5)
        
        return max(size.height - minimumItemHeights, 0.0)
    }
    
    override func updateLayout(size: CGSize, leftInset: CGFloat, rightInset: CGFloat, transition: ContainedViewLayoutTransition, interfaceState: ChatPresentationInterfaceState) {
        let hadValidLayout = self.validLayout != nil
        self.validLayout = (size, leftInset, rightInset, interfaceState)
        
        var insets = UIEdgeInsets()
        insets.top = self.topInsetForLayout(size: size)
        insets.left = leftInset
        insets.right = rightInset
        
        transition.updateFrame(node: self.listView, frame: CGRect(x: 0.0, y: 0.0, width: size.width, height: size.height))
        
        var duration: Double = 0.0
        var curve: UInt = 0
        switch transition {
            case .immediate:
                break
            case let .animated(animationDuration, animationCurve):
                duration = animationDuration
                switch animationCurve {
                    case .easeInOut, .custom:
                        break
                    case .spring:
                        curve = 7
                }
        }
        
        let listViewCurve: ListViewAnimationCurve
        if curve == 7 {
            listViewCurve = .Spring(duration: duration)
        } else {
            listViewCurve = .Default(duration: duration)
        }
        
        let updateSizeAndInsets = ListViewUpdateSizeAndInsets(size: size, insets: insets, duration: duration, curve: listViewCurve)
        
        self.listView.transaction(deleteIndices: [], insertIndicesAndItems: [], updateIndicesAndItems: [], options: [.Synchronous, .LowLatency], scrollToItem: nil, updateSizeAndInsets: updateSizeAndInsets, stationaryItemRange: nil, updateOpaqueState: nil, completion: { _ in })
        
        self.commitResults(updateLayout: false)
        
        if !hadValidLayout {
            while !self.enqueuedTransitions.isEmpty {
                self.dequeueTransition()
            }
        }
        
        if self.theme !== interfaceState.theme {
            self.theme = interfaceState.theme
            self.listView.keepBottomItemOverscrollBackground = self.theme.list.plainBackgroundColor
            
            let new = self.currentEntries?.map({$0.withUpdatedTheme(interfaceState.theme)}) ?? []
            self.prepareTransition(from: self.currentEntries, to: new)
        }
    }
    
    override func animateOut(completion: @escaping () -> Void) {
        var topItemOffset: CGFloat?
        self.listView.forEachItemNode { itemNode in
            if topItemOffset == nil {
                topItemOffset = itemNode.frame.minY
            }
        }
        
        if let topItemOffset = topItemOffset {
            let position = self.listView.layer.position
            self.listView.layer.animatePosition(from: position, to: CGPoint(x: position.x, y: position.y + (self.listView.bounds.size.height - topItemOffset)), duration: 0.3, timingFunction: kCAMediaTimingFunctionSpring, removeOnCompletion: false, completion: { _ in
                completion()
            })
        } else {
            completion()
        }
    }
    
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let listViewFrame = self.listView.frame
        return self.listView.hitTest(CGPoint(x: point.x - listViewFrame.minX, y: point.y - listViewFrame.minY), with: event)
    }
}
