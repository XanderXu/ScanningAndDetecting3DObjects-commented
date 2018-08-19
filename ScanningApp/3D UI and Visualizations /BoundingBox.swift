/*
See LICENSE folder for this sample’s licensing information.

Abstract:
An interactive visualization of a bounding box in 3D space with movement and resizing controls.
一个互动的可视化的3D空间边界盒,带有移动和改变大小控制点.
*/

import Foundation
import ARKit

class BoundingBox: SCNNode {
    
    static let extentChangedNotification = Notification.Name("BoundingBoxExtentChanged")
    static let positionChangedNotification = Notification.Name("BoundingBoxPositionChanged")
    static let scanPercentageChangedNotification = Notification.Name("ScanPercentageChanged")
    static let scanPercentageUserInfoKey = "ScanPercentage"
    static let boxExtentUserInfoKey = "BoxExtent"
    
    var extent: float3 = float3(0.1, 0.1, 0.1) {
        didSet {
            extent = max(extent, minSize)
            updateVisualization()
            NotificationCenter.default.post(name: BoundingBox.extentChangedNotification,
                                            object: self)
        }
    }
    
    override var simdPosition: float3 {
        willSet(newValue) {
            if distance(newValue, simdPosition) > 0.001 {
                NotificationCenter.default.post(name: BoundingBox.positionChangedNotification,
                                                object: self)
            }
        }
    }
    
    var hasBeenAdjustedByUser = false
    private var maxDistanceToFocusPoint: Float = 0.05
    
    private var minSize: Float = 0.01
    
    private struct SideDrag {
        var side: BoundingBoxSide
        var planeTransform: float4x4
        var beginWorldPos: float3
        var beginExtent: float3
    }
    
    private var currentSideDrag: SideDrag?
    
    private var currentSidePlaneDrag: PlaneDrag?
    private var currentGroundPlaneDrag: PlaneDrag?
    
    private var wireframe: Wireframe?
    
    private var sidesNode = SCNNode()
    private var sides: [BoundingBoxSide.Position: BoundingBoxSide] = [:]
    
    private var color = UIColor.appYellow
    
    private var cameraRaysAndHitLocations: [(ray: Ray, hitLocation: float3)] = []
    private var frameCounter: Int = 0
    
    var progressPercentage: Int = 0
    private var isUpdatingCapturingProgress = false
    
    private var sceneView: ARSCNView
    
    internal var isSnappedToHorizontalPlane = false
    
    init(_ sceneView: ARSCNView) {
        self.sceneView = sceneView
        super.init()
        
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(self.scanningStateChanged(_:)),
                                               name: Scan.stateChangedNotification,
                                               object: nil)
        updateVisualization()
    }
    
    @objc
    private func scanningStateChanged(_ notification: Notification) {
        guard let state = notification.userInfo?[Scan.stateUserInfoKey] as? Scan.State else { return }
        switch state {
        case .ready, .defineBoundingBox:
            resetCapturingProgress()
            sides.forEach { $0.value.isHidden = false }
        case .scanning:
            sides.forEach { $0.value.isHidden = false }
        case .adjustingOrigin:
            // Hide the sides while adjusting the origin.
            // 在调整原点时隐藏所有的面.
            sides.forEach { $0.value.isHidden = true }
        }
    }
    
    func fitOverPointCloud(_ pointCloud: ARPointCloud, focusPoint: float3?) {
        var filteredPoints: [vector_float3] = []
        
        for point in pointCloud.points {
            if let focus = focusPoint {
                // Skip this point if it is more than maxDistanceToFocusPoint meters away from the focus point.
                // 如果该点距离焦点大于maxDistanceToFocusPoint,忽略该点.
                let distanceToFocusPoint = length(point - focus)
                if distanceToFocusPoint > maxDistanceToFocusPoint {
                    continue
                }
            }
            
            // Skip this point if it is an outlier (not at least 3 other points closer than 3 cm)
            // 如果是异常点,跳过该点(某个点周围3cm内至少要有3个点的其他点,否则不要该点)
            var nearbyPoints = 0
            for otherPoint in pointCloud.points {
                if distance(point, otherPoint) < 0.03 {
                    nearbyPoints += 1
                    if nearbyPoints >= 3 {
                        filteredPoints.append(point)
                        break
                    }
                }
            }
        }
        
        guard !filteredPoints.isEmpty else { return }
        
        var localMin = -extent / 2
        var localMax = extent / 2
        
        for point in filteredPoints {
            // The bounding box is in local coordinates, so convert point to local, too.
            // 边界盒是在本地坐标系中,所以也需要将点转换到本地坐标系中.
            let localPoint = self.simdConvertPosition(point, from: nil)
            
            localMin = min(localMin, localPoint)
            localMax = max(localMax, localPoint)
        }
        
        // Update the position & extent of the bounding box based on the new min & max values.
        // 根据最新的最小值&最大值,更新边界盒的位置和面积.
        self.simdPosition += (localMax + localMin) / 2
        self.extent = localMax - localMin
    }
    
    private func updateVisualization() {
        self.updateSides()
        self.updateWireframe()
    }
    
    private func updateWireframe() {
        // When this method is called the first time, create the wireframe and add them as child node.
        // 当该方法第一次被调用时,创建线框并将其添加为子节点.
        guard let wireframe = self.wireframe else {
            let wireframe = Wireframe(extent: self.extent, color: color)
            self.addChildNode(wireframe)
            self.wireframe = wireframe
            return
        }
        
        // Otherwise just update the wireframe's size and position.
        // 否则调整线框的尺寸和位置.
        wireframe.update(extent: self.extent)
    }
    
    private func updateSides() {
        // When this method is called the first time, create the sides and add them to the sidesNode.
        // 当该方法第一次被调用时,创建面并将其添加为子节点.
        guard sides.count == 6 else {
            createSides()
            self.addChildNode(sidesNode)
            return
        }
        
        // Otherwise just update the geometries's size and position.
        // 否则调整几何体的尺寸和位置.
        sides.forEach { $0.value.update(boundingBoxExtent: self.extent) }
    }
    
    private func createSides() {
        for position in BoundingBoxSide.Position.allCases {
            self.sides[position] = BoundingBoxSide(position, boundingBoxExtent: self.extent, color: self.color)
            self.sidesNode.addChildNode(self.sides[position]!)
        }
    }
    
    func startSideDrag(screenPos: CGPoint) {
        guard let camera = sceneView.pointOfView else { return }

        // Check if the user is starting the drag on one of the sides. If so, pull/push that side.
        // 检查用户是否开始拖拽某个面.如果是,拉/推这个面.
        let hitResults = sceneView.hitTest(screenPos, options: [
            .rootNode: sidesNode,
            .ignoreHiddenNodes: false])
        
        for result in hitResults {
            if let side = result.node.parent as? BoundingBoxSide {
                side.showZAxisExtensions()
                
                let sideNormalInWorld = normalize(self.simdConvertVector(side.normal, to: nil) -
                    self.simdConvertVector(float3(0), to: nil))
                
                let ray = Ray(origin: float3(result.worldCoordinates), direction: sideNormalInWorld)
                let transform = dragPlaneTransform(for: ray, cameraPos: camera.simdWorldPosition)
                
                currentSideDrag = SideDrag(side: side, planeTransform: transform, beginWorldPos: self.simdWorldPosition, beginExtent: self.extent)
                hasBeenAdjustedByUser = true
                return
            }
        }
    }
    
    func updateSideDrag(screenPos: CGPoint) {
        guard let drag = currentSideDrag else { return }
        
        // Compute a new position for this side of the bounding box based on the given screen position.
        // 根据给定的屏幕位置,计算边界盒的这个面的新位置.
        if let hitPos = sceneView.unprojectPointLocal(screenPos, ontoPlane: drag.planeTransform) {
            let movementAlongRay = hitPos.x

            // First column of the planeTransform is the ray along which the box
            // is manipulated, in world coordinates. The center of the bounding box
            // has be be moved by half of the finger's movement on that ray.
            // planeTransform的第一列就是边界盒在世界坐标系中被移动的方向.边界盒的中心点被移动的距离,就是这个方向上手指移动的一半.
            let originOffset = (drag.planeTransform.columns.0 * (movementAlongRay / 2)).xyz
            
            let extentOffset = drag.side.dragAxis.normal * movementAlongRay
            let newExtent = drag.beginExtent + extentOffset
            guard newExtent.x >= minSize && newExtent.y >= minSize && newExtent.z >= minSize else { return }
            
            // Push/pull a single side of the bounding box by a combination
            // of moving & changing the extent of the box.
            // 推/拉边界盒的单一个面,会同时移动盒子的位置&改变盒子的尺寸.
            self.simdWorldPosition = drag.beginWorldPos + originOffset
            self.extent = newExtent
        }
    }
    
    func endSideDrag() {
        guard let drag = currentSideDrag else { return }
        drag.side.hideZAxisExtensions()
        currentSideDrag = nil
    }
    
    func startSidePlaneDrag(screenPos: CGPoint) {
        guard let camera = sceneView.pointOfView else { return }

        let hitResults = sceneView.hitTest(screenPos, options: [
            .rootNode: sidesNode,
            .ignoreHiddenNodes: false])
        
        for result in hitResults {
            if let side = result.node.parent as? BoundingBoxSide {
                side.showXAxisExtensions()
                side.showYAxisExtensions()
                
                let sideNormalInWorld = normalize(self.simdConvertVector(side.dragAxis.normal, to: nil) -
                    self.simdConvertVector(float3(0), to: nil))
                
                let planeNormalRay = Ray(origin: float3(result.worldCoordinates), direction: sideNormalInWorld)
                let transform = dragPlaneTransform(forPlaneNormal: planeNormalRay, camera: camera)
                
                var offset = float3()
                if let hitPos = sceneView.unprojectPoint(screenPos, ontoPlane: transform) {
                    offset = self.simdWorldPosition - hitPos
                }
                
                currentSidePlaneDrag = PlaneDrag(planeTransform: transform, offset: offset)
                hasBeenAdjustedByUser = true
                return
            }
        }
    }
    
    func updateSidePlaneDrag(screenPos: CGPoint) {
        guard let drag = currentSidePlaneDrag else { return }
        if let hitPos = sceneView.unprojectPoint(screenPos, ontoPlane: drag.planeTransform) {
            self.simdWorldPosition = hitPos + drag.offset
            
            snapToHorizontalPlane()
        }
    }
    
    func endSidePlaneDrag() {
        currentSidePlaneDrag = nil
        hideExtensionsOnAllAxes()
        
        isSnappedToHorizontalPlane = false
    }
    
    func hideExtensionsOnAllAxes() {
        sides.forEach {
            $0.value.hideXAxisExtensions()
            $0.value.hideYAxisExtensions()
            $0.value.hideZAxisExtensions()
        }
    }
    
    func startGroundPlaneDrag(screenPos: CGPoint) {
        let dragPlane = self.simdWorldTransform
        var offset = float3(0)
        if let hitPos = sceneView.unprojectPoint(screenPos, ontoPlane: dragPlane) {
            offset = self.simdWorldPosition - hitPos
        }
        self.currentGroundPlaneDrag = PlaneDrag(planeTransform: dragPlane, offset: offset)
        hasBeenAdjustedByUser = true
    }
    
    func updateGroundPlaneDrag(screenPos: CGPoint) {
        sides[.bottom]?.showXAxisExtensions()
        sides[.bottom]?.showYAxisExtensions()
        
        guard let drag = currentGroundPlaneDrag else { return }
        if let hitPos = sceneView.unprojectPoint(screenPos, ontoPlane: drag.planeTransform) {
            self.simdWorldPosition = hitPos + drag.offset
        }
    }
    
    func endGroundPlaneDrag() {
        currentGroundPlaneDrag = nil
        sides[.bottom]?.hideXAxisExtensions()
        sides[.bottom]?.hideYAxisExtensions()
    }
    
    func isHit(screenPos: CGPoint) -> Bool {
        let hitResults = sceneView.hitTest(screenPos, options: [
            .rootNode: sidesNode,
            .ignoreHiddenNodes: false])
        
        for result in hitResults where (result.node.parent as? BoundingBoxSide) != nil {
            return true
        }
        return false
    }
    
    func resetCapturingProgress() {
        cameraRaysAndHitLocations.removeAll()
        for (_, side) in self.sides {
            side.tiles.forEach {
                $0.isCaptured = false
                $0.isHighlighted = false
                $0.updateVisualization()
            }
        }
    }
    
    func highlightCurrentTile() {
        guard let camera = sceneView.pointOfView, !self.contains(camera.simdWorldPosition) else { return }

        // Create a new hit test ray. A line segment defined by its start and end point
        // is used to hit test against bounding box tiles. The ray's length allows for
        // intersections if the user is no more than five meters away from the bounding box.
        // 创建一个新的命中测试射线.该线段起点是发出点(相机),终点则是命中边界盒图块的点.射线的长度决定了能否交互:如果用户距离边界盒超过五米,则不允许交互.
        let ray = Ray(from: camera, length: 5.0)
        
        for (_, side) in self.sides {
            for tile in side.tiles where tile.isHighlighted {
                tile.isHighlighted = false
            }
        }
        
        if let (tile, _) = tile(hitBy: ray) {
            tile.isHighlighted = true
        }
        
        // Update the opacity of all tiles.
        // 更新所有图块的不透明度.
        for (_, side) in self.sides {
            side.tiles.forEach { $0.updateVisualization() }
        }
    }
    
    func updateCapturingProgress() {
        guard let camera = sceneView.pointOfView, !self.contains(camera.simdWorldPosition) else { return }
        
        frameCounter += 1

        // Add new hit test rays at a lower frame rate to keep the list of previous rays
        // at a reasonable size.
        // 添加新的低帧率命中测试射线,以将先前射线列表保持在合理的大小.(每一帧都发射一个射线的话,射线列表就太多了)
        if frameCounter % 20 == 0 {
            frameCounter = 0
            
            // Create a new hit test ray. A line segment defined by its start and end point
            // is used to hit test against bounding box tiles. The ray's length allows for
            // intersections if the user is no more than five meters away from the bounding box.
            // 创建一个新的命中测试射线.该线段起点是发出点(相机),终点则是命中边界盒图块的点.射线的长度决定了能否交互:如果用户距离边界盒超过五米,则不允许交互.
            let currentRay = Ray(from: camera, length: 5.0)
            
            // Only remember the ray if it hit the bounding box,
            // and the hit location is significantly different from all previous hit locations.
            // 只有命中边界盒的射线才会被记录下来,并且命中位置必须明显不同与先前的其他命中位置.
            if let (_, hitLocation) = tile(hitBy: currentRay) {
                if isHitLocationDifferentFromPreviousRayHitTests(hitLocation) {
                    cameraRaysAndHitLocations.append((ray: currentRay, hitLocation: hitLocation))
                }
            }
        }
        
        // Update tiles at a frame rate that provides a trade-off between responsiveness and performance.
        // 以低帧率更新图块,以在响应和性能之间取得平衡.
        guard frameCounter % 10 == 0, !isUpdatingCapturingProgress else { return }
        
        self.isUpdatingCapturingProgress = true
        
        var capturedTiles: [Tile] = []
        
        // Perform hit tests with all previous rays.
        // 用以前所有的射线,执行命中测试.
        for hitTest in self.cameraRaysAndHitLocations {
            if let (tile, _) = self.tile(hitBy: hitTest.ray) {
                capturedTiles.append(tile)
                tile.isCaptured = true
            }
        }
        
        for (_, side) in self.sides {
            side.tiles.forEach {
                if !capturedTiles.contains($0) {
                    $0.isCaptured = false
                }
            }
        }
        
        // Update the opacity of all tiles.
        // 更新所有图块的不透明度.
        for (_, side) in self.sides {
            side.tiles.forEach { $0.updateVisualization() }
        }
        
        // Update scan percentage for all sides, except the bottom
        // 更新所有面的扫瞄进度,除了底面.
        var sum: Float = 0
        for (pos, side) in self.sides where pos != .bottom {
            sum += side.completion / 5.0
        }
        let progressPercentage: Int = min(Int(floor(sum * 100)), 100)
        if self.progressPercentage != progressPercentage {
            self.progressPercentage = progressPercentage
            NotificationCenter.default.post(name: BoundingBox.scanPercentageChangedNotification,
                                            object: self,
                                            userInfo: [BoundingBox.scanPercentageUserInfoKey: progressPercentage])
        }
        
        self.isUpdatingCapturingProgress = false
    }
    
    /// Returns true if the given location differs from all hit locations in the cameraRaysAndHitLocations array
    /// by at least the threshold distance.
    // 当给定的位置不同于cameraRaysAndHitLocations数组中所有的命中位置时(差别达到一定阈值).
    func isHitLocationDifferentFromPreviousRayHitTests(_ location: float3) -> Bool {
        let distThreshold: Float = 0.03
        for hitTest in cameraRaysAndHitLocations.reversed() {
            if distance(hitTest.hitLocation, location) < distThreshold {
                return false
            }
        }
        return true
    }
    
    private func tile(hitBy ray: Ray) -> (tile: Tile, hitLocation: float3)? {
        // Perform hit test with given ray
        // 以给定的射线执行命中测试.
        let hitResults = self.sceneView.scene.rootNode.hitTestWithSegment(from: ray.origin, to: ray.direction, options: [
            .ignoreHiddenNodes: false,
            .boundingBoxOnly: true,
            .searchMode: SCNHitTestSearchMode.all])
        
        // We cannot just look at the first result because we might have hits with other than the tile geometries.
        // 我们不能简单地只看第一个结果,因为我们可能命中了其他东西,而不是图块几何体.
        for result in hitResults {
            if let tile = result.node as? Tile {
                if let side = tile.parent as? BoundingBoxSide, side.isBusyUpdatingTiles {
                    continue
                }
                
                // Each ray should only hit one tile, so we can stop iterating through results if a hit was successful.
                // 每一个射线应该只命中一个图块,所以我们发现命中成功后就可以停止迭代了.
                return (tile: tile, hitLocation: float3(result.worldCoordinates))
            }
        }
        return nil
    }
    
    private func sidesForAxis(_ axis: Axis) -> [BoundingBoxSide?] {
        switch axis {
        case .x:
            return [sides[.left], sides[.right]]
        case .y:
            return [sides[.top], sides[.bottom]]
        case .z:
            return [sides[.front], sides[.back]]
        }
    }
    
    func updateOnEveryFrame() {
        if let frame = sceneView.session.currentFrame {
            // Check if the bounding box should align its bottom with a nearby plane.
            // 检查边界盒是否应该对齐到附近的平面.
            tryToAlignWithPlanes(frame.anchors)
        }
        
        sides.forEach { $0.value.updateVisualizationIfNeeded() }
    }
    
    func tryToAlignWithPlanes(_ anchors: [ARAnchor]) {
        guard !hasBeenAdjustedByUser, ViewController.instance?.scan?.state == .defineBoundingBox else { return }
        
        let bottomCenter = SCNVector3(x: position.x, y: position.y - extent.y / 2, z: position.z)
        
        var distanceToNearestPlane = Float.greatestFiniteMagnitude
        var offsetToNearestPlaneOnY: Float = 0
        var planeFound = false
        
        // Check which plane is nearest to the bounding box.
        // 检查哪个平面离边界盒最近.
        for anchor in anchors {
            guard let plane = anchor as? ARPlaneAnchor else {
                continue
            }
            guard let planeNode = sceneView.node(for: plane) else {
                continue
            }
            
            // Get the position of the bottom center of this bounding box in the plane's coordinate system.
            // 获取平面自身的坐标系中,该边界盒的底面中心的位置.
            let bottomCenterInPlaneCoords = planeNode.convertPosition(bottomCenter, from: parent)
            
            // Add 10% tolerance to the corners of the plane.
            // 为每个平面的拐角处添加10%的误差.
            let tolerance: Float = 0.1
            let minX = plane.center.x - plane.extent.x / 2 - plane.extent.x * tolerance
            let maxX = plane.center.x + plane.extent.x / 2 + plane.extent.x * tolerance
            let minZ = plane.center.z - plane.extent.z / 2 - plane.extent.z * tolerance
            let maxZ = plane.center.z + plane.extent.z / 2 + plane.extent.z * tolerance
            
            guard (minX...maxX).contains(bottomCenterInPlaneCoords.x) && (minZ...maxZ).contains(bottomCenterInPlaneCoords.z) else {
                continue
            }
            
            let offsetToPlaneOnY = bottomCenterInPlaneCoords.y
            let distanceToPlane = abs(offsetToPlaneOnY)
            
            if distanceToPlane < distanceToNearestPlane {
                distanceToNearestPlane = distanceToPlane
                offsetToNearestPlaneOnY = offsetToPlaneOnY
                planeFound = true
            }
        }
        
        guard planeFound else { return }
        
        // Check that the object is not already on the nearest plane (closer than 1 mm).
        // 检查物体,是否还没在最近的平面上(小于1mm).
        let epsilon: Float = 0.001
        guard distanceToNearestPlane > epsilon else { return }
        
        // Check if the nearest plane is close enough to the bounding box to "snap" to that
        // plane. The threshold is half of the bounding box extent on the y axis.
        // 检查最近的平面是否离边界盒足够近,足够近就可以"吸附"到这个平面上.这里的阈值就是边界盒在y轴上尺寸的一半.
        let maxDistance = extent.y / 2
        if distanceToNearestPlane < maxDistance && offsetToNearestPlaneOnY > 0 {
            // Adjust the bounding box position & extent such that the bottom of the box
            // aligns with the plane.
            // 调整边界盒的位置和尺寸,让盒子的底部对齐到平面上.
            simdPosition.y -= offsetToNearestPlaneOnY / 2
            extent.y += offsetToNearestPlaneOnY
        }
    }
    
    func contains(_ pointInWorld: float3) -> Bool {
        let localMin = -extent / 2
        let localMax = extent / 2
        
        // The bounding box is in local coordinates, so convert point to local, too.
        // 边界盒是在本地坐标系中,所以必须将点也转换到本地坐标系中.
        let localPoint = self.simdConvertPosition(pointInWorld, from: nil)
        
        return (localMin.x...localMax.x).contains(localPoint.x) &&
            (localMin.y...localMax.y).contains(localPoint.y) &&
            (localMin.z...localMax.z).contains(localPoint.z)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
