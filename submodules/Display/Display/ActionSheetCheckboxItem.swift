import Foundation
import UIKit
import AsyncDisplayKit

public enum ActionSheetCheckboxStyle {
    case `default`
    case alignRight
}

public class ActionSheetCheckboxItem: ActionSheetItem {
    public let title: String
    public let label: String
    public let value: Bool
    public let style: ActionSheetCheckboxStyle
    public let action: (Bool) -> Void
    
    public init(title: String, label: String, value: Bool, style: ActionSheetCheckboxStyle = .default, action: @escaping (Bool) -> Void) {
        self.title = title
        self.label = label
        self.value = value
        self.style = style
        self.action = action
    }
    
    public func node(theme: ActionSheetControllerTheme) -> ActionSheetItemNode {
        let node = ActionSheetCheckboxItemNode(theme: theme)
        node.setItem(self)
        return node
    }
    
    public func updateNode(_ node: ActionSheetItemNode) {
        guard let node = node as? ActionSheetCheckboxItemNode else {
            assertionFailure()
            return
        }
        
        node.setItem(self)
    }
}

public class ActionSheetCheckboxItemNode: ActionSheetItemNode {
    public static let defaultFont: UIFont = Font.regular(20.0)
    
    private let theme: ActionSheetControllerTheme
    
    private var item: ActionSheetCheckboxItem?
    
    private let button: HighlightTrackingButton
    private let titleNode: ImmediateTextNode
    private let labelNode: ImmediateTextNode
    private let checkNode: ASImageNode
    
    override public init(theme: ActionSheetControllerTheme) {
        self.theme = theme
        
        self.button = HighlightTrackingButton()
        
        self.titleNode = ImmediateTextNode()
        self.titleNode.maximumNumberOfLines = 1
        self.titleNode.isUserInteractionEnabled = false
        self.titleNode.displaysAsynchronously = false
        
        self.labelNode = ImmediateTextNode()
        self.labelNode.maximumNumberOfLines = 1
        self.labelNode.isUserInteractionEnabled = false
        self.labelNode.displaysAsynchronously = false
        
        self.checkNode = ASImageNode()
        self.checkNode.isUserInteractionEnabled = false
        self.checkNode.displayWithoutProcessing = true
        self.checkNode.displaysAsynchronously = false
        self.checkNode.image = generateImage(CGSize(width: 14.0, height: 11.0), rotatedContext: { size, context in
            context.clear(CGRect(origin: CGPoint(), size: size))
            context.setStrokeColor(theme.controlAccentColor.cgColor)
            context.setLineWidth(2.0)
            context.move(to: CGPoint(x: 12.0, y: 1.0))
            context.addLine(to: CGPoint(x: 4.16482734, y: 9.0))
            context.addLine(to: CGPoint(x: 1.0, y: 5.81145833))
            context.strokePath()
        })
        
        super.init(theme: theme)
        
        self.view.addSubview(self.button)
        self.addSubnode(self.titleNode)
        self.addSubnode(self.labelNode)
        self.addSubnode(self.checkNode)
        
        self.button.highligthedChanged = { [weak self] highlighted in
            if let strongSelf = self {
                if highlighted {
                    strongSelf.backgroundNode.backgroundColor = strongSelf.theme.itemHighlightedBackgroundColor
                } else {
                    UIView.animate(withDuration: 0.3, animations: {
                        strongSelf.backgroundNode.backgroundColor = strongSelf.theme.itemBackgroundColor
                    })
                }
            }
        }
        
        self.button.addTarget(self, action: #selector(self.buttonPressed), for: .touchUpInside)
    }
    
    func setItem(_ item: ActionSheetCheckboxItem) {
        self.item = item
        
        self.titleNode.attributedText = NSAttributedString(string: item.title, font: ActionSheetCheckboxItemNode.defaultFont, textColor: self.theme.primaryTextColor)
        self.labelNode.attributedText = NSAttributedString(string: item.label, font: ActionSheetCheckboxItemNode.defaultFont, textColor: self.theme.secondaryTextColor)
        self.checkNode.isHidden = !item.value
        
        self.setNeedsLayout()
    }
    
    public override func calculateSizeThatFits(_ constrainedSize: CGSize) -> CGSize {
        return CGSize(width: constrainedSize.width, height: 57.0)
    }
    
    public override func layout() {
        super.layout()
        
        let size = self.bounds.size
        
        self.button.frame = CGRect(origin: CGPoint(), size: size)
        
        var titleOrigin: CGFloat = 44.0
        var checkOrigin: CGFloat = 22.0
        if let item = self.item, item.style == .alignRight {
            titleOrigin = 24.0
            checkOrigin = size.width - 22.0
        }
        
        let labelSize = self.labelNode.updateLayout(CGSize(width: size.width - 44.0 - 15.0 - 8.0, height: size.height))
        let titleSize = self.titleNode.updateLayout(CGSize(width: size.width - 44.0 - labelSize.width - 15.0 - 8.0, height: size.height))
        self.titleNode.frame = CGRect(origin: CGPoint(x: titleOrigin, y: floorToScreenPixels((size.height - titleSize.height) / 2.0)), size: titleSize)
        self.labelNode.frame = CGRect(origin: CGPoint(x: size.width - 15.0 - labelSize.width, y: floorToScreenPixels((size.height - labelSize.height) / 2.0)), size: labelSize)
        
        if let image = self.checkNode.image {
            self.checkNode.frame = CGRect(origin: CGPoint(x: floor(checkOrigin - (image.size.width / 2.0)), y: floor((size.height - image.size.height) / 2.0)), size: image.size)
        }
    }
    
    @objc func buttonPressed() {
        if let item = self.item {
            item.action(!item.value)
        }
    }
}
