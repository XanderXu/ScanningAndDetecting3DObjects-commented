/*
See LICENSE folder for this sample’s licensing information.

Abstract:
A visualization of the 3D point cloud data during object scanning.
在物体扫瞄期间的3D点云数据可视化.
*/

import Foundation
import ARKit
import SceneKit

class ScannedPointCloud: SCNNode, PointCloud {
    
    private var pointNode = SCNNode()
    private var preliminaryPointsNode = SCNNode()
    
    // The latest known set of points inside the reference object.
    // 参考物体中最新获知的点的集合.
    private var referenceObjectPoints: [float3] = []
    
    // The current frame's set of points inside the reference object.
    // 参考物体的当前帧中的点的集合
    private var currentFramePoints: [float3] = []
    
    // The set of currently rendered points, in world coordinates.
    // Note: We render them in world coordinates instead of local coordinates to
    //       prevent rendering issues with points jittering e.g. when the
    //       bounding box is rotated.
    // 当前渲染出的点的集合,世界坐标系中.
    // 注意:我们在世界坐标系中而不是本地坐标系中渲染他们,是为了防止渲染时出现点抖动问题,例如当边界盒被旋转时.
    private var renderedPoints: [float3] = []
    
    // The set of points from the current frame, in world coordinates.
    // Note: These are preliminary since not all of them might be added
    //       to the reference object.
    // 当前帧中点的集合,世界坐标系中.
    // 注意: 这里只是初步的操作,因为并不是所有的点都会被加到参考物体上.
    private var renderedPreliminaryPoints: [float3] = []
    
    private var boundingBox: BoundingBox?
    
    override init() {
        super.init()
        
        addChildNode(pointNode)
        addChildNode(preliminaryPointsNode)
        
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(self.scanningStateChanged(_:)),
                                               name: Scan.stateChangedNotification,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(self.boundingBoxPositionOrExtentChanged(_:)),
                                               name: BoundingBox.extentChangedNotification,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(self.boundingBoxPositionOrExtentChanged(_:)),
                                               name: BoundingBox.positionChangedNotification,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(self.scannedObjectPositionChanged(_:)),
                                               name: ScannedObject.positionChangedNotification,
                                               object: nil)
    }
    
    @objc
    func boundingBoxPositionOrExtentChanged(_ notification: Notification) {
        guard let boundingBox = notification.object as? BoundingBox else { return }
        updateBoundingBox(boundingBox)
    }
    
    @objc
    func scannedObjectPositionChanged(_ notification: Notification) {
        guard let scannedObject = notification.object as? ScannedObject else { return }
        let boundingBox = scannedObject.boundingBox != nil ? scannedObject.boundingBox : scannedObject.ghostBoundingBox
        updateBoundingBox(boundingBox)
    }
    
    func updateBoundingBox(_ boundingBox: BoundingBox?) {
        self.boundingBox = boundingBox
    }
    
    func update(with pointCloud: ARPointCloud, localFor boundingBox: BoundingBox) {
        // Convert the points to world coordinates because we display them
        // in world coordinates.
        // 将点转换到世界坐标系中,因为我们要在世界坐标系中展示他们.
        var pointsInWorld: [float3] = []
        for point in pointCloud.points {
            pointsInWorld.append(boundingBox.simdConvertPosition(point, to: nil))
        }
        
        self.referenceObjectPoints = pointsInWorld
    }
    
    func update(with pointCloud: ARPointCloud) {
        self.currentFramePoints = pointCloud.points
    }
    
    func updateOnEveryFrame() {
        guard !self.isHidden else { return }
        guard !referenceObjectPoints.isEmpty, let boundingBox = boundingBox else {
            self.pointNode.geometry = nil
            self.preliminaryPointsNode.geometry = nil
            return
        }
        
        renderedPoints = []
        renderedPreliminaryPoints = []
        
        // Abort if the bounding box has no extent yet
        // 如果边界盒不再扩展,则中止.
        guard boundingBox.extent.x > 0 else { return }
        
        // Check which of the reference object's points and current frame's points are within the bounding box.
        // Note: The creation of the latest ARReferenceObject happens at a lower frequency
        //       than rendering and updates of the bounding box, so some of the points
        //       may no longer be inside of the box.
        // 检查参考物体的哪些点以及当前帧的哪些点位于边界盒中.
        // 注意: 最新的ARReferenceObject是以较低频率创建出来的,低于边界盒渲染和更新的频率,所以某些点可能已经不在边界盒里面了.
        renderedPoints = referenceObjectPoints.filter { boundingBox.contains($0) }
        renderedPreliminaryPoints = currentFramePoints.filter { boundingBox.contains($0) }
        
        self.pointNode.geometry = createVisualization(for: renderedPoints, color: .appYellow, size: 12)
        self.preliminaryPointsNode.geometry = createVisualization(for: renderedPreliminaryPoints, color: .appLightYellow, size: 12)
    }
    
    var count: Int {
        return renderedPoints.count
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc
    private func scanningStateChanged(_ notification: Notification) {
        guard let state = notification.userInfo?[Scan.stateUserInfoKey] as? Scan.State else { return }
        switch state {
        case .ready, .scanning, .defineBoundingBox:
            self.isHidden = false
        case .adjustingOrigin:
            self.isHidden = true
        }
    }
}
