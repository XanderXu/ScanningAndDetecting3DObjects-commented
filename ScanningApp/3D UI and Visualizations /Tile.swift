/*
See LICENSE folder for this sample’s licensing information.

Abstract:
A visualization indicating when part of a scanned bounding box has enough data for recognition.
一个可视化指示器,指示当边界盒的某一部分已经识别到足够数据.
*/

import UIKit
import SceneKit

class Tile: SCNNode {
    
    var isCaptured: Bool = false
    var isHighlighted: Bool = false
    
    func updateVisualization() {
        var newOpacity: CGFloat = isCaptured ? 0.5 : 0.0
        newOpacity += isHighlighted ? 0.35 : 0.0
        opacity = newOpacity
    }
    
    init(_ plane: SCNPlane) {
        super.init()
        self.geometry = plane
        self.opacity = 0.0
        
        // Create a child node with another plane of the same size, but a darker color to stand out better.
        // This helps users see captured tiles from the back.
        // 创建一个尺寸相同的子节点,里面包含一个平面,但是颜色更深一点以突出显示.
        // 这帮助用户从后面看到捕捉到的图块.
        if childNodes.isEmpty {
            let innerPlane = SCNPlane(width: plane.width, height: plane.height)
            innerPlane.materials = [SCNMaterial.material(withDiffuse: UIColor.appBrown.withAlphaComponent(0.8), isDoubleSided: false)]
            let innerNode = SCNNode(geometry: innerPlane)
            innerNode.simdEulerAngles = float3(0, .pi, 0)
            addChildNode(innerNode)
        }
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
