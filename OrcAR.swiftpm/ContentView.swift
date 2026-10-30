import SwiftUI
import ARKit
import SceneKit

// MARK: - Paleta

extension Color {
    static let ember = Color(red: 1.0, green: 0.54, blue: 0.17)
    static let orcGreen = Color(red: 0.56, green: 0.75, blue: 0.29)
    static let bone = Color(red: 0.93, green: 0.90, blue: 0.82)
    static let blood = Color(red: 0.89, green: 0.26, blue: 0.23)
    static let panel = Color(red: 0.06, green: 0.08, blue: 0.05).opacity(0.82)
    static let ink = Color(red: 0.05, green: 0.06, blue: 0.04)
}

// MARK: - Visão AR

struct ARContainer: UIViewRepresentable {
    let game: GameController

    func makeUIView(context: Context) -> ARSCNView {
        let v = ARSCNView(frame: .zero)
        game.attach(v)
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped(_:)))
        v.addGestureRecognizer(tap)
        return v
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(game: game) }

    final class Coordinator: NSObject {
        let game: GameController
        init(game: GameController) { self.game = game }
        @objc func tapped(_ g: UITapGestureRecognizer) {
            guard let v = g.view else { return }
            game.tap(at: g.location(in: v))
        }
    }
}

// MARK: - Tela principal

struct ContentView: View {
    @StateObject private var game = GameController()
    @State private var started = false

    var body: some View {
        ZStack {
            if started {
                ARContainer(game: game).ignoresSafeArea()
                HUD(game: game)
            } else {
                StartView { started = true }
            }
        }
        .background(Color.ink.ignoresSafeArea())
    }
}

struct StartView: View {
    var onStart: () -> Void
    private let supported = ARWorldTrackingConfiguration.isSupported

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Spacer()
            Text("REALIDADE AUMENTADA · 3D")
                .font(.system(size: 13, weight: .bold)).tracking(2.5).foregroundColor(.ember)
            (Text("Caça ao ") + Text("Orc").foregroundColor(.orcGreen))
                .font(.system(size: 64, weight: .black, design: .serif))
                .foregroundColor(.bone)
            Text("Um orc invade o seu ambiente, corre entre árvores e pedras, se esconde e joga machadinhas em você. Acabe com ele a bombadas.")
                .font(.system(size: 18)).foregroundColor(.bone.opacity(0.75))
            VStack(alignment: .leading, spacing: 10) {
                Step(n: "1", t: "Escaneie o chão", d: "Mova o iPad devagar apontando para o piso.")
                Step(n: "2", t: "Fixe o cenário", d: "Árvores, pedras e tocos ficam presos ao seu redor.")
                Step(n: "3", t: "Cace o orc", d: "Ele entra depois. Ande, procure e toque para lançar bombas.")
            }
            .padding(.vertical, 6)
            if supported {
                Button(action: onStart) {
                    HStack {
                        Text("Começar").font(.system(size: 20, weight: .bold))
                        Spacer()
                        Image(systemName: "arkit")
                    }
                    .padding(.horizontal, 20).padding(.vertical, 16)
                    .foregroundColor(.black)
                    .background(Color.ember)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            } else {
                Text("Este aparelho não suporta rastreamento de mundo do ARKit.")
                    .foregroundColor(.blood)
            }
            Text("Jogue em pé, num espaço livre de uns 3 metros ao seu redor.")
                .font(.system(size: 14)).foregroundColor(.bone.opacity(0.55))
            Spacer()
        }
        .frame(maxWidth: 460)
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct Step: View {
    let n: String, t: String, d: String
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(n).font(.system(size: 15, weight: .bold)).foregroundColor(.black)
                .frame(width: 28, height: 28).background(Circle().fill(Color.ember))
            VStack(alignment: .leading, spacing: 2) {
                Text(t).font(.system(size: 17, weight: .bold)).foregroundColor(.bone)
                Text(d).font(.system(size: 15)).foregroundColor(.bone.opacity(0.7))
            }
        }
    }
}

// MARK: - HUD

struct HUD: View {
    @ObservedObject var game: GameController

    var body: some View {
        ZStack {
            // Avisos de dano e de projétil chegando
            RadialGradient(colors: [.clear, Color.red.opacity(0.65)], center: .center, startRadius: 200, endRadius: 700)
                .opacity(game.hurt ? 1 : 0).animation(.easeOut(duration: 0.4), value: game.hurt)
                .ignoresSafeArea().allowsHitTesting(false)
            HStack {
                LinearGradient(colors: [Color.orange.opacity(0.55), .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: 120).opacity(game.warnL ? 1 : 0)
                Spacer()
                LinearGradient(colors: [.clear, Color.orange.opacity(0.55)], startPoint: .leading, endPoint: .trailing)
                    .frame(width: 120).opacity(game.warnR ? 1 : 0)
            }
            .ignoresSafeArea().allowsHitTesting(false)

            if game.phase == .playing { finderArrow.allowsHitTesting(false) }

            VStack(spacing: 0) {
                if game.phase == .playing || game.phase == .fixing { topBar }
                if !game.trackingMsg.isEmpty && game.phase != .over {
                    Text(game.trackingMsg)
                        .font(.system(size: 15, weight: .semibold)).foregroundColor(.bone)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Capsule().fill(Color.panel)).padding(.top, 10)
                }
                Spacer()
                if game.phase == .playing { crosshair }
                Spacer()
                Text(game.toast)
                    .font(.system(size: 30, weight: .black, design: .serif))
                    .foregroundColor(.bone).shadow(color: .black, radius: 8)
                    .opacity(game.toast.isEmpty ? 0 : 1)
                    .animation(.easeOut(duration: 0.2), value: game.toast)
                    .allowsHitTesting(false)
                    .padding(.bottom, 16)
                bottom
            }
            .padding(.horizontal, 16).padding(.vertical, 12)

            if game.phase == .over { gameOver }
        }
    }

    private var topBar: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 0) {
                Text("\(game.score)").font(.system(size: 36, weight: .bold).monospacedDigit()).foregroundColor(.bone)
                Text("ONDA \(game.wave)").font(.system(size: 13, weight: .bold)).tracking(1.5).foregroundColor(.ember)
            }
            Spacer()
            if game.showFoe {
                VStack(spacing: 4) {
                    Text(game.orcName).font(.system(size: 20, weight: .black, design: .serif)).foregroundColor(.orcGreen)
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.black.opacity(0.55))
                            Capsule().fill(Color.orcGreen).frame(width: g.size.width * CGFloat(game.orcHP))
                        }
                    }
                    .frame(width: 160, height: 8)
                }
            }
            Spacer()
            HStack(spacing: 3) {
                ForEach(0..<5, id: \.self) { i in
                    Image(systemName: i < game.hearts ? "heart.fill" : "heart")
                        .foregroundColor(i < game.hearts ? .blood : .bone.opacity(0.5))
                        .font(.system(size: 20))
                }
            }
        }
        .shadow(color: .black.opacity(0.6), radius: 4)
        .allowsHitTesting(false)
    }

    private var crosshair: some View {
        ZStack {
            Circle().stroke(Color.bone.opacity(0.7), lineWidth: 2).frame(width: 20, height: 20)
            Rectangle().fill(Color.bone).frame(width: 2, height: 10).offset(y: -16)
            Rectangle().fill(Color.bone).frame(width: 2, height: 10).offset(y: 16)
            Rectangle().fill(Color.bone).frame(width: 10, height: 2).offset(x: -16)
            Rectangle().fill(Color.bone).frame(width: 10, height: 2).offset(x: 16)
        }
        .allowsHitTesting(false)
    }

    private var finderArrow: some View {
        GeometryReader { g in
            if let a = game.finder {
                let w = g.size.width, h = g.size.height
                let rx = w / 2 - 50, ry = h / 2 - 130
                let sx = CGFloat(sin(a)), sy = CGFloat(-cos(a))
                let k: CGFloat = min(rx / max(abs(sx), 0.000001), ry / max(abs(sy), 0.000001))
                VStack(spacing: 2) {
                    Image(systemName: "location.north.fill")
                        .font(.system(size: 34)).foregroundColor(.orcGreen)
                        .rotationEffect(.radians(a))
                        .shadow(color: .black, radius: 3)
                    Text("ORC").font(.system(size: 13, weight: .bold)).tracking(1.5).foregroundColor(.orcGreen)
                        .shadow(color: .black, radius: 3)
                }
                .position(x: w / 2 + sx * k, y: h / 2 + sy * k)
            }
        }
    }

    @ViewBuilder private var bottom: some View {
        switch game.phase {
        case .scanning:
            VStack(spacing: 12) {
                Text(game.planeFound
                     ? "Chão encontrado. Fique no lugar onde quer jogar e fixe o cenário."
                     : "1 · Escaneando… mova o iPad devagar apontando para o chão até aparecer o anel laranja.")
                    .font(.system(size: 17, weight: .semibold)).foregroundColor(.bone)
                    .multilineTextAlignment(.center)
                    .padding(14).background(RoundedRectangle(cornerRadius: 14).fill(Color.panel))
                Button(action: game.placeScenery) {
                    Text("2 · Fixar cenário aqui")
                        .font(.system(size: 19, weight: .bold))
                        .padding(.horizontal, 26).padding(.vertical, 15)
                        .foregroundColor(.black)
                        .background(Capsule().fill(game.planeFound ? Color.ember : Color.gray.opacity(0.5)))
                }
                .disabled(!game.planeFound)
            }
        case .fixing:
            Text("Cenário fixado. O orc está chegando…")
                .font(.system(size: 17, weight: .semibold)).foregroundColor(.bone)
                .padding(14).background(RoundedRectangle(cornerRadius: 14).fill(Color.panel))
        case .playing:
            HStack(alignment: .bottom) {
                Button(action: game.rescan) {
                    Label("Reescanear", systemImage: "arrow.counterclockwise")
                        .font(.system(size: 14, weight: .semibold)).foregroundColor(.bone)
                        .padding(.horizontal, 12).padding(.vertical, 10)
                        .background(Capsule().fill(Color.panel))
                }
                Spacer()
                Button(action: game.throwCenter) {
                    ZStack {
                        Circle().fill(Color.panel)
                        Circle().trim(from: 0, to: CGFloat(1 - game.cooldown))
                            .stroke(Color.ember, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        Text("BOMBA").font(.system(size: 14, weight: .bold)).foregroundColor(.bone)
                    }
                    .frame(width: 86, height: 86)
                }
                Spacer()
                Text("Toque para lançar\nAnde para desviar")
                    .font(.system(size: 13)).foregroundColor(.bone.opacity(0.75))
                    .multilineTextAlignment(.trailing)
                    .allowsHitTesting(false)
            }
        case .over:
            EmptyView()
        }
    }

    private var gameOver: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("O ORC VENCEU").font(.system(size: 13, weight: .bold)).tracking(2.5).foregroundColor(.ember)
            Text("\(game.score)").font(.system(size: 72, weight: .black, design: .serif).monospacedDigit()).foregroundColor(.ember)
            Text("Onda \(game.wave) · \(game.kills) \(game.kills == 1 ? "orc derrubado" : "orcs derrubados") · recorde \(game.best)")
                .font(.system(size: 17)).foregroundColor(.bone.opacity(0.8))
            Button(action: game.restart) {
                Text("Jogar de novo aqui").font(.system(size: 18, weight: .bold))
                    .frame(maxWidth: .infinity).padding(.vertical, 15)
                    .foregroundColor(.black).background(RoundedRectangle(cornerRadius: 14).fill(Color.ember))
            }
            Button(action: game.rescan) {
                Text("Escanear outro lugar").font(.system(size: 17, weight: .semibold))
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .foregroundColor(.bone).background(RoundedRectangle(cornerRadius: 14).fill(Color.panel))
            }
        }
        .padding(24)
        .frame(maxWidth: 420)
        .background(RoundedRectangle(cornerRadius: 20).fill(Color.ink.opacity(0.9)))
        .padding(20)
    }
}
