import Foundation
import UIKit
import Display
import SwiftSignalKit
import Postbox
import TelegramCore
import TelegramPresentationData
import TelegramUIPreferences

private final class BlockedPeersControllerArguments {
    let account: Account
    
    let setPeerIdWithRevealedOptions: (PeerId?, PeerId?) -> Void
    let addPeer: () -> Void
    let removePeer: (PeerId) -> Void
    let openPeer: (Peer) -> Void
    
    init(account: Account, setPeerIdWithRevealedOptions: @escaping (PeerId?, PeerId?) -> Void, addPeer: @escaping () -> Void, removePeer: @escaping (PeerId) -> Void, openPeer: @escaping (Peer) -> Void) {
        self.account = account
        self.setPeerIdWithRevealedOptions = setPeerIdWithRevealedOptions
        self.addPeer = addPeer
        self.removePeer = removePeer
        self.openPeer = openPeer
    }
}

private enum BlockedPeersSection: Int32 {
    case actions
    case peers
}

private enum BlockedPeersEntryStableId: Hashable {
    case add
    case peer(PeerId)
}

private enum BlockedPeersEntry: ItemListNodeEntry {
    case add(PresentationTheme, String)
    case peerItem(Int32, PresentationTheme, PresentationStrings, PresentationDateTimeFormat, PresentationPersonNameOrder, Peer, ItemListPeerItemEditing, Bool)
    
    var section: ItemListSectionId {
        switch self {
            case .add:
                return BlockedPeersSection.actions.rawValue
            case .peerItem:
                return BlockedPeersSection.peers.rawValue
        }
    }
    
    var stableId: BlockedPeersEntryStableId {
        switch self {
            case .add:
                return .add
            case let .peerItem(_, _, _, _, _, peer, _, _):
                return .peer(peer.id)
        }
    }
    
    static func ==(lhs: BlockedPeersEntry, rhs: BlockedPeersEntry) -> Bool {
        switch lhs {
            case let .add(lhsTheme, lhsText):
                if case let .add(rhsTheme, rhsText) = rhs, lhsTheme === rhsTheme, lhsText == rhsText {
                    return true
                } else {
                    return false
                }
            case let .peerItem(lhsIndex, lhsTheme, lhsStrings, lhsDateTimeFormat, lhsNameOrder, lhsPeer, lhsEditing, lhsEnabled):
                if case let .peerItem(rhsIndex, rhsTheme, rhsStrings, rhsDateTimeFormat, rhsNameOrder, rhsPeer, rhsEditing, rhsEnabled) = rhs {
                    if lhsIndex != rhsIndex {
                        return false
                    }
                    if lhsTheme !== rhsTheme {
                        return false
                    }
                    if lhsStrings !== rhsStrings {
                        return false
                    }
                    if lhsDateTimeFormat != rhsDateTimeFormat {
                        return false
                    }
                    if lhsNameOrder != rhsNameOrder {
                        return false
                    }
                    if !lhsPeer.isEqual(rhsPeer) {
                        return false
                    }
                    if lhsEditing != rhsEditing {
                        return false
                    }
                    if lhsEnabled != rhsEnabled {
                        return false
                    }
                    return true
                } else {
                    return false
                }
        }
    }
    
    static func <(lhs: BlockedPeersEntry, rhs: BlockedPeersEntry) -> Bool {
        switch lhs {
            case .add:
                if case .add = rhs {
                    return true
                } else {
                    return false
                }
            case let .peerItem(index, _, _, _, _, _, _, _):
                switch rhs {
                    case .add:
                        return false
                    case let .peerItem(rhsIndex, _, _, _, _, _, _, _):
                        return index < rhsIndex
                }
        }
    }
    
    func item(_ arguments: BlockedPeersControllerArguments) -> ListViewItem {
        switch self {
            case let .add(theme, text):
                return ItemListPeerActionItem(theme: theme, icon: PresentationResourcesItemList.addPersonIcon(theme), title: text, sectionId: self.section, editing: false, action: {
                    arguments.addPeer()
                })
            case let .peerItem(_, theme, strings, dateTimeFormat, nameDisplayOrder, peer, editing, enabled):
                return ItemListPeerItem(theme: theme, strings: strings, dateTimeFormat: dateTimeFormat, nameDisplayOrder: nameDisplayOrder, account: arguments.account, peer: peer, presence: nil, text: .none, label: .none, editing: editing, switchValue: nil, enabled: enabled, selectable: true, sectionId: self.section, action: {
                    arguments.openPeer(peer)
                }, setPeerIdWithRevealedOptions: { previousId, id in
                    arguments.setPeerIdWithRevealedOptions(previousId, id)
                }, removePeer: { peerId in
                    arguments.removePeer(peerId)
                })
        }
    }
}

private struct BlockedPeersControllerState: Equatable {
    let editing: Bool
    let peerIdWithRevealedOptions: PeerId?
    let removingPeerId: PeerId?
    
    init() {
        self.editing = false
        self.peerIdWithRevealedOptions = nil
        self.removingPeerId = nil
    }
    
    init(editing: Bool, peerIdWithRevealedOptions: PeerId?, removingPeerId: PeerId?) {
        self.editing = editing
        self.peerIdWithRevealedOptions = peerIdWithRevealedOptions
        self.removingPeerId = removingPeerId
    }
    
    static func ==(lhs: BlockedPeersControllerState, rhs: BlockedPeersControllerState) -> Bool {
        if lhs.editing != rhs.editing {
            return false
        }
        if lhs.peerIdWithRevealedOptions != rhs.peerIdWithRevealedOptions {
            return false
        }
        if lhs.removingPeerId != rhs.removingPeerId {
            return false
        }
        
        return true
    }
    
    func withUpdatedEditing(_ editing: Bool) -> BlockedPeersControllerState {
        return BlockedPeersControllerState(editing: editing, peerIdWithRevealedOptions: self.peerIdWithRevealedOptions, removingPeerId: self.removingPeerId)
    }
    
    func withUpdatedPeerIdWithRevealedOptions(_ peerIdWithRevealedOptions: PeerId?) -> BlockedPeersControllerState {
        return BlockedPeersControllerState(editing: self.editing, peerIdWithRevealedOptions: peerIdWithRevealedOptions, removingPeerId: self.removingPeerId)
    }
    
    func withUpdatedRemovingPeerId(_ removingPeerId: PeerId?) -> BlockedPeersControllerState {
        return BlockedPeersControllerState(editing: self.editing, peerIdWithRevealedOptions: self.peerIdWithRevealedOptions, removingPeerId: removingPeerId)
    }
}

private func blockedPeersControllerEntries(presentationData: PresentationData, state: BlockedPeersControllerState, blockedPeersState: BlockedPeersContextState) -> [BlockedPeersEntry] {
    var entries: [BlockedPeersEntry] = []
    
    if !blockedPeersState.peers.isEmpty || !blockedPeersState.canLoadMore {
        entries.append(.add(presentationData.theme, presentationData.strings.BlockedUsers_BlockUser))
        
        var index: Int32 = 0
        for peer in blockedPeersState.peers {
            entries.append(.peerItem(index, presentationData.theme, presentationData.strings, presentationData.dateTimeFormat, presentationData.nameDisplayOrder, peer.peer!, ItemListPeerItemEditing(editable: true, editing: state.editing, revealed: peer.peerId == state.peerIdWithRevealedOptions), state.removingPeerId != peer.peerId))
            index += 1
        }
    }
    
    return entries
}

public func blockedPeersController(context: AccountContext, blockedPeersContext: BlockedPeersContext) -> ViewController {
    let statePromise = ValuePromise(BlockedPeersControllerState(), ignoreRepeated: true)
    let stateValue = Atomic(value: BlockedPeersControllerState())
    let updateState: ((BlockedPeersControllerState) -> BlockedPeersControllerState) -> Void = { f in
        statePromise.set(stateValue.modify { f($0) })
    }
    
    var pushControllerImpl: ((ViewController) -> Void)?
    var presentControllerImpl: ((ViewController, Any?) -> Void)?
    
    let actionsDisposable = DisposableSet()
    
    let removePeerDisposable = MetaDisposable()
    actionsDisposable.add(removePeerDisposable)
    
    let peersPromise = Promise<[Peer]?>(nil)
    
    let arguments = BlockedPeersControllerArguments(account: context.account, setPeerIdWithRevealedOptions: { peerId, fromPeerId in
        updateState { state in
            if (peerId == nil && fromPeerId == state.peerIdWithRevealedOptions) || (peerId != nil && fromPeerId == nil) {
                return state.withUpdatedPeerIdWithRevealedOptions(peerId)
            } else {
                return state
            }
        }
    }, addPeer: {
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let controller = PeerSelectionController(context: context, filter: [.onlyPrivateChats, .excludeSavedMessages, .removeSearchHeader, .excludeRecent], title: presentationData.strings.BlockedUsers_SelectUserTitle)
        controller.peerSelected = { [weak controller] peerId in
            guard let strongController = controller else {
                return
            }
            strongController.inProgress = true
            removePeerDisposable.set((blockedPeersContext.add(peerId: peerId)
            |> deliverOnMainQueue).start(completed: {
                guard let strongController = controller else {
                    return
                }
                strongController.inProgress = false
                strongController.dismiss()
            }))
        }
        presentControllerImpl?(controller, nil)
    }, removePeer: { memberId in
        updateState {
            return $0.withUpdatedRemovingPeerId(memberId)
        }
        
        removePeerDisposable.set((blockedPeersContext.remove(peerId: memberId)
        |> deliverOnMainQueue).start(error: { _ in
            updateState {
                return $0.withUpdatedRemovingPeerId(nil)
            }
        }, completed: {
            updateState {
                return $0.withUpdatedRemovingPeerId(nil)
            }
        }))
    }, openPeer: { peer in
        if let controller = peerInfoController(context: context, peer: peer) {
            pushControllerImpl?(controller)
        }
    })
    
    var previousState: BlockedPeersContextState?
    
    let signal = combineLatest(context.sharedContext.presentationData, statePromise.get(), blockedPeersContext.state)
    |> deliverOnMainQueue
    |> map { presentationData, state, blockedPeersState -> (ItemListControllerState, (ItemListNodeState<BlockedPeersEntry>, BlockedPeersEntry.ItemGenerationArguments)) in
        var rightNavigationButton: ItemListNavigationButton?
        if !blockedPeersState.peers.isEmpty {
            if state.editing {
                rightNavigationButton = ItemListNavigationButton(content: .text(presentationData.strings.Common_Done), style: .bold, enabled: true, action: {
                    updateState { state in
                        return state.withUpdatedEditing(false)
                    }
                })
            } else {
                rightNavigationButton = ItemListNavigationButton(content: .text(presentationData.strings.Common_Edit), style: .regular, enabled: true, action: {
                    updateState { state in
                        return state.withUpdatedEditing(true)
                    }
                })
            }
        }
        
        var emptyStateItem: ItemListControllerEmptyStateItem?
        if blockedPeersState.peers.isEmpty && !blockedPeersState.canLoadMore {
            emptyStateItem = ItemListTextEmptyStateItem(text: presentationData.strings.BlockedUsers_Info)
        }
        
        let previousStateValue = previousState
        previousState = blockedPeersState
        
        let controllerState = ItemListControllerState(theme: presentationData.theme, title: .text(presentationData.strings.BlockedUsers_Title), leftNavigationButton: nil, rightNavigationButton: rightNavigationButton, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back), animateChanges: true)
        let listState = ItemListNodeState(entries: blockedPeersControllerEntries(presentationData: presentationData, state: state, blockedPeersState: blockedPeersState), style: .blocks, emptyStateItem: emptyStateItem, animateChanges: previousStateValue != nil && previousStateValue!.peers.count >= blockedPeersState.peers.count, scrollEnabled: emptyStateItem == nil)
        
        return (controllerState, (listState, arguments))
    }
    |> afterDisposed {
        actionsDisposable.dispose()
    }
    
    let controller = ItemListController(context: context, state: signal)
    pushControllerImpl = { [weak controller] c in
        if let controller = controller {
            (controller.navigationController as? NavigationController)?.pushViewController(c)
        }
    }
    presentControllerImpl = { [weak controller] c, a in
        if let controller = controller {
            controller.present(c, in: .window(.root), with: a)
        }
    }
    controller.visibleBottomContentOffsetChanged = { offset in
        if case let .known(value) = offset, value < 40.0 {
            blockedPeersContext.loadMore()
        }
    }
    return controller
}
