import SceneKit
import UIKit

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xff) / 255,
                  green: CGFloat((hex >> 8) & 0xff) / 255,
                  blue: CGFloat(hex & 0xff) / 255,
                  alpha: alpha)
    }
}

/// Construção procedural de todos os objetos 3D do jogo (sem arquivos de modelo).
enum Make {
    static func mat(_ hex: UInt32, rough: CGFloat = 0.85, metal: CGFloat = 0) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = UIColor(hex: hex)
        m.roughness.contents = NSNumber(value: Double(rough))
        m.metalness.contents = NSNumber(value: Double(metal))
        return m
    }

    static func glow(_ hex: UInt32) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = UIColor(hex: hex)
        return m
    }

    static func node(_ g: SCNGeometry, _ m: SCNMaterial, _ p: SIMD3<Float> = .zero) -> SCNNode {
        g.materials = [m]
        let n = SCNNode(geometry: g)
        n.simdPosition = p
        return n
    }

    static func facet(_ r: CGFloat, _ seg: Int = 6) -> SCNSphere {
        let s = SCNSphere(radius: r)
        s.segmentCount = seg
        return s
    }

    /// Sombra suave no chão (disco escuro translúcido).
    static func shadow(_ r: CGFloat) -> SCNNode {
        let g = SCNCylinder(radius: r, height: 0.002)
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = UIColor(white: 0, alpha: 0.35)
        m.writesToDepthBuffer = false
        let n = node(g, m, [0, 0.008, 0])
        n.renderingOrder = -1
        return n
    }

    static func tree() -> SCNNode {
        let g = SCNNode()
        let trunk = SCNCone(topRadius: 0.24, bottomRadius: 0.34, height: 1.5)
        trunk.radialSegmentCount = 7
        g.addChildNode(node(trunk, mat(0x5a3d26), [0, 0.75, 0]))
        let leaf = mat(0x2f5a2a), leaf2 = mat(0x3d6e2f)
        let parts: [(SIMD3<Float>, CGFloat, SCNMaterial)] = [
            ([0, 1.9, 0], 0.95, leaf), ([0.45, 1.65, 0.2], 0.6, leaf2),
            ([-0.4, 1.75, -0.15], 0.65, leaf2), ([0, 2.55, 0], 0.65, leaf)
        ]
        for (p, r, m) in parts { g.addChildNode(node(facet(r), m, p)) }
        g.addChildNode(shadow(0.9))
        return g
    }

    static func rock() -> SCNNode {
        let g = SCNNode()
        let big = node(facet(0.72, 5), mat(0x7c7a72), [0, 0.5, 0])
        big.simdScale = [1.15, 0.8, 1]
        big.eulerAngles.y = Float.random(in: 0...6)
        g.addChildNode(big)
        g.addChildNode(node(facet(0.32, 5), mat(0x6a6860), [0.62, 0.22, 0.2]))
        g.addChildNode(shadow(1.0))
        return g
    }

    static func stump() -> SCNNode {
        let g = SCNNode()
        let s = SCNCone(topRadius: 0.5, bottomRadius: 0.62, height: 1.05)
        s.radialSegmentCount = 9
        g.addChildNode(node(s, mat(0x6b4a2c), [0, 0.52, 0]))
        let top = SCNCylinder(radius: 0.48, height: 0.04)
        top.radialSegmentCount = 9
        g.addChildNode(node(top, mat(0xc79a62), [0, 1.06, 0]))
        let a = axe()
        a.simdPosition = [0.1, 1.2, 0]
        a.eulerAngles.z = 0.4
        g.addChildNode(a)
        g.addChildNode(shadow(0.8))
        return g
    }

    static func axe() -> SCNNode {
        let g = SCNNode()
        g.addChildNode(node(SCNCylinder(radius: 0.028, height: 0.55), mat(0x5a3a20)))
        g.addChildNode(node(SCNBox(width: 0.2, height: 0.17, length: 0.035, chamferRadius: 0),
                            mat(0xb8bcc4, rough: 0.35, metal: 0.7), [0.1, 0.2, 0]))
        return g
    }

    static func arrow() -> SCNNode {
        let g = SCNNode()
        let shaft = node(SCNCylinder(radius: 0.012, height: 0.75), mat(0x8a6a3a))
        shaft.eulerAngles.x = .pi / 2
        g.addChildNode(shaft)
        let tip = node(SCNCone(topRadius: 0, bottomRadius: 0.035, height: 0.11), mat(0x9aa0a8, rough: 0.4, metal: 0.6), [0, 0, 0.42])
        tip.eulerAngles.x = .pi / 2
        g.addChildNode(tip)
        g.addChildNode(node(SCNBox(width: 0.1, height: 0.01, length: 0.12, chamferRadius: 0), mat(0xb03a2a), [0, 0, -0.33]))
        return g
    }

    static func stone() -> SCNNode {
        node(facet(0.13, 5), mat(0x857f74))
    }

    static func bomb() -> (SCNNode, SCNNode) {
        let g = SCNNode()
        g.addChildNode(node(SCNSphere(radius: 0.15), mat(0x1d1d1f, rough: 0.5)))
        g.addChildNode(node(SCNCylinder(radius: 0.02, height: 0.1), mat(0x8a6a3a), [0, 0.18, 0]))
        let spark = node(SCNSphere(radius: 0.05), glow(0xffc04a), [0, 0.25, 0])
        g.addChildNode(spark)
        return (g, spark)
    }

    /// Anel do retículo de escaneamento.
    static func reticle() -> SCNNode {
        let ring = SCNTube(innerRadius: 0.11, outerRadius: 0.14, height: 0.004)
        ring.radialSegmentCount = 48
        let n = node(ring, glow(0xff8a2b))
        let holder = SCNNode()
        holder.addChildNode(n)
        return holder
    }

    /// Anel que marca o limite da arena no chão.
    static func arenaRing(_ r: CGFloat) -> SCNNode {
        let t = SCNTube(innerRadius: r - 0.06, outerRadius: r + 0.06, height: 0.004)
        t.radialSegmentCount = 96
        let m = glow(0xff8a2b)
        m.transparency = 0.45
        return node(t, m, [0, 0.01, 0])
    }
}

/// O orc: modelo + articulações para animar.
final class OrcRig {
    let node = SCNNode()
    let body = SCNNode()
    let legL = SCNNode(), legR = SCNNode(), armL = SCNNode(), armR = SCNNode()
    let held: SCNNode
    let skin: SCNMaterial

    init() {
        skin = Make.mat(0x6c8f2e)
        held = Make.axe()
        let cloth = Make.mat(0x4a3122)
        let metal = Make.mat(0x8b9097, rough: 0.4, metal: 0.6)
        let eye = Make.glow(0xff3a1a)
        node.addChildNode(body)

        for (leg, x) in [(legL, Float(-0.14)), (legR, Float(0.14))] {
            leg.simdPosition = [x, 0.72, 0]
            leg.addChildNode(Make.node(SCNBox(width: 0.21, height: 0.72, length: 0.24, chamferRadius: 0.02), cloth, [0, -0.36, 0]))
            leg.addChildNode(Make.node(SCNBox(width: 0.23, height: 0.1, length: 0.32, chamferRadius: 0.02), Make.mat(0x2a2018), [0, -0.68, 0.05]))
            body.addChildNode(leg)
        }
        body.addChildNode(Make.node(SCNBox(width: 0.64, height: 0.62, length: 0.4, chamferRadius: 0.04), skin, [0, 1.06, 0]))
        body.addChildNode(Make.node(SCNBox(width: 0.67, height: 0.34, length: 0.43, chamferRadius: 0.03), cloth, [0, 0.9, 0]))
        body.addChildNode(Make.node(SCNBox(width: 0.69, height: 0.08, length: 0.45, chamferRadius: 0), Make.mat(0x2a1c12), [0, 0.76, 0]))
        body.addChildNode(Make.node(SCNBox(width: 0.26, height: 0.1, length: 0.3, chamferRadius: 0.02), metal, [-0.4, 1.38, 0]))

        let head = SCNNode()
        head.simdPosition = [0, 1.56, 0]
        body.addChildNode(head)
        head.addChildNode(Make.node(SCNBox(width: 0.38, height: 0.34, length: 0.36, chamferRadius: 0.03), skin))
        head.addChildNode(Make.node(SCNBox(width: 0.42, height: 0.13, length: 0.38, chamferRadius: 0.02), skin, [0, -0.17, 0.02]))
        for x in [Float(-0.11), Float(0.11)] {
            head.addChildNode(Make.node(SCNCone(topRadius: 0, bottomRadius: 0.035, height: 0.14), Make.mat(0xf1ead2), [x, -0.07, 0.2]))
            head.addChildNode(Make.node(SCNBox(width: 0.07, height: 0.04, length: 0.02, chamferRadius: 0), eye, [x * 0.8, 0.04, 0.185]))
            let ear = Make.node(SCNCone(topRadius: 0, bottomRadius: 0.06, height: 0.22), skin, [x * 2.1, 0.03, 0])
            ear.eulerAngles.z = x > 0 ? -1.4 : 1.4
            head.addChildNode(ear)
        }
        head.addChildNode(Make.node(SCNCone(topRadius: 0.21, bottomRadius: 0.23, height: 0.12), metal, [0, 0.2, 0]))
        head.addChildNode(Make.node(SCNCone(topRadius: 0, bottomRadius: 0.05, height: 0.18), metal, [0, 0.34, 0]))

        for (arm, x) in [(armL, Float(-0.42)), (armR, Float(0.42))] {
            arm.simdPosition = [x, 1.32, 0]
            arm.addChildNode(Make.node(SCNBox(width: 0.17, height: 0.58, length: 0.17, chamferRadius: 0.02), skin, [0, -0.28, 0]))
            body.addChildNode(arm)
        }
        held.simdPosition = [0, -0.6, 0.12]
        held.eulerAngles.x = .pi / 2
        armR.addChildNode(held)
        node.addChildNode(Make.shadow(0.45))
    }
}
