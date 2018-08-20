/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Convenience extensions on system types used in this project.
为本项目中的系统类型提供便利扩展.
*/

import Foundation
import ARKit

// Convenience accessors for Asset Catalog named colors.
// 便利访问器,访问Asset Catalog中命名的颜色.
extension UIColor {
    static let appYellow = UIColor(named: "appYellow")!
    static let appLightYellow = UIColor(named: "appLightYellow")!
    static let appBrown = UIColor(named: "appBrown")!
    static let appGreen = UIColor(named: "appGreen")!
    static let appBlue = UIColor(named: "appBlue")!
    static let appLightBlue = UIColor(named: "appLightBlue")!
    static let appGray = UIColor(named: "appGray")!
}

enum Axis {
    case x
    case y
    case z
    
    var normal: float3 {
        switch self {
        case .x:
            return float3(1, 0, 0)
        case .y:
            return float3(0, 1, 0)
        case .z:
            return float3(0, 0, 1)
        }
    }
}

struct PlaneDrag {
    var planeTransform: float4x4
    var offset: float3
}

extension simd_quatf {
    init(angle: Float, axis: Axis) {
        self.init(angle: angle, axis: axis.normal)
    }
}

extension float4x4 {
    var position: float3 {
        return columns.3.xyz
    }
}

extension float4 {
    var xyz: float3 {
        return float3(x, y, z)
    }

    init(_ xyz: float3, _ w: Float) {
        self.init(xyz.x, xyz.y, xyz.z, w)
    }
}

extension SCNMaterial {
    
    static func material(withDiffuse diffuse: Any?, respondsToLighting: Bool = false, isDoubleSided: Bool = true) -> SCNMaterial {
        let material = SCNMaterial()
        material.diffuse.contents = diffuse
        material.isDoubleSided = isDoubleSided
        if respondsToLighting {
            material.locksAmbientWithDiffuse = true
        } else {
            material.locksAmbientWithDiffuse = false
            material.ambient.contents = UIColor.black
            material.lightingModel = .constant
        }
        return material
    }
}

struct Ray {
    let origin: float3
    let direction: float3
    let endPoint: float3
    
    init(origin: float3, direction: float3) {
        self.origin = origin
        self.direction = direction
        self.endPoint = origin + direction
    }
    
    init(normalFrom pointOfView: SCNNode, length: Float) {
        let cameraNormal = normalize(pointOfView.simdWorldFront) * length
        self.init(origin: pointOfView.simdWorldPosition, direction: cameraNormal)
    }
}

extension ARSCNView {
    
    func unprojectPointLocal(_ point: CGPoint, ontoPlane planeTransform: float4x4) -> float3? {
        guard let result = unprojectPoint(point, ontoPlane: planeTransform) else {
            return nil
        }
        
        // Convert the result into the plane's local coordinate system.
        // 转换结果到平面的本地坐标系中.
        let point = float4(result, 1)
        let localResult = planeTransform.inverse * point
        return localResult.xyz
    }
    
    func smartHitTest(_ point: CGPoint) -> ARHitTestResult? {
        let hitTestResults = hitTest(point, types: .featurePoint)
        guard !hitTestResults.isEmpty else { return nil }
        
        for result in hitTestResults {
            // Return the first result which is between 20 cm and 3 m away from the user.
            // 返回距离用户20cm到3m的第一个结果.
            if result.distance > 0.2 && result.distance < 3 {
                return result
            }
        }
        return nil
    }
    
    func stopPlaneDetection() {
        if let configuration = session.configuration as? ARObjectScanningConfiguration {
            configuration.planeDetection = []
            session.run(configuration)
        }
    }
}

extension SCNNode {
    
    /// Wrapper for SceneKit function to use SIMD vectors and a typed dictionary.
    // 对SceneKit函数的包装,让其可以使用SIMD向量和类型化的字典.
    open func hitTestWithSegment(from pointA: float3, to pointB: float3, options: [SCNHitTestOption: Any]? = nil) -> [SCNHitTestResult] {
        if let options = options {
            var rawOptions = [String: Any]()
            for (key, value) in options {
                switch (key, value) {
                case (_, let bool as Bool):
                    rawOptions[key.rawValue] = NSNumber(value: bool)
                case (.searchMode, let searchMode as SCNHitTestSearchMode):
                    rawOptions[key.rawValue] = NSNumber(value: searchMode.rawValue)
                case (.rootNode, let object as AnyObject):
                    rawOptions[key.rawValue] = object
                default:
                    fatalError("unexpected key/value in SCNHitTestOption dictionary")
                }
            }
            return hitTestWithSegment(from: SCNVector3(pointA), to: SCNVector3(pointB), options: rawOptions)
        } else {
            return hitTestWithSegment(from: SCNVector3(pointA), to: SCNVector3(pointB))
        }
    }
    
    func load3DModel(from url: URL) -> SCNNode? {
        guard let scene = try? SCNScene(url: url, options: nil) else {
            print("Error: Failed to load 3D model from file \(url)")
            return nil
        }
        
        let node = SCNNode()
        for child in scene.rootNode.childNodes {
            node.addChildNode(child)
        }
        
        // If there are no light sources in the model, add some
        // 如果模型中没有光源,添加一些光源.
        let lightNodes = node.childNodes(passingTest: { node, _ in
            return node.light != nil
        })
        if lightNodes.isEmpty {
            let ambientLight = SCNLight()
            ambientLight.type = .ambient
            ambientLight.intensity = 100
            let ambientLightNode = SCNNode()
            ambientLightNode.light = ambientLight
            node.addChildNode(ambientLightNode)
            
            let directionalLight = SCNLight()
            directionalLight.type = .directional
            directionalLight.intensity = 500
            let directionalLightNode = SCNNode()
            directionalLightNode.light = directionalLight
            node.addChildNode(directionalLightNode)
        }
        
        return node
    }
    
    func displayNodeHierarchyOnTop(_ isOnTop: Bool) {
        // Recursivley traverses the node's children to update the rendering order depending on the `isOnTop` parameter.
        // 递归遍历节点的子元素,并根据'isOnTop'参数来更新渲染顺序.
        func updateRenderOrder(for node: SCNNode) {
            node.renderingOrder = isOnTop ? 2 : 0
            
            for material in node.geometry?.materials ?? [] {
                material.readsFromDepthBuffer = !isOnTop
            }
            
            for child in node.childNodes {
                updateRenderOrder(for: child)
            }
        }
        
        updateRenderOrder(for: self)
    }
}

extension CGPoint {
    /// Returns the length of a point when considered as a vector. (Used with gesture recognizers.)
    // 将点当做向量,返回长度.(用在手势识别器中.)
    var length: CGFloat {
        return sqrt(x * x + y * y)
    }
    
    static func +(left: CGPoint, right: CGPoint) -> CGPoint {
        return CGPoint(x: left.x + right.x, y: left.y + right.y)
    }
}

func dragPlaneTransform(for dragRay: Ray, cameraPos: float3) -> float4x4 {
    
    let camToRayOrigin = normalize(dragRay.origin - cameraPos)
    
    // Create a transform for a XZ-plane. This transform can be passed to unproject() to
    // map the user's touch position in screen space onto that plane in 3D space.
    // The plane's transform is constructed such that:
    // 1. The ray along which we want to drag the object is the plane's X axis.
    // 2. The plane's Z axis is ortogonal to the X axis and orthogonal to the vector
    //    from the camera to the object.
    //
    // Defining the plane this way has two main benefits:
    // 1. Since we want to drag the object along an axis (not on a plane), we need to
    //    do one more projection from the plane's 2D space to a 1D axis. Since the axis to
    //    drag on is the plane's X-axis, we can later simply convert the un-projected point
    //    into the plane's local coordinate system and use the value on the X axis.
    // 2. The plane's Z-axis is chosen to maximize the plane's coverage of screen space.
    //    The unprojectPoint() method will stop returning positions if the user drags their
    //    finger on the screen across the plane's horizon, leading to a bad user experience.
    //    So the ideal plane is parallel or almost parallel to the screen, but this is not
    //    possible when dragging along an axis which is pointing at the camera. For that case
    //    we try to find a plane which covers as much screen space as possible.
    // 创建一个XZ-平面的变换.该变换可以被传递给unproject(),用来将屏幕空间的用户触摸位置,投射到3D空间内的一个平面上.平面的变换是由一个给定的法向量得到的.
    // 这个平面的变换是这样构建的:
    // 1. 将沿拖拽物体方向的射线,作为平面的X轴.
    // 2. 平面的Z轴,同时垂直于X轴和相机到物体的射线.
    // 这样定义平面有两个主要的好处:
    // 1. 因为我们只希望沿着一个轴方向上拖拽物体(不是在平面上随意拖动),所以我们需要再做一个投影,从平面的2D空间投影到1D坐标轴上.
    //    因为拖动的轴就是平面的X轴,我们稍后只需要简单地转换未投影点到平面的本地坐标系中,并使用X轴上的值就可以了.
    // 2. 平面的Z轴的选择,是为了最大化平面在屏幕上的覆盖率.
    //    因为如果用户在屏幕上沿平面的水平方向来滑动手指时,unprojectPoint()方法将会停止返回位置,这会让用户体验很差.
    //    所以,理想的平面应该是平行于,或近似平行于屏幕的,但是这样的话,当拖拽的轴是指向屏幕的时候,就无法操作了.
    //    为此,我们试着找到一个平面,可以尽可能多的覆盖屏幕空间.
    let xVector = dragRay.direction
    let zVector = normalize(cross(xVector, camToRayOrigin))
    let yVector = normalize(cross(xVector, zVector))
    
    return float4x4([float4(xVector, 0),
                     float4(yVector, 0),
                     float4(zVector, 0),
                     float4(dragRay.origin, 1)])
}

func dragPlaneTransform(forPlaneNormal planeNormalRay: Ray, camera: SCNNode) -> float4x4 {
    
    // Create a transform for a XZ-plane. This transform can be passed to unproject() to
    // map the user's touch position in screen space onto that plane in 3D space.
    // The plane's transform is constructed from a given normal.
    // 创建一个XZ-平面的变换.该变换可以被传递给unproject(),用来将屏幕空间的用户触摸位置,投射到3D空间内的一个平面上.平面的变换是由一个给定的法向量得到的.
    let yVector = normalize(planeNormalRay.direction)
    let xVector = cross(yVector, camera.simdWorldRight)
    let zVector = normalize(cross(xVector, yVector))
    
    return float4x4([float4(xVector, 0),
                     float4(yVector, 0),
                     float4(zVector, 0),
                     float4(planeNormalRay.origin, 1)])
}

extension ARReferenceObject {
    func mergeInBackground(with otherReferenceObject: ARReferenceObject, completion: @escaping (ARReferenceObject?, Error?) -> Void) {
        DispatchQueue.global(qos: .background).async {
            do {
                let mergedObject = try self.merging(otherReferenceObject)
                DispatchQueue.main.async {
                    completion(mergedObject, nil)
                }
            } catch {
                DispatchQueue.main.async {
                    completion(nil, error)
                }
            }
        }
    }
}
