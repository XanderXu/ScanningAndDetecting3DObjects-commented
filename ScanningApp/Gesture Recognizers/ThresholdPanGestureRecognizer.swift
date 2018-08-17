/*
See LICENSE folder for this sample’s licensing information.

Abstract:
A custom pan gesture reconizer that fires only when a threshold is passed.
一个自定义的平移手势识别器,只有超过阈值时才会触发.
*/

import UIKit.UIGestureRecognizerSubclass
import ARKit

class ThresholdPanGestureRecognizer: UIPanGestureRecognizer {
    
    /// The threshold in screen pixels after which this gesture is detected.
    // 屏幕像素阈值,超过后手势都会被检测到.
    private static var threshold: CGFloat = 30
    
    /// Indicates whether the currently active gesture has exceeded the threshold.
    // 指示当前活跃的手势是否已超过了阈值.
    private(set) var isThresholdExceeded = false
    
    /// The initial touch location when this gesture started.
    // 当手势开始时的初始触摸位置.
    private var initialLocation: CGPoint = .zero
    
    /// The offset in screen space to the manipulated object
    // 操纵物体时,在屏幕空间的位移.
    private var offsetToObject: CGPoint = .zero
    
    /// Observe when the gesture's `state` changes to reset the threshold.
    // 监听,当手势的'state'变化时,重置阈值.
    override var state: UIGestureRecognizer.State {
        didSet {
            switch state {
            case .possible, .began, .changed:
                break
            default:
                // Reset variables.
                // 重置变量.
                isThresholdExceeded = false
                initialLocation = .zero
            }
        }
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        
        initialLocation = location(in: view)
        
        if let viewController = ViewController.instance, let object = viewController.scan?.objectToManipulate {
            let objectPos = viewController.sceneView.projectPoint(object.worldPosition)
            offsetToObject.x = CGFloat(objectPos.x) - initialLocation.x
            offsetToObject.y = CGFloat(objectPos.y) - initialLocation.y
        }
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesMoved(touches, with: event)
        
        let translationMagnitude = translation(in: view).length
        
        if !isThresholdExceeded && translationMagnitude > ThresholdPanGestureRecognizer.threshold {
            isThresholdExceeded = true
            
            // Set the overall translation to zero as the gesture should now begin.
            // 设置总体平移为0,因为手势开始了.
            setTranslation(.zero, in: view)
        }
    }
        
    override func location(in view: UIView?) -> CGPoint {
        switch state {
        case .began, .changed:
            let correctedLocation = CGPoint(x: initialLocation.x + translation(in: view).x,
                                            y: initialLocation.y + translation(in: view).y)
            return correctedLocation
        default:
            return super.location(in: view)
        }
    }
    
    func offsetLocation(in view: UIView?) -> CGPoint {
        return location(in: view) + offsetToObject
    }
}
