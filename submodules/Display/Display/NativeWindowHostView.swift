import Foundation
import UIKit
import SwiftSignalKit

private let orientationChangeDuration: Double = UIDevice.current.userInterfaceIdiom == .pad ? 0.4 : 0.3

private let defaultOrientations: UIInterfaceOrientationMask = {
    if UIDevice.current.userInterfaceIdiom == .pad {
        return .all
    } else {
        return .allButUpsideDown
    }
}()

public final class PreviewingHostViewDelegate {
    public let controllerForLocation: (UIView, CGPoint) -> (UIViewController, CGRect)?
    public let commitController: (UIViewController) -> Void
    
    public init(controllerForLocation: @escaping (UIView, CGPoint) -> (UIViewController, CGRect)?, commitController: @escaping (UIViewController) -> Void) {
        self.controllerForLocation = controllerForLocation
        self.commitController = commitController
    }
}

public protocol PreviewingHostView {
    @available(iOSApplicationExtension 9.0, iOS 9.0, *)
    var previewingDelegate: PreviewingHostViewDelegate? { get }
}

private func tracePreviewingHostView(view: UIView, point: CGPoint) -> (UIView & PreviewingHostView, CGPoint)? {
    if let view = view as? UIView & PreviewingHostView {
        return (view, point)
    }
    if let superview = view.superview {
        if let result = tracePreviewingHostView(view: superview, point: superview.convert(point, from: view)) {
            return result
        }
    }
    return nil
}

private final class WindowRootViewControllerView: UIView {
    override var frame: CGRect {
        get {
            return super.frame
        } set(value) {
            var value = value
            value.size.height += value.minY
            value.origin.y = 0.0
            super.frame = value
        }
    }
}

private final class WindowRootViewController: UIViewController, UIViewControllerPreviewingDelegate {
    private var voiceOverStatusObserver: AnyObject?
    private var registeredForPreviewing = false
    
    var presentController: ((UIViewController, PresentationSurfaceLevel, Bool, (() -> Void)?) -> Void)?
    var transitionToSize: ((CGSize, Double) -> Void)?
    
    var orientations: UIInterfaceOrientationMask = defaultOrientations {
        didSet {
            if oldValue != self.orientations {
                if self.orientations == .portrait {
                    if UIDevice.current.orientation != .portrait {
                        let value = UIInterfaceOrientation.portrait.rawValue
                        UIDevice.current.setValue(value, forKey: "orientation")
                    }
                } else {
                    UIViewController.attemptRotationToDeviceOrientation()
                }
            }
        }
    }
    
    var gestureEdges: UIRectEdge = [] {
        didSet {
            if oldValue != self.gestureEdges {
                if #available(iOSApplicationExtension 11.0, *) {
                    self.setNeedsUpdateOfScreenEdgesDeferringSystemGestures()
                }
            }
        }
    }
    
    var preferNavigationUIHidden: Bool = false {
        didSet {
            if oldValue != self.preferNavigationUIHidden {
                if #available(iOSApplicationExtension 11.0, *) {
                    self.setNeedsUpdateOfHomeIndicatorAutoHidden()
                }
            }
        }
    }
    
    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .default
    }
    
    override var prefersStatusBarHidden: Bool {
        return false
    }
    
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return orientations
    }
    
    init() {
        super.init(nibName: nil, bundle: nil)
        
        self.extendedLayoutIncludesOpaqueBars = true
        
        if #available(iOSApplicationExtension 11.0, *) {
            self.voiceOverStatusObserver = NotificationCenter.default.addObserver(forName: NSNotification.Name.UIAccessibilityVoiceOverStatusDidChange, object: nil, queue: OperationQueue.main, using: { [weak self] _ in
                if let strongSelf = self {
                    strongSelf.updatePreviewingRegistration()
                }
            })
        }
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        if let voiceOverStatusObserver = self.voiceOverStatusObserver {
            NotificationCenter.default.removeObserver(voiceOverStatusObserver)
        }
    }
    
    override func preferredScreenEdgesDeferringSystemGestures() -> UIRectEdge {
        return self.gestureEdges
    }
    
    override func prefersHomeIndicatorAutoHidden() -> Bool {
        return self.preferNavigationUIHidden
    }
    
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        UIView.performWithoutAnimation {
            self.transitionToSize?(size, coordinator.transitionDuration)
        }
    }
    
    override func loadView() {
        self.view = WindowRootViewControllerView()
        self.view.isOpaque = false
        self.view.backgroundColor = nil
        
        self.updatePreviewingRegistration()
    }
    
    private var previewingContext: AnyObject?
    
    private func updatePreviewingRegistration() {
        var shouldRegister = false
        
        var isVoiceOverRunning = false
        if #available(iOSApplicationExtension 10.0, *) {
            isVoiceOverRunning = UIAccessibility.isVoiceOverRunning
        }
        if !isVoiceOverRunning {
            shouldRegister = true
        }
        
        if shouldRegister != self.registeredForPreviewing {
            self.registeredForPreviewing = shouldRegister
            if shouldRegister {
                if #available(iOSApplicationExtension 9.0, *) {
                    self.previewingContext = self.registerForPreviewing(with: self, sourceView: self.view)
                }
            } else if let previewingContext = self.previewingContext {
                self.previewingContext = nil
                if let previewingContext = previewingContext as? UIViewControllerPreviewing {
                    if #available(iOSApplicationExtension 9.0, *) {
                        self.unregisterForPreviewing(withContext: previewingContext)
                    }
                }
            }
        }
    }
    
    private weak var previousPreviewingHostView: (UIView & PreviewingHostView)?
    
    public func previewingContext(_ previewingContext: UIViewControllerPreviewing, viewControllerForLocation location: CGPoint) -> UIViewController? {
        if UIAccessibility.isVoiceOverRunning {
            return nil
        }
        if #available(iOSApplicationExtension 9.0, *) {
            guard let result = self.view.hitTest(location, with: nil) else {
                return nil
            }
            if let (result, resultPoint) = tracePreviewingHostView(view: result, point: self.view.convert(location, to: result)), let delegate = result.previewingDelegate {
                self.previousPreviewingHostView = result
                if let (controller, rect) = delegate.controllerForLocation(previewingContext.sourceView, resultPoint) {
                    previewingContext.sourceRect = rect
                    return controller
                }
            }
        }
        return nil
    }
    
    public func previewingContext(_ previewingContext: UIViewControllerPreviewing, commit viewControllerToCommit: UIViewController) {
        if #available(iOSApplicationExtension 9.0, *) {
            if let previousPreviewingHostView = self.previousPreviewingHostView, let delegate = previousPreviewingHostView.previewingDelegate {
                delegate.commitController(viewControllerToCommit)
            }
            self.previousPreviewingHostView = nil
        }
    }
}

private final class NativeWindow: UIWindow, WindowHost {
    var updateSize: ((CGSize) -> Void)?
    var layoutSubviewsEvent: (() -> Void)?
    var updateIsUpdatingOrientationLayout: ((Bool) -> Void)?
    var updateToInterfaceOrientation: ((UIInterfaceOrientation) -> Void)?
    var presentController: ((ContainableController, PresentationSurfaceLevel, Bool, @escaping () -> Void) -> Void)?
    var presentControllerInGlobalOverlay: ((_ controller: ContainableController) -> Void)?
    var hitTestImpl: ((CGPoint, UIEvent?) -> UIView?)?
    var presentNativeImpl: ((UIViewController) -> Void)?
    var invalidateDeferScreenEdgeGestureImpl: (() -> Void)?
    var invalidatePreferNavigationUIHiddenImpl: (() -> Void)?
    var invalidateSupportedOrientationsImpl: (() -> Void)?
    var cancelInteractiveKeyboardGesturesImpl: (() -> Void)?
    var forEachControllerImpl: (((ContainableController) -> Void) -> Void)?
    var getAccessibilityElementsImpl: (() -> [Any]?)?
    
    override var frame: CGRect {
        get {
            return super.frame
        } set(value) {
            let sizeUpdated = super.frame.size != value.size
            
            var frameTransition: ContainedViewLayoutTransition = .immediate
            if #available(iOSApplicationExtension 9.0, *) {
                let duration = UIView.inheritedAnimationDuration
                if !duration.isZero {
                    frameTransition = .animated(duration: duration, curve: .easeInOut)
                }
            }
            if sizeUpdated, case let .animated(duration, curve) = frameTransition {
                let previousFrame = super.frame
                super.frame = value
                self.layer.animateFrame(from: previousFrame, to: value, duration: duration, timingFunction: curve.timingFunction)
            } else {
                super.frame = value
            }
            
            if sizeUpdated {
                self.updateSize?(value.size)
            }
        }
    }
    
    override var bounds: CGRect {
        get {
            return super.bounds
        }
        set(value) {
            let sizeUpdated = super.bounds.size != value.size
            super.bounds = value
            
            if sizeUpdated {
                self.updateSize?(value.size)
            }
        }
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        if let gestureRecognizers = self.gestureRecognizers {
            for recognizer in gestureRecognizers {
                recognizer.delaysTouchesBegan = false
            }
        }
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        self.layoutSubviewsEvent?()
    }
    
    override func _update(toInterfaceOrientation arg1: Int32, duration arg2: Double, force arg3: Bool) {
        self.updateIsUpdatingOrientationLayout?(true)
        super._update(toInterfaceOrientation: arg1, duration: arg2, force: arg3)
        self.updateIsUpdatingOrientationLayout?(false)
        
        let orientation = UIInterfaceOrientation(rawValue: Int(arg1)) ?? .unknown
        self.updateToInterfaceOrientation?(orientation)
    }
    
    func present(_ controller: ContainableController, on level: PresentationSurfaceLevel, blockInteraction: Bool, completion: @escaping () -> Void) {
        self.presentController?(controller, level, blockInteraction, completion)
    }
    
    func presentInGlobalOverlay(_ controller: ContainableController) {
        self.presentControllerInGlobalOverlay?(controller)
    }
    
    func presentNative(_ controller: UIViewController) {
        self.presentNativeImpl?(controller)
    }
    
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        return self.hitTestImpl?(point, event)
    }
    
    func invalidateDeferScreenEdgeGestures() {
        self.invalidateDeferScreenEdgeGestureImpl?()
    }
    
    func invalidatePreferNavigationUIHidden() {
        self.invalidatePreferNavigationUIHiddenImpl?()
    }
    
    func invalidateSupportedOrientations() {
        self.invalidateSupportedOrientationsImpl?()
    }
    
    func cancelInteractiveKeyboardGestures() {
        self.cancelInteractiveKeyboardGesturesImpl?()
    }
    
    func forEachController(_ f: (ContainableController) -> Void) {
        self.forEachControllerImpl?(f)
    }
}

public func nativeWindowHostView() -> (UIWindow & WindowHost, WindowHostView) {
    let window = NativeWindow(frame: UIScreen.main.bounds)
    
    let rootViewController = WindowRootViewController()
    window.rootViewController = rootViewController
    rootViewController.viewWillAppear(false)
    rootViewController.view.frame = CGRect(origin: CGPoint(), size: window.bounds.size)
    rootViewController.viewDidAppear(false)
    
    let hostView = WindowHostView(containerView: rootViewController.view, eventView: window, isRotating: {
        return window.isRotating()
    }, updateSupportedInterfaceOrientations: { orientations in
        rootViewController.orientations = orientations
    }, updateDeferScreenEdgeGestures: { edges in
        rootViewController.gestureEdges = edges
    }, updatePreferNavigationUIHidden: { value in
        rootViewController.preferNavigationUIHidden = value
    })
    
    rootViewController.transitionToSize = { [weak hostView] size, duration in
        hostView?.updateSize?(size, duration)
    }
    
    window.updateSize = { _ in
    }
    
    window.layoutSubviewsEvent = { [weak hostView] in
        hostView?.layoutSubviews?()
    }
    
    window.updateIsUpdatingOrientationLayout = { [weak hostView] value in
        hostView?.isUpdatingOrientationLayout = value
    }
    
    window.updateToInterfaceOrientation = { [weak hostView] orientation in
        hostView?.updateToInterfaceOrientation?(orientation)
    }
    
    window.presentController = { [weak hostView] controller, level, blockInteraction, completion in
        hostView?.present?(controller, level, blockInteraction, completion)
    }
    
    window.presentControllerInGlobalOverlay = { [weak hostView] controller in
        hostView?.presentInGlobalOverlay?(controller)
    }
    
    window.presentNativeImpl = { [weak hostView] controller in
        hostView?.presentNative?(controller)
    }
    
    window.hitTestImpl = { [weak hostView] point, event in
        return hostView?.hitTest?(point, event)
    }
    
    window.invalidateDeferScreenEdgeGestureImpl = { [weak hostView] in
        return hostView?.invalidateDeferScreenEdgeGesture?()
    }
    
    window.invalidatePreferNavigationUIHiddenImpl = { [weak hostView] in
        return hostView?.invalidatePreferNavigationUIHidden?()
    }
    
    window.invalidateSupportedOrientationsImpl = { [weak hostView] in
        return hostView?.invalidateSupportedOrientations?()
    }
    
    window.cancelInteractiveKeyboardGesturesImpl = { [weak hostView] in
        hostView?.cancelInteractiveKeyboardGestures?()
    }
    
    window.forEachControllerImpl = { [weak hostView] f in
        hostView?.forEachController?(f)
    }
    
    window.getAccessibilityElementsImpl = { [weak hostView] in
        return hostView?.getAccessibilityElements?()
    }
    
    rootViewController.presentController = { [weak hostView] controller, level, animated, completion in
        if let hostView = hostView {
            hostView.present?(LegacyPresentedController(legacyController: controller, presentation: .custom), level, false, completion ?? {})
            completion?()
        }
    }
    
    return (window, hostView)
}
