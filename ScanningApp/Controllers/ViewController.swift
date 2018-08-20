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
    var mergeScanButton: UIBarButtonItem!
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
    
    var referenceObjectToMerge: ARReferenceObject?
    var referenceObjectToTest: ARReferenceObject?
    
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

        let title = "Merge another scan?"
        let message = """
            Merging multiple scan results improves detection.
            You can start a new scan now to merge into this one, or load an already scanned *.arobject file.
            """
        
        let alertController = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alertController.addAction(UIAlertAction(title: "Merge New Scan…", style: .default) { _ in
            // Save the previously scanned object as the object to be merged into the next scan.
            // 保存前一个扫瞄过的物体,因为它会被合并到下一次扫瞄中.
            self.referenceObjectToMerge = self.testRun?.referenceObject
            self.state = .startARSession
        })
        alertController.addAction(UIAlertAction(title: "Merge ARObject File…", style: .default) { _ in
            // Show a document picker to choose an existing scan
            // 显示文档选择器,来选择一个已存在的扫瞄结果
            self.showFilePickerForLoadingScan()
        })
        alertController.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        DispatchQueue.main.async {
            self.present(alertController, animated: true, completion: nil)
        }
    }
    
    func showFilePickerForLoadingScan() {
        let documentPicker = UIDocumentPickerViewController(documentTypes: ["com.apple.arobject"], in: .import)
        documentPicker.delegate = self
        
        documentPicker.modalPresentationStyle = .overCurrentContext
        documentPicker.popoverPresentationController?.barButtonItem = mergeScanButton
        
        DispatchQueue.main.async {
            self.present(documentPicker, animated: true, completion: nil)
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
        guard let url = urls.first else { return }
        readFile(url)
    }
    
    func showAlert(title: String, message: String, buttonTitle: String? = "OK", showCancel: Bool = false, buttonHandler: ((UIAlertAction) -> Void)? = nil) {
        print(title + "\n" + message)
        
        var actions = [UIAlertAction]()
        if let buttonTitle = buttonTitle {
            actions.append(UIAlertAction(title: buttonTitle, style: .default, handler: buttonHandler))
        }
        if showCancel {
            actions.append(UIAlertAction(title: "Cancel", style: .cancel))
        }
        self.showAlert(title: title, message: message, actions: actions)
    }
    
    func showAlert(title: String, message: String, actions: [UIAlertAction]) {
        let showAlertBlock = {
            let alertController = UIAlertController(title: title, message: message, preferredStyle: .alert)
            actions.forEach { alertController.addAction($0) }
            DispatchQueue.main.async {
                self.present(alertController, animated: true, completion: nil)
            }
        }
        
        if presentedViewController != nil {
            dismiss(animated: true) {
                showAlertBlock()
            }
        } else {
            showAlertBlock()
        }
    }
    
    func testObjectDetection() {
        // In case an object for testing has been received, use it right away...
        // 如果测试用的物体已经被接收到了,就直接使用...
        if let object = referenceObjectToTest {
            testObjectDetection(of: object)
            return
        }
        
        // ...otherwise attempt to create a reference object from the current scan.
        // ...否则就尝试从当前扫瞄中创建一个参考物体.
        guard let scan = scan, scan.boundingBoxExists else {
            print("Error: Bounding box not yet created.")
            return
        }
        
        scan.createReferenceObject { scannedObject in
            if let object = scannedObject {
                self.testObjectDetection(of: object)
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
    
    func testObjectDetection(of object: ARReferenceObject) {
        self.testRun?.setReferenceObject(object, screenshot: scan?.screenshot)
        
        // Delete the scan to make sure that users cannot go back from
        // testing to scanning, because:
        // 1. Testing and scanning require running the ARSession with different configurations,
        //    thus the scanned environment is lost when starting a test.
        // 2. We encourage users to move the scanned object during testing, which invalidates
        //    the feature point cloud which was captured during scanning.
        // 删除扫瞄结果,确保用户不能再从测试返回扫瞄流程,因为:
        // 1. 测试和扫瞄需要ARSession运行在不同的配置下,这样当开始测试时,扫瞄过的环境会丢失.
        // 2. 我们鼓励用户在测试期间移动扫瞄物体,这会让扫瞄期间捕捉到的特征点云失效.
        self.scan = nil
        self.displayInstruction(Message("""
                    Test detection of the object from different angles. Consider moving the object to different environments and test there.
                    """))
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
            
            // After a plane was found, disable plane detection for performance reasons.
            // 在平面被发现后,为了性能更好,禁用平面检测功能.
            sceneView.stopPlaneDetection()
        }
    }
    
    func readFile(_ url: URL) {
        if url.pathExtension == "arobject" {
            loadReferenceObjectToMerge(from: url)
        } else if url.pathExtension == "usdz" {
            modelURL = url
        }
    }
    
    fileprivate func mergeIntoCurrentScan(referenceObject: ARReferenceObject, from url: URL) {
        if self.state == .testing {
            
            // Show activity indicator during the merge.
            // 在合并期间展示活动指示器.
            ViewController.instance?.showAlert(title: "", message: "Merging other scan into this scan...", buttonTitle: nil)
            
            // Try to merge the object which was just scanned with the existing one.
           // 如果刚才扫瞄的物体是已经存在的,尝试合并.
            self.testRun?.referenceObject?.mergeInBackground(with: referenceObject, completion: { (mergedObject, error) in
                let alertController = UIAlertController(title: nil, message: nil, preferredStyle: .alert)
                
                if let mergedObject = mergedObject {
                    mergedObject.name = self.testRun?.referenceObject?.name
                    self.testRun?.setReferenceObject(mergedObject, screenshot: nil)
                    self.showAlert(title: "Merge successful", message: "The other scan has been merged into this scan.",
                                   buttonTitle: "OK", showCancel: false)
                    
                } else {
                    print("Error: Failed to merge scans. \(error?.localizedDescription ?? "")")
                    alertController.title = "Merge failed"
                    let message = """
                            Merging the other scan into the current scan failed. Please make sure
                            that there is sufficient overlap between both scans and that the
                            lighting environment hasn't changed drastically.
                            Which scan do you want to use to proceed testing?
                            """
                    let currentScan = UIAlertAction(title: "Use Current Scan", style: .default)
                    let otherScan = UIAlertAction(title: "Use Other Scan", style: .default) { _ in
                        self.testRun?.setReferenceObject(referenceObject, screenshot: nil)
                    }
                    self.showAlert(title: "Merge failed", message: message, actions: [currentScan, otherScan])
                }
            })
            
        } else {
            // Upon completion of a scan, we will try merging
            // the scan with this ARReferenceObject.
            // 扫瞄完成后,我们会尝试将扫瞄结果和ARReferenceObject进行合并.
            self.referenceObjectToMerge = referenceObject
            self.displayMessage("Scan \"\(url.lastPathComponent)\" received. " +
                "It will be merged with this scan before proceeding to Test mode.", expirationTime: 3.0)
        }
    }
    
    func loadReferenceObjectToMerge(from url: URL) {
        do {
            let receivedReferenceObject = try ARReferenceObject(archiveURL: url)
            
            // Ask the user if the received object should be merged into the current scan,
            // or if the received scan should be tested (and the current one discarded).
            // 询问用户,接收到的物体是否应该被合并到当前扫瞄中,或者扫瞄结果是否应该被测试(同时当前物体会被丢弃)
            let title = "Scan \"\(url.lastPathComponent)\" received"
            let message = """
                Do you want to merge the received scan into the current scan,
                or test only the received scan, discarding the current scan?
                """
            let merge = UIAlertAction(title: "Merge Into This Scan", style: .default) { _ in
                self.mergeIntoCurrentScan(referenceObject: receivedReferenceObject, from: url)
            }
            let test = UIAlertAction(title: "Test Received Scan", style: .default) { _ in
                self.referenceObjectToTest = receivedReferenceObject
                self.state = .testing
            }
            self.showAlert(title: title, message: message, actions: [merge, test])
            
        } catch {
            self.showAlert(title: "File invalid", message: "Loading the scanned object file failed.",
                           buttonTitle: "OK", showCancel: false)
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
