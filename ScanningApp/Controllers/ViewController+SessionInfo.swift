/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Managemenent of session information communication to the user.
管理与用户沟通的session信息.
*/

import UIKit
import ARKit

extension ViewController {
    
    func updateSessionInfoLabel(for trackingState: ARCamera.TrackingState) {
        // Update the UI to provide feedback on the state of the AR experience.
        // 更新UI,以提供AR过程中不同状态的反馈.
        var message: String = ""
        let stateString = state == .testing ? "Detecting" : "Scanning"
        
        switch trackingState {
            
        case .notAvailable:
            message = "\(stateString) not possible: \(trackingState.presentationString)"
            startTimeOfLastMessage = Date().timeIntervalSince1970
            expirationTimeOfLastMessage = 3.0
            
        case .limited:
            message = "\(stateString) might not work: \(trackingState.presentationString)"
            startTimeOfLastMessage = Date().timeIntervalSince1970
            expirationTimeOfLastMessage = 3.0
            
        default:
            // No feedback needed when tracking is normal.
            // Defer clearing the info label if the last message hasn't reached its expiration time.
            // 当追踪正常时,没反馈.
            // 当最后一条信息还未到期时,延迟消除info label.
            let now = Date().timeIntervalSince1970
            if let startTimeOfLastMessage = startTimeOfLastMessage,
                let expirationTimeOfLastMessage = expirationTimeOfLastMessage,
                now - startTimeOfLastMessage < expirationTimeOfLastMessage {
                let timeToKeepLastMessageOnScreen = expirationTimeOfLastMessage - (now - startTimeOfLastMessage)
                startMessageExpirationTimer(duration: timeToKeepLastMessageOnScreen)
            } else {
                // Otherwise hide the info label immediately.
                // 否则直接隐藏info label.
                self.sessionInfoLabel.text = ""
                self.sessionInfoView.isHidden = true
            }
            return
        }
        
        sessionInfoLabel.text = message
        sessionInfoView.isHidden = false
    }
    
    func displayMessage(_ message: String, expirationTime: TimeInterval) {
        startTimeOfLastMessage = Date().timeIntervalSince1970
        expirationTimeOfLastMessage = expirationTime
        DispatchQueue.main.async {
            self.sessionInfoLabel.text = message
            self.sessionInfoView.isHidden = false
            self.startMessageExpirationTimer(duration: expirationTime)
        }
    }
    
    func startMessageExpirationTimer(duration: TimeInterval) {
        cancelMessageExpirationTimer()
        
        messageExpirationTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { (timer) in
            self.cancelMessageExpirationTimer()
            self.sessionInfoLabel.text = ""
            self.sessionInfoView.isHidden = true
            
            self.startTimeOfLastMessage = nil
            self.expirationTimeOfLastMessage = nil
        }
    }
    
    func cancelMessageExpirationTimer() {
        messageExpirationTimer?.invalidate()
        messageExpirationTimer = nil
    }
}
