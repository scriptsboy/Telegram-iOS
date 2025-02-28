import Foundation
import UIKit
import Display
import Postbox
import TelegramCore
import SwiftSignalKit
import TelegramPresentationData
import TelegramUIPrivateModule

public final class TelegramRootController: NavigationController {
    private let context: AccountContext
    
    public var rootTabController: TabBarController?
    
    public var contactsController: ContactsController?
    public var callListController: CallListController?
    public var chatListController: ChatListController?
    public var accountSettingsController: ViewController?
    
    public var filterControllers: [ChatListController]?
    
    private var permissionsDisposable: Disposable?
    private var presentationDataDisposable: Disposable?
    private var presentationData: PresentationData
    
    public init(context: AccountContext) {
        self.context = context
        
        self.presentationData = context.sharedContext.currentPresentationData.with { $0 }
        
        let navigationDetailsBackgroundMode: NavigationEmptyDetailsBackgoundMode?
        switch presentationData.chatWallpaper {
        case .color:
            let image = generateTintedImage(image: UIImage(bundleImageName: "Chat List/EmptyMasterDetailIcon"), color: presentationData.theme.chatList.messageTextColor.withAlphaComponent(0.2))
            navigationDetailsBackgroundMode = image != nil ? .image(image!) : nil
        default:
            let image = chatControllerBackgroundImage(wallpaper: presentationData.chatWallpaper, mediaBox: context.account.postbox.mediaBox)
            navigationDetailsBackgroundMode = image != nil ? .wallpaper(image!) : nil
        }
        
        super.init(mode: .automaticMasterDetail, theme: NavigationControllerTheme(presentationTheme: self.presentationData.theme), backgroundDetailsMode: navigationDetailsBackgroundMode)
        
        self.presentationDataDisposable = (context.sharedContext.presentationData
        |> deliverOnMainQueue).start(next: { [weak self] presentationData in
            if let strongSelf = self {
                
                if presentationData.chatWallpaper != strongSelf.presentationData.chatWallpaper {
                    let navigationDetailsBackgroundMode: NavigationEmptyDetailsBackgoundMode?
                    switch presentationData.chatWallpaper {
                    case .color:
                        let image = generateTintedImage(image: UIImage(bundleImageName: "Chat List/EmptyMasterDetailIcon"), color: presentationData.theme.chatList.messageTextColor.withAlphaComponent(0.2))
                        navigationDetailsBackgroundMode = image != nil ? .image(image!) : nil
                    default:
                        let image = chatControllerBackgroundImage(wallpaper: presentationData.chatWallpaper, mediaBox: strongSelf.context.account.postbox.mediaBox)
                        navigationDetailsBackgroundMode = image != nil ? .wallpaper(image!) : nil
                    }
                    strongSelf.updateBackgroundDetailsMode(navigationDetailsBackgroundMode, transition: .immediate)
                }
                
                
                
                let previousTheme = strongSelf.presentationData.theme
                strongSelf.presentationData = presentationData
                if previousTheme !== presentationData.theme {
                    strongSelf.rootTabController?.updateTheme(navigationBarPresentationData: NavigationBarPresentationData(presentationData: presentationData), theme: TabBarControllerTheme(rootControllerTheme: presentationData.theme))
                    strongSelf.rootTabController?.statusBar.statusBarStyle = presentationData.theme.rootController.statusBarStyle.style
                    
                    
                }
            }
        })
    }
    
    required public init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        self.permissionsDisposable?.dispose()
        self.presentationDataDisposable?.dispose()
    }
    
    public func addRootControllers(showCallsTab: Bool, niceSettings: NiceSettings) {
        let tabBarController = TabBarController(navigationBarPresentationData: NavigationBarPresentationData(presentationData: self.presentationData), theme: TabBarControllerTheme(rootControllerTheme: self.presentationData.theme), showTabNames: SimplyNiceSettings().showTabNames)
        let chatListController = ChatListController(context: self.context, groupId: .root, controlsHistoryPreload: true)
        chatListController.tabBarItem.badgeValue = self.context.sharedContext.switchingData.chatListBadge
        let callListController = CallListController(context: self.context, mode: .tab)
        
        var controllers: [ViewController] = []
        
        let contactsController = ContactsController(context: self.context)
        contactsController.switchToChatsController = {  [weak self] in
            self?.openChatsController(activateSearch: false)
        }
        // let niceSettings = getNiceSettings(accountManager: self.context.sharedContext.accountManager)
        if niceSettings.showContactsTab {
            controllers.append(contactsController)
        }
        if showCallsTab {
            controllers.append(callListController)
        }
        if SimplyNiceSettings().maxFilters > 0 {
            var filControllers: [ChatListController] = []
            for (index, filter) in SimplyNiceSettings().chatFilters.enumerated() {
                // Break if max filters
                if index + 1 > SimplyNiceSettings().maxFilters {
                    break
                }
                filControllers.append(ChatListController(context: self.context, groupId: .root, controlsHistoryPreload: true, filter: filter, filterIndex: Int32(index)))
            }
            
            if !filControllers.isEmpty {
                for controller in filControllers {
                    controller.tabBarItem.badgeValue = self.context.sharedContext.switchingData.chatListBadge
                    controllers.append(controller)
                }
                self.filterControllers = filControllers
            } else {
                self.filterControllers = nil
            }
        }

        controllers.append(chatListController)
        
        let restoreSettignsController = self.context.sharedContext.switchingData.settingsController
        restoreSettignsController?.updateContext(context: self.context)
        self.context.sharedContext.switchingData = (nil, nil, nil)
        
        let accountSettingsController = restoreSettignsController ?? settingsController(context: self.context, accountManager: context.sharedContext.accountManager)
        controllers.append(accountSettingsController)
        
        tabBarController.setControllers(controllers, selectedIndex: restoreSettignsController != nil ? (controllers.count - 1) : (controllers.count - 2))
        
        self.contactsController = contactsController
        self.callListController = callListController
        self.chatListController = chatListController
        self.accountSettingsController = accountSettingsController
        self.rootTabController = tabBarController
        self.pushViewController(tabBarController, animated: false)
    }
    
    public func updateRootControllers(showCallsTab: Bool, niceSettings: NiceSettings) {
        guard let rootTabController = self.rootTabController else {
            return
        }
        var controllers: [ViewController] = []
        // let niceSettings = getNiceSettings(accountManager: self.context.sharedContext.accountManager)
        if niceSettings.showContactsTab {
            controllers.append(self.contactsController!)
        }
        
        if showCallsTab {
            controllers.append(self.callListController!)
        }
        
        if SimplyNiceSettings().maxFilters > 0 {
            var filControllers: [ChatListController] = []
            for (index, filter) in SimplyNiceSettings().chatFilters.enumerated() {
                // Break if max filters
                if index + 1 > SimplyNiceSettings().maxFilters {
                    break
                }
                filControllers.append(ChatListController(context: self.context, groupId: .root, controlsHistoryPreload: true, filter: filter, filterIndex: Int32(index)))
            }
            
            if !filControllers.isEmpty {
                for controller in filControllers {
                    controller.tabBarItem.badgeValue = self.context.sharedContext.switchingData.chatListBadge
                    controllers.append(controller)
                }
                self.filterControllers = filControllers
            } else {
                self.filterControllers = nil
            }
        }
        
        
        controllers.append(self.chatListController!)
        controllers.append(self.accountSettingsController!)
        
        rootTabController.setControllers(controllers, selectedIndex: nil)
    }
    
    public func openChatsController(activateSearch: Bool) {
        guard let rootTabController = self.rootTabController else {
            return
        }
        
        if activateSearch {
            self.popToRoot(animated: false)
        }
        
        if let index = rootTabController.controllers.index(where: { $0 is ChatListController}) {
            rootTabController.selectedIndex = index
        }
        
        if activateSearch {
            self.chatListController?.activateSearch()
        }
    }
    
    public func openRootCompose() {
        self.chatListController?.composePressed()
    }
    
    public func openRootCamera() {
        guard let controller = self.viewControllers.last as? ViewController else {
            return
        }
        controller.view.endEditing(true)
        presentedLegacyShortcutCamera(context: self.context, saveCapturedMedia: false, saveEditedPhotos: false, mediaGrouping: true, parentController: controller)
    }
}
