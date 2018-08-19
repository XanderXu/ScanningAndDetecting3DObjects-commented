/*
See LICENSE folder for this sample’s licensing information.

Abstract:
An interactive visualization a single x/y/z coordinate axis for use in placing the origin/anchor point of a scanned object.
一个交互可视化,用于放置被扫瞄物体的x/y/z坐标轴的原点/锚点.
*/

import SceneKit

class ObjectOriginAxis: SCNNode {
    
    let axis: Axis
    
    private var flashTimer: Timer?
    private var flashDuration = 0.1
    
    // Whether this axis is currently being highlighted -
    // then it will be displayed white.
    // 这个轴当前是否是高亮的--高亮会显示为白色.
    var isHighlighted: Bool = false {
        didSet {
            let emissionColor = isHighlighted ? UIColor.white : UIColor.black
            childNodes.forEach { $0.geometry?.materials.first?.emission.contents = emissionColor }
        }
    }
    
    func flash() {
        self.isHighlighted = true
        
        self.flashTimer?.invalidate()
        self.flashTimer = Timer.scheduledTimer(withTimeInterval: flashDuration, repeats: false) { _ in
            self.isHighlighted = false
        }
    }
    
    // MARK: - Initializers
    
    init(axis: Axis, length: Float, thickness: Float, radius: CGFloat, handleSize: CGFloat) {
        self.axis = axis
        super.init()
        
        var color: UIColor
        var texture: UIImage?
        var dimensions: float3
        let position = axis.normal * (length / 2.0)
        let axisHandlePosition = axis.normal * length
        
        switch axis {
        case .x:
            color = UIColor.red
            texture = #imageLiteral(resourceName: "handle_red")
            dimensions = float3(length, thickness, thickness)
        case .y:
            color = UIColor.green
            texture = #imageLiteral(resourceName: "handle_green")
            dimensions = float3(thickness, length, thickness)
        case .z:
            color = UIColor.blue
            texture = #imageLiteral(resourceName: "handle_blue")
            dimensions = float3(thickness, thickness, length)
        }
        
        let axisGeo = SCNBox(width: CGFloat(dimensions.x),
                             height: CGFloat(dimensions.y),
                             length: CGFloat(dimensions.z),
                             chamferRadius: radius)
        axisGeo.materials = [SCNMaterial.material(withDiffuse: color)]
        let axis = SCNNode(geometry: axisGeo)
        
        let axisHandleGeo = SCNPlane(width: handleSize, height: handleSize)
        axisHandleGeo.materials = [SCNMaterial.material(withDiffuse: texture, respondsToLighting: false)]
        let axisHandle = SCNNode(geometry: axisHandleGeo)
        axisHandle.constraints = [SCNBillboardConstraint()]
        
        axis.simdPosition = position
        axisHandle.simdPosition = axisHandlePosition
        
        // Increase the axis handle geometry's bounding box that is used for hit testing to make it easier to hit.
        // 增大坐标轴操作手柄的几何体的边界盒尺寸,这样可以让命中测试更容易命中.
        let min = axisHandle.boundingBox.min
        let max = axisHandle.boundingBox.max
        let padding = Float(handleSize) * 0.8
        axisHandle.boundingBox.min = SCNVector3(min.x - padding, min.y - padding, min.z - padding)
        axisHandle.boundingBox.max = SCNVector3(max.x + padding, max.y + padding, max.z + padding)
        
        addChildNode(axis)
        addChildNode(axisHandle)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
