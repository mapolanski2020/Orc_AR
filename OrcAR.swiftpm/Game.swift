import SwiftUI
import ARKit
import SceneKit
import UIKit

// MARK: - Tipos do jogo

enum Phase { case scanning, fixing, playing, over }
enum CoverKind { case tree, rock, stump }
enum OrcState { case run, hide, peek, windup, recover, stagger, dead }

struct Cover {
    var p: SIMD2<Float>
    var r: Float
    var h: Float
    var kind: CoverKind
    var node: SCNNode
    var wob: Float = 0
}

final class Orc {
    let rig = OrcRig()
    var x: Float, z: Float
    var hp: Int
    let maxHp: Int
    let name: String
    let speed: Float
    var state: OrcState = .run
    var timer: Float = 0, side: Float = 1, crouch: Float = 0, anim: Float = 0
    var flash: Float = 0, deadT: Float = 0, boost: Float = 1, yaw: Float = 0
    var cover = -1

    init(x: Float, z: Float, hp: Int, name: String, speed: Float) {
        self.x = x; self.z = z; self.hp = hp; self.maxHp = hp; self.name = name; self.speed = speed
    }
}

struct Bomb { let node: SCNNode; let spark: SCNNode; var v: SIMD3<Float>; var t: Float = 0 }

struct Proj {
    let node: SCNNode
    var v: SIMD3<Float>
    let g: Float
    let kind: Int          // 0 machadinha, 1 pedra, 2 flecha
    var t: Float = 0
    let T: Float
    var minD: Float = 99
    let spin: SIMD3<Float>
}

private let NAMES = ["Grak", "Murzog", "Brokka", "Zug Dente-Torto", "Hrolk", "Skarn", "Gorbuk", "Rasha Olho-Rubro"]

// MARK: - Controlador

/// Toda a simulação roda no laço de renderização do SceneKit; a interface (SwiftUI)
/// recebe só um resumo publicado na thread principal.
final class GameController: NSObject, ObservableObject, ARSCNViewDelegate {

    // Estado mostrado na interface
    @Published var phase: Phase = .scanning
    @Published var planeFound = false
    @Published var score = 0
    @Published var wave = 1
    @Published var hearts = 5
    @Published var kills = 0
    @Published var orcHP: Double = 1
    @Published var orcName = ""
    @Published var showFoe = false
    @Published var toast = ""
    @Published var cooldown: Double = 0
    @Published var finder: Double? = nil
    @Published var warnL = false
    @Published var warnR = false
    @Published var hurt = false
    @Published var trackingMsg = "Iniciando a câmera…"
    @Published var placeScale: Double = 1 { didSet { lock.lock(); pScale = Float(placeScale); lock.unlock() } }
    var sizeLabel: String { String(format: "%.1f m", 9.3 * Double(S) * placeScale).replacingOccurrences(of: ".", with: ",") }
    @Published var best = UserDefaults.standard.integer(forKey: "orcBest")

    private weak var view: ARSCNView?
    private let anchorNode = SCNNode()   // segue a âncora do ARKit (fixa no mundo real)
    private let root = SCNNode()         // arena em unidades do jogo, escalada
    private let reticle = Make.reticle()
    private var anchor: ARAnchor?
    private var planeNodes: [UUID: SCNNode] = [:]
    private var center = SIMD3<Float>(0, 0, 0)
    private let S: Float = 0.42          // 1 unidade do jogo = 42 cm

    // Simulação (somente na thread de renderização)
    private var sPhase: Phase = .scanning
    private var covers: [Cover] = []
    private var bombs: [Bomb] = []
    private var projs: [Proj] = []
    private var orc: Orc?
    private var nextOrcT: Float = 0
    private var first = true
    private var cool: Float = 0
    private var lastTime: TimeInterval = 0
    private var over = false
    private var uiT: Float = 0
    private var sScore = 0, sWave = 1, sHearts = 5, sKills = 0
    private var hitPose: simd_float4x4?
    private var lastPlaneFound = false
    private var lastEye = SIMD3<Float>(0, 3.8, 0)

    // Fila de comandos vindos da interface
    private let lock = NSLock()
    private var pThrows: [(SIMD3<Float>, SIMD3<Float>)] = []
    private var pPlace = false, pRestart = false, pRescan = false
    private var pScale: Float = 1
    private var toastID = 0

    private let HIT_R: Float = 0.6
    private let COOL: Float = 0.75
    private let G: Float = 9.8

    override init() {
        super.init()
        root.simdScale = SIMD3<Float>(repeating: S)
        anchorNode.addChildNode(root)
    }

    // MARK: Sessão AR

    func attach(_ v: ARSCNView) {
        view = v
        v.delegate = self
        v.scene = SCNScene()
        v.autoenablesDefaultLighting = true
        v.automaticallyUpdatesLighting = true
        let sun = SCNNode()
        sun.light = SCNLight()
        sun.light?.type = .directional
        sun.light?.intensity = 700
        sun.eulerAngles = SCNVector3(-1.0, 0.6, 0)
        v.scene.rootNode.addChildNode(sun)
        reticle.isHidden = true
        v.scene.rootNode.addChildNode(reticle)
        buildArena()
        anchorNode.isHidden = true
        v.scene.rootNode.addChildNode(anchorNode)
        let c = ARWorldTrackingConfiguration()
        c.planeDetection = [.horizontal]
        c.environmentTexturing = .automatic
        v.session.run(c, options: [.resetTracking, .removeExistingAnchors])
    }

    func renderer(_ renderer: SCNSceneRenderer, nodeFor anchor: ARAnchor) -> SCNNode? {
        if anchor.name == "arena" {
            anchorNode.removeFromParentNode()
            return anchorNode
        }
        return nil
    }

    // Mostra os planos detectados enquanto escaneia
    func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
        guard let pa = anchor as? ARPlaneAnchor else { return }
        let plane = SCNPlane(width: CGFloat(pa.planeExtent.width), height: CGFloat(pa.planeExtent.height))
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = UIColor(hex: 0xff8a2b, alpha: 0.18)
        m.isDoubleSided = true
        m.writesToDepthBuffer = false
        plane.materials = [m]
        let pn = SCNNode(geometry: plane)
        pn.eulerAngles.x = -.pi / 2
        pn.simdPosition = pa.center
        pn.isHidden = sPhase != .scanning
        node.addChildNode(pn)
        planeNodes[pa.identifier] = pn
    }

    func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
        guard let pa = anchor as? ARPlaneAnchor, let pn = planeNodes[pa.identifier],
              let plane = pn.geometry as? SCNPlane else { return }
        plane.width = CGFloat(pa.planeExtent.width)
        plane.height = CGFloat(pa.planeExtent.height)
        pn.simdPosition = pa.center
        pn.eulerAngles.y = 0
        pn.simdEulerAngles = SIMD3<Float>(-.pi / 2, 0, 0)
        pn.isHidden = sPhase != .scanning
    }

    func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        var msg = ""
        switch camera.trackingState {
        case .normal: msg = ""
        case .notAvailable: msg = "Rastreamento indisponível"
        case .limited(let r):
            switch r {
            case .excessiveMotion: msg = "Mova o iPad mais devagar"
            case .insufficientFeatures: msg = "Aponte para um chão com textura e boa luz"
            case .initializing: msg = "Iniciando… mova o iPad devagar"
            case .relocalizing: msg = "Recuperando a posição…"
            @unknown default: msg = "Rastreamento limitado"
            }
        }
        ui { self.trackingMsg = msg }
    }

    // MARK: Comandos da interface (thread principal)

    func tap(at pt: CGPoint) {
        guard let v = view else { return }
        guard phase == .playing else { return }
        let a = v.unprojectPoint(SCNVector3(Float(pt.x), Float(pt.y), 0))
        let b = v.unprojectPoint(SCNVector3(Float(pt.x), Float(pt.y), 1))
        let o = SIMD3<Float>(a.x, a.y, a.z)
        let d = simd_normalize(SIMD3<Float>(b.x - a.x, b.y - a.y, b.z - a.z))
        lock.lock(); pThrows.append((o, d)); lock.unlock()
    }

    func throwCenter() {
        guard let v = view else { return }
        tap(at: CGPoint(x: v.bounds.midX, y: v.bounds.midY))
    }

    func placeScenery() { lock.lock(); pPlace = true; lock.unlock() }
    func restart() { lock.lock(); pRestart = true; lock.unlock() }
    func rescan() { lock.lock(); pRescan = true; lock.unlock() }

    // MARK: Laço principal

    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        let dt: Float = lastTime == 0 ? 0 : Float(min(time - lastTime, 0.05))
        lastTime = time
        guard let v = view, let pov = renderer.pointOfView, let frame = v.session.currentFrame else { return }

        lock.lock()
        let throwsNow = pThrows; pThrows.removeAll()
        let place = pPlace; pPlace = false
        let restartNow = pRestart; pRestart = false
        let rescanNow = pRescan; pRescan = false
        let scaleNow = pScale
        lock.unlock()

        if rescanNow { doRescan(v) }
        if restartNow && sPhase == .over { clearArena(); resetStats(); buildArena(); startFixing() }

        if sPhase == .scanning {
            // 1) ESCANEAR: procura o plano do chão no centro da tela
            let q = frame.raycastQuery(from: CGPoint(x: 0.5, y: 0.5), allowing: .estimatedPlane, alignment: .horizontal)
            if let r = v.session.raycast(q).first {
                reticle.simdTransform = r.worldTransform
                reticle.isHidden = false
                hitPose = r.worldTransform
            } else {
                reticle.isHidden = true
                hitPose = nil
            }
            let found = hitPose != nil
            if found != lastPlaneFound { lastPlaneFound = found; ui { self.planeFound = found } }

            // 2) ESCOLHER: o cenário aparece como prévia onde você mira, no tamanho escolhido
            root.simdScale = SIMD3<Float>(repeating: S * scaleNow)
            if let hp = hitPose {
                let target = SIMD3<Float>(hp.columns.3.x, hp.columns.3.y, hp.columns.3.z)
                anchorNode.simdPosition = anchorNode.isHidden ? target : simd_mix(anchorNode.simdPosition, target, SIMD3<Float>(repeating: 0.3))
                anchorNode.simdOrientation = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
                anchorNode.isHidden = false
            }

            // 3) FIXAR: só quando você toca em "Fixar cenário aqui"
            if place, hitPose != nil {
                center = anchorNode.simdPosition
                var t = matrix_identity_float4x4
                t.columns.3 = SIMD4<Float>(center.x, center.y, center.z, 1)
                let a = ARAnchor(name: "arena", transform: t)
                anchor = a
                v.session.add(anchor: a)
                reticle.isHidden = true
                for pn in planeNodes.values { pn.isHidden = true }
                resetStats()
                startFixing()
            }
            return
        }

        let eye = playerLocal(pov)
        lastEye = eye
        cool = max(0, cool - dt)
        if sPhase == .playing && !over {
            for (o, d) in throwsNow { throwBomb(o, d) }
        }

        if !over {
            // 3) O ORC entra só depois que o cenário está fixo
            if orc == nil && nextOrcT > 0 {
                nextOrcT -= dt
                if nextOrcT <= 0 {
                    if first {
                        first = false
                        spawnOrc(eye)
                        sPhase = .playing
                        let n = orc?.name ?? "O orc"
                        ui { self.phase = .playing }
                        say("\(n) entrou! Procure-o", 1.8)
                    } else {
                        sWave += 1
                        spawnOrc(eye)
                        let n = orc?.name ?? "Orc", w = sWave
                        say("Onda \(w): \(n)!", 1.6)
                    }
                }
            }
            updateOrc(dt, eye)
        }
        updateProjs(dt, eye, pov)
        updateBombs(dt)
        for i in covers.indices where covers[i].wob > 0 {
            covers[i].wob = max(0, covers[i].wob - dt * 2)
            covers[i].node.eulerAngles.z = sin(covers[i].wob * 30) * 0.05 * covers[i].wob
        }

        uiT -= dt
        if uiT <= 0 {
            uiT = 0.08
            let f = finderAngle(pov)
            let c = Double(cool / COOL)
            let hp = orc.map { Double(max(0, $0.hp)) / Double($0.maxHp) } ?? 0
            ui { self.finder = f; self.cooldown = c; self.orcHP = hp }
        }
    }

    private func startFixing() {
        sPhase = .fixing
        first = true
        nextOrcT = 2.4
        ui { self.phase = .fixing; self.showFoe = false }
        say("Cenário fixado", 1.6)
    }

    private func doRescan(_ v: ARSCNView) {
        if let a = anchor { v.session.remove(anchor: a) }
        anchor = nil
        anchorNode.removeFromParentNode()
        anchorNode.isHidden = true
        v.scene.rootNode.addChildNode(anchorNode)
        clearArena()
        buildArena()
        sPhase = .scanning
        for pn in planeNodes.values { pn.isHidden = false }
        ui { self.phase = .scanning; self.showFoe = false; self.finder = nil }
    }

    private func playerLocal(_ pov: SCNNode) -> SIMD3<Float> {
        let w = pov.simdWorldPosition
        if anchorNode.parent != nil { return root.simdConvertPosition(w, from: nil) }
        return (w - center) / (S * pScale)
    }

    private func toLocal(_ wp: SIMD3<Float>) -> SIMD3<Float> {
        if anchorNode.parent != nil { return root.simdConvertPosition(wp, from: nil) }
        return (wp - center) / (S * pScale)
    }

    private func toWorld(_ lp: SIMD3<Float>) -> SIMD3<Float> {
        if anchorNode.parent != nil { return root.simdConvertPosition(lp, to: nil) }
        return lp * (S * pScale) + center
    }

    // MARK: Cenário

    private func clearArena() {
        for n in root.childNodes { n.removeFromParentNode() }
        covers.removeAll(); bombs.removeAll(); projs.removeAll()
        orc = nil
    }

    private func resetStats() {
        sScore = 0; sWave = 1; sHearts = 5; sKills = 0; over = false; cool = 0
        publishStats()
        ui { self.hurt = false; self.finder = nil }
    }

    private func buildArena() {
        root.addChildNode(Make.arenaRing(4.62))
        let kinds: [CoverKind] = [.tree, .rock, .tree, .stump, .rock, .tree, .rock, .tree, .stump]
        var tries = 0
        while covers.count < kinds.count && tries < 600 {
            tries += 1
            let a = Float(covers.count) / Float(kinds.count) * 2 * .pi + Float.random(in: -0.3...0.3)
            let r = covers.count % 3 == 0 ? Float.random(in: 0.9...1.8) : Float.random(in: 2.2...4.0)
            let p = SIMD2<Float>(cos(a) * r, sin(a) * r)
            if covers.contains(where: { simd_distance($0.p, p) < 1.5 }) { continue }
            let k = kinds[covers.count]
            let node: SCNNode
            let cr: Float, ch: Float
            switch k {
            case .tree: node = Make.tree(); cr = 0.36; ch = 2.9
            case .rock: node = Make.rock(); cr = 0.78; ch = 1.05
            case .stump: node = Make.stump(); cr = 0.6; ch = 1.1
            }
            node.simdPosition = SIMD3<Float>(p.x, 0, p.y)
            // pequena animação de "brotar" do chão
            node.simdScale = SIMD3<Float>(repeating: 0.01)
            node.runAction(.sequence([.wait(duration: Double(covers.count) * 0.12), .scale(to: 1, duration: 0.35)]))
            root.addChildNode(node)
            covers.append(Cover(p: p, r: cr, h: ch, kind: k, node: node))
        }
    }

    // MARK: Orc

    private func spawnOrc(_ eye: SIMD3<Float>) {
        let a = atan2(-eye.z, -eye.x) + Float.random(in: -1.2...1.2)   // entra pelo lado oposto ao seu
        let hp = 3 + (sWave - 1) / 2
        let o = Orc(x: cos(a) * 5.6, z: sin(a) * 5.6, hp: hp,
                    name: NAMES[(sWave - 1) % NAMES.count], speed: 2.6 + Float(sWave) * 0.25)
        o.rig.node.simdPosition = SIMD3<Float>(o.x, 0, o.z)
        root.addChildNode(o.rig.node)
        orc = o
        pickCover(o, eye, boost: false)
        let n = o.name
        ui { self.orcName = n; self.orcHP = 1; self.showFoe = true }
    }

    private func pickCover(_ o: Orc, _ eye: SIMD3<Float>, boost: Bool) {
        let e2 = SIMD2<Float>(eye.x, eye.z), op = SIMD2<Float>(o.x, o.z)
        var idx = covers.indices.filter { $0 != o.cover && simd_distance(covers[$0].p, e2) > 2.4 }
        if idx.isEmpty { idx = covers.indices.filter { $0 != o.cover } }
        guard !idx.isEmpty else { return }
        idx.sort { simd_distance(covers[$0].p, op) < simd_distance(covers[$1].p, op) }
        o.cover = idx[Int.random(in: 0..<min(3, idx.count))]
        o.state = .run
        o.boost = boost ? 1.35 : 1
    }

    /// Ponto atrás da cobertura, do lado oposto ao jogador.
    private func hideSpot(_ c: Cover, _ eye: SIMD3<Float>, _ extra: Float = 0.4) -> (SIMD2<Float>, SIMD2<Float>) {
        var v = c.p - SIMD2<Float>(eye.x, eye.z)
        let L = simd_length(v)
        v = L > 0 ? v / L : SIMD2<Float>(1, 0)
        return (c.p + v * (c.r + extra), v)
    }

    @discardableResult
    private func stepTo(_ o: Orc, _ t: SIMD2<Float>, _ spd: Float, _ dt: Float) -> Float {
        let d = t - SIMD2<Float>(o.x, o.z)
        let dist = simd_length(d)
        if dist < 0.001 { return 0 }
        let s = min(dist, spd * dt)
        o.x += d.x / dist * s
        o.z += d.y / dist * s
        for c in covers {
            let off = SIMD2<Float>(o.x, o.z) - c.p
            let od = simd_length(off), mn = c.r + 0.28
            if od < mn && od > 0 {
                let np = c.p + off / od * mn
                o.x = np.x; o.z = np.y
            }
        }
        return dist
    }

    private func face(_ o: Orc, _ tx: Float, _ tz: Float, _ k: Float) {
        let t = atan2(tx - o.x, tz - o.z)
        var d = t - o.yaw
        while d > .pi { d -= 2 * .pi }
        while d < -.pi { d += 2 * .pi }
        o.yaw += d * min(1, k)
    }

    private func orcCenter(_ o: Orc) -> SIMD3<Float> { SIMD3<Float>(o.x, 0.95 - o.crouch * 0.4, o.z) }

    private func updateOrc(_ dt: Float, _ eye: SIMD3<Float>) {
        guard let o = orc else { return }
        var moving: Float = 0
        o.flash = max(0, o.flash - dt)
        o.rig.skin.emission.contents = o.flash > 0 ? UIColor(red: 0.8, green: 0, blue: 0, alpha: 1) : UIColor.black

        if o.state == .dead {
            o.deadT += dt
            o.rig.body.eulerAngles.x = max(-1.5, -o.deadT * 4)
            o.rig.node.simdPosition.y = o.deadT > 1 ? -(o.deadT - 1) * 0.8 : 0
            if o.deadT > 2.2 { o.rig.node.removeFromParentNode(); orc = nil; nextOrcT = 1.2 }
            return
        }
        guard o.cover >= 0 && o.cover < covers.count else { pickCover(o, eye, boost: false); return }
        let c = covers[o.cover]
        let (hs, hv) = hideSpot(c, eye)

        switch o.state {
        case .run:
            let d = stepTo(o, hs, o.speed * o.boost, dt)
            moving = 1
            face(o, hs.x, hs.y, dt * 10)
            o.crouch *= 0.9
            if d < 0.08 { o.state = .hide; o.timer = max(0.5, Float.random(in: 1...2.3) - Float(sWave) * 0.1) }
        case .hide:
            if stepTo(o, hs, o.speed * 0.7, dt) > 0.05 { moving = 0.6 }
            face(o, eye.x, eye.z, dt * 6)
            o.crouch += ((c.kind == .tree ? 0 : 1) - o.crouch) * min(1, dt * 8)
            o.timer -= dt
            if o.timer <= 0 { o.state = .peek; o.side = Bool.random() ? -1 : 1; o.timer = 0.4 }
        case .peek, .windup, .recover:
            let perp = SIMD2<Float>(-hv.y, hv.x) * o.side * (c.r + 0.5)
            let target = hs + perp - hv * (c.r + 0.2)
            if stepTo(o, target, o.speed * 1.3, dt) > 0.05 { moving = 0.8 }
            face(o, eye.x, eye.z, dt * 12)
            o.crouch *= 0.85
            if o.state == .peek {
                o.timer -= dt
                if o.timer <= 0 { o.state = .windup; o.timer = max(0.3, 0.55 - Float(sWave) * 0.03) }
            } else if o.state == .windup {
                o.rig.armR.eulerAngles.x = -2.6 * (1 - o.timer / 0.55)
                o.timer -= dt
                if o.timer <= 0 { orcThrow(o, eye); o.state = .recover; o.timer = 0.35; o.rig.armR.eulerAngles.x = 1 }
            } else {
                o.timer -= dt
                if o.timer <= 0 {
                    o.rig.armR.eulerAngles.x = 0
                    if Bool.random() { pickCover(o, eye, boost: false) } else { o.state = .hide; o.timer = Float.random(in: 0.8...1.8) }
                }
            }
        case .stagger:
            o.timer -= dt
            o.rig.body.eulerAngles.x = -0.3 * sin(o.timer * 20)
            if o.timer <= 0 { o.rig.body.eulerAngles.x = 0; pickCover(o, eye, boost: true) }
        case .dead:
            break
        }

        o.anim += dt * (moving > 0 ? 13 * o.speed / 2.6 : 0)
        let sw = sin(o.anim) * 0.75 * moving
        o.rig.legL.eulerAngles.x = sw
        o.rig.legR.eulerAngles.x = -sw
        o.rig.armL.eulerAngles.x = -sw * 0.7
        if o.state == .run || o.state == .hide { o.rig.armR.eulerAngles.x = sw * 0.6 }
        o.rig.held.isHidden = o.state == .recover
        o.rig.body.simdPosition.y = abs(sin(o.anim)) * 0.05 * moving - o.crouch * 0.38
        o.rig.body.simdScale = SIMD3<Float>(1, 1 - o.crouch * 0.12, 1)
        o.rig.node.simdPosition = SIMD3<Float>(o.x, o.rig.node.simdPosition.y, o.z)
        o.rig.node.eulerAngles.y = o.yaw
    }

    // MARK: Projéteis do orc

    private func orcThrow(_ o: Orc, _ eye: SIMD3<Float>) {
        let pool = sWave < 2 ? [0, 1] : [0, 1, 2, 2]
        let kind = pool.randomElement() ?? 0
        let node = kind == 0 ? Make.axe() : kind == 2 ? Make.arrow() : Make.stone()
        let hx = o.x + sin(o.yaw) * 0.3 + cos(o.yaw) * 0.4
        let hz = o.z + cos(o.yaw) * 0.3 - sin(o.yaw) * 0.4
        let hy = 1.7 - o.crouch * 0.3
        let spread = max(0.12, 0.55 - Float(sWave) * 0.06)
        let t = SIMD3<Float>(eye.x + .random(in: -spread...spread),
                             eye.y + .random(in: -spread...spread) * 0.6,
                             eye.z + .random(in: -spread...spread))
        let g: Float = kind == 2 ? 2.5 : G
        let spd: Float = (kind == 2 ? 11 : 7.5) + Float(sWave) * 0.4
        let d = t - SIMD3<Float>(hx, hy, hz)
        let T = max(0.5, simd_length(d) / spd)
        let v = SIMD3<Float>(d.x / T, (d.y + 0.5 * g * T * T) / T, d.z / T)
        node.simdPosition = SIMD3<Float>(hx, hy, hz)
        root.addChildNode(node)
        projs.append(Proj(node: node, v: v, g: g, kind: kind, T: T,
                          spin: SIMD3<Float>(.random(in: 8...14), .random(in: -3...3), 0)))
        haptic(.light)
    }

    private func updateProjs(_ dt: Float, _ eye: SIMD3<Float>, _ pov: SCNNode) {
        var wl = false, wr = false
        var i = projs.count - 1
        while i >= 0 {
            var q = projs[i]
            q.t += dt
            q.v.y -= q.g * dt
            q.node.simdPosition += q.v * dt
            if q.kind == 2 {
                q.node.simdLook(at: toWorld(q.node.simdPosition + q.v), up: SIMD3<Float>(0, 1, 0), localFront: SIMD3<Float>(0, 0, 1))
            } else {
                q.node.eulerAngles.x += q.spin.x * dt
                q.node.eulerAngles.y += q.spin.y * dt
            }
            let d = simd_distance(q.node.simdPosition, eye)
            q.minD = min(q.minD, d)
            let cs = pov.simdConvertPosition(toWorld(q.node.simdPosition), from: nil)
            if d < 6 && (cs.z > 0 || abs(cs.x / max(0.01, -cs.z)) > 0.6) { if cs.x < 0 { wl = true } else { wr = true } }

            var gone = false
            if d < HIT_R && !over {
                hurtPlayer(q.kind)
                gone = true
            } else if q.node.simdPosition.y < 0 || q.t > q.T + 1.2 {
                gone = true
                if q.minD < 1.2 && !over {
                    sScore += 5 * sWave
                    publishStats()
                    say("Desviou!", 0.7)
                }
            }
            if gone { q.node.removeFromParentNode(); projs.remove(at: i) } else { projs[i] = q }
            i -= 1
        }
        if wl != lastWarnL || wr != lastWarnR {
            lastWarnL = wl; lastWarnR = wr
            ui { self.warnL = wl; self.warnR = wr }
        }
    }
    private var lastWarnL = false, lastWarnR = false

    private func hurtPlayer(_ kind: Int) {
        sHearts -= 1
        publishStats()
        haptic(.heavy)
        ui {
            self.hurt = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { self.hurt = false }
        }
        say(kind == 0 ? "Machadinha na cara!" : kind == 2 ? "Flechada!" : "Pedrada!", 0.9)
        if sHearts <= 0 { gameOver() }
    }

    // MARK: Bombas

    private func throwBomb(_ originW: SIMD3<Float>, _ dirW: SIMD3<Float>) {
        guard cool <= 0, !over else { return }
        cool = COOL
        let o = toLocal(originW)
        let d = simd_normalize(toLocal(originW + dirW) - o)
        let (node, spark) = Make.bomb()
        node.simdPosition = o + d * 0.5 - SIMD3<Float>(0, 0.15, 0)
        root.addChildNode(node)
        bombs.append(Bomb(node: node, spark: spark, v: d * 10.5 + SIMD3<Float>(0, 2.2, 0)))
        haptic(.medium)
    }

    private func updateBombs(_ dt: Float) {
        var i = bombs.count - 1
        while i >= 0 {
            var b = bombs[i]
            b.t += dt
            b.v.y -= G * dt
            b.node.simdPosition += b.v * dt
            b.node.eulerAngles.z += dt * 6
            b.spark.simdScale = SIMD3<Float>(repeating: Float.random(in: 0.7...1.5))
            let P = b.node.simdPosition
            var hit = P.y <= 0.15
            var direct = false
            for j in covers.indices where P.y < covers[j].h && simd_distance(SIMD2<Float>(P.x, P.z), covers[j].p) < covers[j].r + 0.12 {
                hit = true
                covers[j].wob = 1
                break
            }
            if let o = orc, o.state != .dead, simd_distance(P, orcCenter(o)) < 0.55 { hit = true; direct = true }
            if hit || b.t > 4 {
                explode(P, direct: direct)
                b.node.removeFromParentNode()
                bombs.remove(at: i)
            } else {
                bombs[i] = b
            }
            i -= 1
        }
    }

    /// A cobertura bloqueia a explosão se estiver entre a bomba e o orc.
    private func blocked(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Bool {
        for c in covers {
            let dx = b.x - a.x, dz = b.z - a.z
            let L2 = max(0.0001, dx * dx + dz * dz)
            let t = ((c.p.x - a.x) * dx + (c.p.y - a.z) * dz) / L2
            if t < 0.03 || t > 0.97 { continue }
            let px = a.x + dx * t - c.p.x, pz = a.z + dz * t - c.p.y
            let y = a.y + (b.y - a.y) * t
            if px * px + pz * pz < c.r * c.r * 0.85 && y < c.h { return true }
        }
        return false
    }

    private func explode(_ P: SIMD3<Float>, direct: Bool) {
        haptic(.rigid)
        burst(P, n: 22, color: 0xff8a2b, speed: 4.5, life: 0.55, size: 0.2, glow: true)
        burst(P, n: 12, color: 0xffe08a, speed: 3, life: 0.35, size: 0.13, glow: true)
        burst(P, n: 12, color: 0x3a3530, speed: 2, life: 1.2, size: 0.28, glow: false)
        let scorch = Make.node(SCNCylinder(radius: 0.6, height: 0.002), Make.glow(0x120c08), SIMD3<Float>(P.x, 0.012, P.z))
        scorch.geometry?.firstMaterial?.transparency = 0.6
        root.addChildNode(scorch)
        scorch.runAction(.sequence([.wait(duration: 5), .fadeOut(duration: 2), .removeFromParentNode()]))

        guard let o = orc, o.state != .dead else { return }
        let oc = orcCenter(o)
        let d = simd_distance(P, oc)
        if direct || (d < 1.45 && !blocked(P, oc)) {
            let dmg = direct ? 2 : 1
            o.hp -= dmg
            o.flash = 0.2
            sScore += 25 * sWave * dmg
            say(direct ? "Em cheio! +\(50 * sWave)" : "Acertou! +\(25 * sWave)", 0.8)
            if o.hp <= 0 { killOrc(o) } else { o.state = .stagger; o.timer = 0.35 }
            publishStats()
        } else if d < 2.4 && [.hide, .peek, .windup].contains(o.state) {
            if d < 1.45 { say(["Ele se protegeu!", "Bateu na cobertura!"].randomElement()!, 0.8) }
            else { say(["Errou, humano!", "Hahaha!", "Mira torta!"].randomElement()!, 0.8) }
            if Float.random(in: 0...1) < 0.6 { pickCover(o, lastEye, boost: true) }
        }
    }

    private func killOrc(_ o: Orc) {
        o.state = .dead
        o.deadT = 0
        sKills += 1
        sScore += 100 * sWave
        sHearts = min(5, sHearts + 1)
        for q in projs { q.node.removeFromParentNode() }
        projs.removeAll()
        haptic(.heavy)
        say("\(o.name) caiu! +\(100 * sWave)", 1.4)
        publishStats()
    }

    private func gameOver() {
        over = true
        sPhase = .over
        let s = sScore
        ui {
            if s > self.best { self.best = s; UserDefaults.standard.set(s, forKey: "orcBest") }
            self.phase = .over
            self.finder = nil
        }
    }

    // MARK: Efeitos

    private func burst(_ p: SIMD3<Float>, n: Int, color: UInt32, speed: Float, life: Double, size: CGFloat, glow: Bool) {
        for _ in 0..<n {
            let m = glow ? Make.glow(color) : Make.mat(color)
            if glow { m.blendMode = .add }
            let s = Make.node(Make.facet(size * CGFloat(Float.random(in: 0.5...1.2)), 4), m, p)
            root.addChildNode(s)
            let dir = simd_normalize(SIMD3<Float>(.random(in: -1...1), .random(in: 0.2...1.4), .random(in: -1...1)))
                * speed * Float.random(in: 0.3...1)
            let L = life * Double.random(in: 0.6...1.2)
            let mv = SCNAction.moveBy(x: CGFloat(dir.x) * CGFloat(L) * 0.6,
                                      y: CGFloat(dir.y) * CGFloat(L) * 0.6,
                                      z: CGFloat(dir.z) * CGFloat(L) * 0.6, duration: L)
            mv.timingMode = .easeOut
            s.runAction(.sequence([.group([mv, .scale(to: glow ? 2.2 : 3.5, duration: L), .fadeOut(duration: L)]),
                                   .removeFromParentNode()]))
        }
    }

    /// Ângulo (0 = para cima, sentido horário) da seta que aponta o orc fora da tela.
    private func finderAngle(_ pov: SCNNode) -> Double? {
        guard let o = orc, o.state != .dead, !over else { return nil }
        let v = pov.simdConvertPosition(toWorld(orcCenter(o)), from: nil)
        if v.z < 0 && abs(v.x / -v.z) < 0.5 && abs(v.y / -v.z) < 0.6 { return nil }
        var ang = atan2(v.x, v.y)
        if v.z > 0 && abs(v.x) < 0.3 { ang = v.x < 0 ? -.pi / 2 : .pi / 2 }
        return Double(ang)
    }

    // MARK: Utilidades

    private func publishStats() {
        let s = sScore, w = sWave, h = sHearts, k = sKills
        ui { self.score = s; self.wave = w; self.hearts = max(0, h); self.kills = k }
    }

    private func ui(_ f: @escaping () -> Void) { DispatchQueue.main.async(execute: f) }

    private func say(_ t: String, _ secs: Double = 1.2) {
        ui {
            self.toastID += 1
            let id = self.toastID
            self.toast = t
            DispatchQueue.main.asyncAfter(deadline: .now() + secs) { if self.toastID == id { self.toast = "" } }
        }
    }

    private func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        ui { UIImpactFeedbackGenerator(style: style).impactOccurred() }
    }
}
