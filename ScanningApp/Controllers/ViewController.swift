/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Main view controller for the object scanning UI.
物体扫瞄UI界面的主控制器.
*/

import UIKit
import SceneKit
import ARKit

class ViewController: UIViewController, ARSCNViewDelegate, ARSessionDelegate, UIDocumentPickerDelegate {
    
    static let appStateChangedNotification = Notification.Name("ApplicationStateChanged")
    static let appStateUserInfoKey = "AppState"
    
    static var instance: ViewController?
    
    @IBOutlet weak var sceneView: ARSCNView!
    @IBOutlet weak var blurView: UIVisualEffectView!
    @IBOutlet weak var nextButton: RoundedButton!
    var backButton: UIBarButtonItem!
    var addToScanButton: UIBarButtonItem!
    @IBOutlet weak var instructionView: UIVisualEffectView!
    @IBOutlet weak var instructionLabel: MessageLabel!
    @IBOutlet weak var loadModelButton: RoundedButton!
    @IBOutlet weak var flashlightButton: FlashlightButton!
    @IBOutlet weak var navigationBar: UINavigationBar!
    @IBOutlet weak var sessionInfoView: UIVisualEffectView!
    @IBOutlet weak var sessionInfoLabel: UILabel!
    @IBOutlet weak var toggleInstructionsButton: RoundedButton!
    
    internal var internalState: State = .startARSession
    
    internal var scan: Scan?
    
    private var initialARReferenceObject: ARReferenceObject?
    var referenceObjectToMerge: ARReferenceObject?
    
    internal var testRun: TestRun?
    
    internal var messageExpirationTimer: Timer?
    internal var startTimeOfLastMessage: TimeInterval?
    internal var expirationTimeOfLastMessage: TimeInterval?
    
    internal var screenCenter = CGPoint()
    
    var modelURL: URL? {
        didSet {
            if let url = modelURL {
                displayMessage("3D model \"\(url.lastPathComponent)\" received.", expirationTime: 3.0)
            }
            if let scannedObject = self.scan?.scannedObject {
                scannedObject.set3DModel(modelURL)
            }
            if let dectectedObject = self.testRun?.detectedObject {
                dectectedObject.set3DModel(modelURL)
            }
        }
    }
    
    var instructionsVisible: Bool = true {
        didSet {
            instructionView.isHidden = !instructionsVisible
            toggleInstructionsButton.toggledOn = instructionsVisible
        }
    }
    
    // MARK: - Application Lifecycle
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        ViewController.instance = self
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        sceneView.session.pause()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        sceneView.delegate = self
        sceneView.session.delegate = self
        
        // Prevent the screen from being dimmed after a while.
        // 阻止屏幕变暗休眠
        UIApplication.shared.isIdleTimerDisabled = true
        
        let notificationCenter = NotificationCenter.default
        notificationCenter.addObserver(self, selector: #selector(scanningStateChanged), name: Scan.stateChangedNotification, object: nil)
        notificationCenter.addObserver(self, selector: #selector(ghostBoundingBoxWasCreated),
                                       name: ScannedObject.ghostBoundingBoxCreatedNotification, object: nil)
        notificationCenter.addObserver(self, selector: #selector(ghostBoundingBoxWasRemoved),
                                       name: ScannedObject.ghostBoundingBoxRemovedNotification, object: nil)
        notificationCenter.addObserver(self, selector: #selector(boundingBoxWasCreated),
                                       name: ScannedObject.boundingBoxCreatedNotification, object: nil)
        notificationCenter.addObserver(self, selector: #selector(scanPercentageChanged),
                                       name: BoundingBox.scanPercentageChangedNotification, object: nil)
        notificationCenter.addObserver(self, selector: #selector(boundingBoxPositionOrExtentChanged(_:)),
                                       name: BoundingBox.extentChangedNotification, object: nil)
        notificationCenter.addObserver(self, selector: #selector(boundingBoxPositionOrExtentChanged(_:)),
                                       name: BoundingBox.positionChangedNotification, object: nil)
        notificationCenter.addObserver(self, selector: #selector(objectOriginPositionChanged(_:)),
                                       name: ObjectOrigin.positionChangedNotification, object: nil)
        notificationCenter.addObserver(self, selector: #selector(displayWarningIfInLowPowerMode),
                                       name: Notification.Name.NSProcessInfoPowerStateDidChange, object: nil)
        
        setupNavigationBar()
        
        displayWarningIfInLowPowerMode()
        
        // Make sure the application launches in .startARSession state.
        // 确保启动状态为.startARSession.
        // Entering this state will run() the ARSession.
        // 进入该状态将会调用run() 启动 ARSession
        state = .startARSession
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        // Store the screen center location after the view's bounds did change,
        // so it can be retrieved later from outside the main thread.
        // 在视图尺寸变化后储存屏幕中心的位置,这样就可以在主线程外使用屏幕中心位置变量.
        screenCenter = sceneView.center
    }
    
    // MARK: - UI Event Handling
    
    @IBAction func restartButtonTapped(_ sender: Any) {
        if let scan = scan, scan.boundingBoxExists {
            let title = "Start over?"
            let message = "Discard the current scan and start over?"
            self.showAlert(title: title, message: message, buttonTitle: "Yes", showCancel: true) { _ in
                self.state = .startARSession
            }
        } else if testRun != nil {
            let title = "Start over?"
            let message = "Discard this scan and start over?"
            self.showAlert(title: title, message: message, buttonTitle: "Yes", showCancel: true) { _ in
                self.state = .startARSession
            }
        } else {
            self.state = .startARSession
        }
    }
    
    func backFromBackground() {
        if state == .scanning {
            let title = "Warning: Scan may be broken"
            let message = "The scan was interrupted. It is recommended to restart the scan."
            let buttonTitle = "Restart Scan"
            self.showAlert(title: title, message: message, buttonTitle: buttonTitle, showCancel: true) { _ in
                self.state = .notReady
            }
        }
    }
    
    @IBAction func previousButtonTapped(_ sender: Any) {
        switchToPreviousState()
    }
    
    @IBAction func nextButtonTapped(_ sender: Any) {
        guard !nextButton.isHidden && nextButton.isEnabled else { return }
        switchToNextState()
    }
    
    @IBAction func addScanButtonTapped(_ sender: Any) {
        guard state == .testing else { return }
        let title = "Add new scan?"
        let message = "Stop testing this scan and add a second scan?"
        self.showAlert(title: title, message: message, buttonTitle: "Yes", showCancel: true) { _ in
            // Save the previously scanned object as the object to be merged into the next scan.
            // 保存前一个扫瞄过的物体,因为它会被合并到下一次扫瞄中.
            self.referenceObjectToMerge = self.testRun?.referenceObject
            self.state = .startARSession
        }
    }
    
    @IBAction func loadModelButtonTapped(_ sender: Any) {
        guard !loadModelButton.isHidden && loadModelButton.isEnabled else { return }
        
        let documentPicker = UIDocumentPickerViewController(documentTypes: ["com.pixar.universal-scene-description-mobile"], in: .import)
        documentPicker.delegate = self
        
        documentPicker.modalPresentationStyle = .overCurrentContext
        documentPicker.popoverPresentationController?.sourceView = self.loadModelButton
        documentPicker.popoverPresentationController?.sourceRect = self.loadModelButton.bounds
        
        DispatchQueue.main.async {
            self.present(documentPicker, animated: true, completion: nil)
        }
    }
    
    @IBAction func leftButtonTouchAreaTapped(_ sender: Any) {
        // A tap in the extended hit area on the lower left should cause a tap
        //  on the button that is currently visible at that location.
        // 点击左下角扩展区域,根据当前按键的显示或隐藏状态来响应点击.
        if !loadModelButton.isHidden {
            loadModelButtonTapped(self)
        } else if !flashlightButton.isHidden {
            toggleFlashlightButtonTapped(self)
        }
    }
    
    @IBAction func toggleFlashlightButtonTapped(_ sender: Any) {
        guard !flashlightButton.isHidden && flashlightButton.isEnabled else { return }
        flashlightButton.toggledOn = !flashlightButton.toggledOn
    }
    
    @IBAction func toggleInstructionsButtonTapped(_ sender: Any) {
        guard !toggleInstructionsButton.isHidden && toggleInstructionsButton.isEnabled else { return }
        instructionsVisible.toggle()
    }
    
    func displayInstruction(_ message: Message) {
        instructionLabel.display(message)
        instructionsVisible = true
    }
    
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard !urls.isEmpty else { return }
        modelURL = urls[0]
    }
    
    func showAlert(title: String, message: String, buttonTitle: String? = "OK", showCancel: Bool = false, buttonHandler: ((UIAlertAction) -> Void)? = nil) {
        print(title + "\n" + message)
        let alertController = UIAlertController(title: title, message: message, preferredStyle: .alert)
        if let buttonTitle = buttonTitle {
            alertController.addAction(UIAlertAction(title: buttonTitle, style: .default, handler: buttonHandler))
        }
        if showCancel {
            alertController.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        }
        DispatchQueue.main.async {
            self.present(alertController, animated: true, completion: nil)
        }
    }
    
    func testObjectDetection() {
        guard let scan = scan, scan.boundingBoxExists else {
            print("Error: Bounding box not yet created.")
            return
        }
        
        scan.createReferenceObject { scannedObject in
            if let object = scannedObject {
                self.testRun?.setReferenceObject(object, screenshot: scan.screenshot)

                // Delete the scan to make sure that users cannot go back from
                // testing to scanning, because:
                // 1. Testing and scanning require running the ARSession with different configurations,
                //    thus the scanned environment is lost when starting a test.
                // 2. We encourage users to move the scanned object during testing, which invalidates
                //    the feature point cloud which was captured during scanning.
                //  删除scan以防止用户从测试状态返回到扫瞄状态,因为:
                // 1. 测试和扫瞄需要ARSession运行在不同配置下,这样当启动测试状态时,扫瞄出环境就会丢失.
                // 2. 我们鼓励用户在测试期间移动被扫瞄过的物体,这会让扫瞄期间捕捉到的特征点云变为不可用.
                self.scan = nil
                self.displayInstruction(Message("""
                    Test detection of the object from different angles. Consider moving the object to different environments and test there.
                    """))
            } else {
                let title = "Scan failed"
                let message = "Saving the scan failed."
                let buttonTitle = "Restart Scan"
                self.showAlert(title: title, message: message, buttonTitle: buttonTitle, showCancel: false) { _ in
                    self.state = .startARSession
                }
            }
        }
    }
    
    func createAndShareReferenceObject() {
        guard let testRun = self.testRun, let object = testRun.referenceObject, let name = object.name else {
            print("Error: Missing scanned object.")
            return
        }
        
        let documentURL = FileManager.default.temporaryDirectory.appendingPathComponent(name + ".arobject")
        
        DispatchQueue.global().async {
            do {
                try object.export(to: documentURL, previewImage: testRun.previewImage)
            } catch {
                fatalError("Failed to save the file to \(documentURL)")
            }
            
            // Initiate a share sheet for the scanned object
            // 初始化分享页面, 用以分享被扫瞄物体.
            let airdropShareSheet = ShareScanViewController(sourceView: self.nextButton, sharedObject: documentURL)
            DispatchQueue.main.async {
                self.present(airdropShareSheet, animated: true, completion: nil)
            }
        }
    }
    
    var limitedTrackingTimer: Timer?
    
    func startLimitedTrackingTimer() {
        guard limitedTrackingTimer == nil else { return }
        
        limitedTrackingTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { _ in
            self.cancelLimitedTrackingTimer()
            guard let scan = self.scan else { return }
            if scan.state == .defineBoundingBox || scan.state == .scanning || scan.state == .adjustingOrigin {
                let title = "Limited Tracking"
                let message = "Low tracking quality - it is unlikely that a good reference object can be generated from this scan."
                let buttonTitle = "Restart Scan"
                
                self.showAlert(title: title, message: message, buttonTitle: buttonTitle, showCancel: true) { _ in
                    self.state = .startARSession
                }
            }
        }
    }
    
    func cancelLimitedTrackingTimer() {
        limitedTrackingTimer?.invalidate()
        limitedTrackingTimer = nil
    }
    
    var maxScanTimeTimer: Timer?
    
    func startMaxScanTimeTimer() {
        guard maxScanTimeTimer == nil else { return }
        
        let timeout: TimeInterval = 60.0 * 5
        
        maxScanTimeTimer = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) { _ in
            self.cancelMaxScanTimeTimer()
            guard self.state == .scanning else { return }
            let title = "Scan is taking too long"
            let message = "Scanning consumes a lot of resources. This scan has been running for \(Int(timeout)) s. Consider closing the app and letting the device rest for a few minutes."
            let buttonTitle = "OK"
            self.showAlert(title: title, message: message, buttonTitle: buttonTitle, showCancel: true)
        }
    }
    
    func cancelMaxScanTimeTimer() {
        maxScanTimeTimer?.invalidate()
        maxScanTimeTimer = nil
    }
    
    // MARK: - ARSessionDelegate
    
    func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        
        updateSessionInfoLabel(for: camera.trackingState)
        
        switch camera.trackingState {
        case .notAvailable:
            state = .notReady
        case .limited(let reason):
            switch state {
            case .startARSession:
                state = .notReady
            case .notReady, .testing:
                break
            case .scanning:
                if let scan = scan {
                    switch scan.state {
                    case .ready:
                        state = .notReady
                    case .defineBoundingBox, .scanning, .adjustingOrigin:
                        if reason == .relocalizing {
                            // If ARKit is relocalizing we should abort the current scan
                            // as this can cause unpredictable distortions of the map.
                            // 如果ARKit正在重定位,我们应该中止当前的扫瞄,因为这样会导致不可预知的地图失真.
                            print("Warning: ARKit is relocalizing")
                            
                            let title = "Warning: Scan may be broken"
                            let message = "A gap in tracking has occurred. It is recommended to restart the scan."
                            let buttonTitle = "Restart Scan"
                            self.showAlert(title: title, message: message, buttonTitle: buttonTitle, showCancel: true) { _ in
                                self.state = .notReady
                            }
                            
                        } else {
                            // Suggest the user to restart tracking after a while.
                            // 建议用户在一段时间后重启追踪.
                            startLimitedTrackingTimer()
                        }
                    }
                }
            }
        case .normal:
            if limitedTrackingTimer != nil {
                cancelLimitedTrackingTimer()
            }
            
            switch state {
            case .startARSession, .notReady:
                state = .scanning
            case .scanning, .testing:
                break
            }
        }
    }
    
    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        guard let frame = sceneView.session.currentFrame else { return }
        scan?.updateOnEveryFrame(frame)
        testRun?.updateOnEveryFrame()
    }
    
    func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
        if let objectAnchor = anchor as? ARObjectAnchor {
            if let testRun = self.testRun, objectAnchor.referenceObject == testRun.referenceObject {
                testRun.successfulDetection(objectAnchor)
                let messageText = """
                    Object successfully detected from this angle.

                    """ + testRun.statistics
                displayMessage(messageText, expirationTime: testRun.resultDisplayDuration)
            }
        } else if state == .scanning, let planeAnchor = anchor as? ARPlaneAnchor {
            scan?.scannedObject.tryToAlignWithPlanes([planeAnchor])
        }
    }
    
    func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
        if state == .scanning, let planeAnchor = anchor as? ARPlaneAnchor {
            scan?.scannedObject.tryToAlignWithPlanes([planeAnchor])
        }
    }
    
    func readFile(_ url: URL) {
        if url.pathExtension == "arobject" {
            loadReferenceObjectToMerge(from: url)
        } else if url.pathExtension == "usdz" {
            modelURL = url
        }
    }
    
    func loadReferenceObjectToMerge(from url: URL) {
        do {
            let receivedReferenceObject = try ARReferenceObject(archiveURL: url)
            if state == .testing {
                
                // Show activity indicator during the merge.
                // 在合并期间展示活动指示器.
                ViewController.instance?.showAlert(title: "", message: "Merging received scan into this scan...", buttonTitle: nil)
                
                // Try to merge the object which was just scanned with the existing one.
                // 如果刚才扫瞄的物体是已经存在的,尝试合并.
                self.testRun?.referenceObject?.mergeInBackground(with: receivedReferenceObject, completion: { (mergedObject, error) in
                    var title: String
                    var message: String
                    
                    if let mergedObject = mergedObject {
                        mergedObject.name = self.testRun?.referenceObject?.name
                        self.testRun?.setReferenceObject(mergedObject, screenshot: nil)
                        
                        title = "Merge successful"
                        message = "The received scan has been merged into this scan."
                    } else {
                        print("Error: Failed to merge scans. \(error?.localizedDescription ?? "")")
                        title = "Merge failed"
                        message = """
                        Merging the received scan into the current scan failed. Please make sure
                        that there is sufficient overlap between both scans and that the
                        lighting environment hasn't changed drastically.
                        """
                    }
                    
                    // Hide activity indicator and inform the user about the result of the merge.
                    // 隐藏活动指示器,并通知用户合并的结果.
                    ViewController.instance?.dismiss(animated: true) {
                        ViewController.instance?.showAlert(title: title, message: message, buttonTitle: "OK", showCancel: false)
                    }
                })
                
            } else {
                // Upon completion of a scan, we will try merging
                // the scan with this ARReferenceObject.
                // 扫瞄完成后,我们将尝试将scan合并到ARReferenceObject.
                referenceObjectToMerge = receivedReferenceObject
                displayMessage("Scan \"\(url.lastPathComponent)\" received. " +
                    "It will be merged with this scan before proceeding to Test mode.", expirationTime: 3.0)
            }
        } catch {
            let title = "File invalid"
            let message = "Loading the scanned object file failed."
            self.showAlert(title: title, message: message, buttonTitle: "OK", showCancel: false)
        }
    }
    
    @objc
    func scanPercentageChanged(_ notification: Notification) {
        guard let percentage = notification.userInfo?[BoundingBox.scanPercentageUserInfoKey] as? Int else { return }
        
        // Switch to the next state if the scan is complete.
        // 当扫瞄完成后,切换到下个状态.
        if percentage >= 100 {
            switchToNextState()
            return
        }
        DispatchQueue.main.async {
            self.setNavigationBarTitle("Scan (\(percentage)%)")
        }
    }
    
    @objc
    func boundingBoxPositionOrExtentChanged(_ notification: Notification) {
        guard let box = notification.object as? BoundingBox,
            let cameraPos = sceneView.pointOfView?.simdWorldPosition else { return }
        
        let xString = String(format: "width: %.2f", box.extent.x)
        let yString = String(format: "height: %.2f", box.extent.y)
        let zString = String(format: "length: %.2f", box.extent.z)
        let distanceFromCamera = String(format: "%.2f m", distance(box.simdWorldPosition, cameraPos))
        displayMessage("Current bounding box: \(distanceFromCamera) away\n\(xString) \(yString) \(zString)", expirationTime: 1.5)
    }
    
    @objc
    func objectOriginPositionChanged(_ notification: Notification) {
        guard let node = notification.object as? ObjectOrigin else { return }
        
        // Display origin position w.r.t. bounding box
        // 显示边界盒的原点位置.
        let xString = String(format: "x: %.2f", node.position.x)
        let yString = String(format: "y: %.2f", node.position.y)
        let zString = String(format: "z: %.2f", node.position.z)
        displayMessage("Current local origin position in meters:\n\(xString) \(yString) \(zString)", expirationTime: 1.5)
    }
    
    @objc
    func displayWarningIfInLowPowerMode() {
        if ProcessInfo.processInfo.isLowPowerModeEnabled {
            let title = "Low Power Mode is enabled"
            let message = "Performance may be impacted. For best scanning results, disable Low Power Mode in Settings > Battery, and restart the scan."
            let buttonTitle = "OK"
            self.showAlert(title: title, message: message, buttonTitle: buttonTitle, showCancel: false)
        }
    }
    
    override var shouldAutorotate: Bool {
        // Lock UI rotation after starting a scan
        // 开始扫瞄之后,锁定UI旋转.
        if let scan = scan, scan.state != .ready {
            return false
        }
        return true
    }
}
