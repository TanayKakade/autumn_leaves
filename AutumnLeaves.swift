// AutumnLeaves — falling autumn leaves on your Mac desktop.
// Leaves drift down, pile up on window tops and on the Dock / bottom of the screen,
// fly off when you drag a window, and scatter when you swish the mouse through them.
// Build: swiftc -O AutumnLeaves.swift -o AutumnLeaves     Run: ./AutumnLeaves  (🍂 appears in the menu bar)

import Cocoa
import SpriteKit

// MARK: - Settings (tweak freely)

enum Cfg {
    static var targetLeaves = 90            // leaves in the air at once (menu: light / medium / heavy)
    static var swish = true                 // fast mouse movement scatters resting leaves
    static let colW: CGFloat = 8            // width of one column of a pile's height map (px)
    static let windowPileMax: CGFloat = 14  // max pile height on a window
    static let groundPileMax: CGFloat = 30  // max pile height on the Dock / screen bottom
    static let pollInterval = 1.0 / 30.0    // how often window positions are read (s)
    static let fallSpeed: CGFloat = 1.0     // falling speed multiplier
    static let inFrontFraction: CGFloat = 0.5 // share of the far layer that ignores windows (lands on the Dock)
    static let swishRadius: CGFloat = 46
    static let swishMinSpeed: CGFloat = 250 // mouse speed (px/s) needed to scatter leaves
    static let leafHeight: CGFloat = 2.2    // how much one resting leaf raises its pile
}

@inline(__always) func rnd(_ a: CGFloat, _ b: CGFloat) -> CGFloat { CGFloat.random(in: a...b) }
@inline(__always) func clamp(_ v: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat { min(max(v, lo), hi) }

// Three depth layers: far = small, faint, slow; near = big, bright, fast
struct Layer {
    let size: ClosedRange<CGFloat>
    let speed: ClosedRange<CGFloat>
    let alpha: ClosedRange<CGFloat>
    let sway: ClosedRange<CGFloat>
    let wind: CGFloat
    let z: CGFloat
}

let layers: [Layer] = [
    Layer(size: 12...17, speed: 28...45, alpha: 0.65...0.85, sway: 12...26, wind: 0.6, z: 1),
    Layer(size: 17...24, speed: 45...70, alpha: 0.85...1.00, sway: 18...34, wind: 0.9, z: 2),
    Layer(size: 24...32, speed: 70...100, alpha: 1.00...1.00, sway: 24...44, wind: 1.2, z: 7),
]

// Autumn palette: red, orange, amber, brown, olive gold
let palette: [(CGFloat, CGFloat, CGFloat)] = [
    (0.78, 0.16, 0.10), (0.92, 0.45, 0.08), (0.96, 0.68, 0.12), (0.60, 0.34, 0.14), (0.72, 0.62, 0.16),
]

// MARK: - Leaf textures (all drawn in code)

enum LeafShape: CaseIterable { case maple, oval, round, oak }

@MainActor func makeLeafTexture(_ shape: LeafShape, _ rgb: (CGFloat, CGFloat, CGFloat)) -> SKTexture {
    let s: CGFloat = 64
    let img = NSImage(size: NSSize(width: s, height: s), flipped: false) { _ in
        let color = NSColor(calibratedRed: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1)
        let dark = color.blended(withFraction: 0.5, of: .black) ?? color
        let c = CGPoint(x: s / 2, y: s / 2)
        let R = s * 0.44
        let pi = CGFloat.pi
        let path = NSBezierPath()
        var tips: [CGPoint] = []   // where the veins end

        func radial(_ f: (CGFloat) -> CGPoint) {
            for i in 0...64 {
                let p = f(CGFloat(i) / 64 * 2 * pi)
                if i == 0 { path.move(to: p) } else { path.line(to: p) }
            }
            path.close()
        }

        switch shape {
        case .maple: // five pointed lobes
            radial { a in
                let r = R * (0.34 + 0.66 * pow(abs(cos(2.5 * a)), 1.6))
                let g = a + pi / 2
                return CGPoint(x: c.x + cos(g) * r, y: c.y + sin(g) * r)
            }
            tips = (0..<5).map { k in
                let g = 0.4 * pi * CGFloat(k) + pi / 2
                return CGPoint(x: c.x + cos(g) * R * 0.8, y: c.y + sin(g) * R * 0.8)
            }
        case .oval: // pointed ellipse
            let w = R * 0.62
            let bot = CGPoint(x: c.x, y: c.y - R * 0.85), top = CGPoint(x: c.x, y: c.y + R)
            path.move(to: bot)
            path.curve(to: top, controlPoint1: CGPoint(x: c.x + w * 1.6, y: c.y - R * 0.5),
                       controlPoint2: CGPoint(x: c.x + w * 1.4, y: c.y + R * 0.5))
            path.curve(to: bot, controlPoint1: CGPoint(x: c.x - w * 1.4, y: c.y + R * 0.5),
                       controlPoint2: CGPoint(x: c.x - w * 1.6, y: c.y - R * 0.5))
            path.close()
            tips = [CGPoint(x: c.x, y: c.y + R * 0.9)]
        case .round: // birch / aspen
            path.appendOval(in: CGRect(x: c.x - R * 0.8, y: c.y - R * 0.7, width: R * 1.6, height: R * 1.5))
            tips = [CGPoint(x: c.x, y: c.y + R * 0.65)]
        case .oak: // wavy edge
            radial { a in
                let r = R * (0.62 + 0.17 * cos(7 * a))
                return CGPoint(x: c.x + cos(a) * r * 0.72, y: c.y + sin(a) * r * 1.15)
            }
            tips = [CGPoint(x: c.x, y: c.y + R * 1.0)]
        }

        color.setFill()
        path.fill()
        dark.setStroke()
        path.lineWidth = 1.3
        path.stroke()

        let veins = NSBezierPath()
        veins.lineWidth = 1
        veins.lineCapStyle = .round
        veins.move(to: CGPoint(x: c.x, y: c.y - R * 0.98)) // stem
        veins.line(to: c)
        for t in tips { veins.move(to: c); veins.line(to: t) }
        dark.withAlphaComponent(0.75).setStroke()
        veins.stroke()
        return true
    }
    return SKTexture(image: img)
}

// MARK: - Leaf

@MainActor final class Leaf {
    let node: SKSpriteNode
    var vel = CGVector.zero
    var fall: CGFloat = 50          // target falling speed
    var swayAmp: CGFloat = 20       // side-to-side drift (px/s)
    var swayFreq: CGFloat = 1
    var phase: CGFloat = 0
    var flipFreq: CGFloat = 2       // "tumbling" (leaf turning edge-on)
    var flipPhase: CGFloat = 0
    var rot0: CGFloat = 0
    var spin: CGFloat = 0
    var windFactor: CGFloat = 1
    var inFront = false             // ignores windows, only lands on the Dock / ground
    var ignoreID = -1               // don't land right back on the window it was flung from
    var ignoreUntil: CGFloat = 0
    var col = 0                     // column in the pile it rests on
    weak var pile: Pile?
    init(texture: SKTexture) { node = SKSpriteNode(texture: texture) }
}

// MARK: - Pile (a height map that resting leaves sit on)

@MainActor final class Pile {
    var minX: CGFloat
    var topY: CGFloat
    let width: CGFloat
    let maxLeaves: Int
    var h: [CGFloat]
    var caps: [CGFloat]
    var occ: [Bool]                 // column hidden behind a window in front
    var leaves: [Leaf] = []

    init(minX: CGFloat, topY: CGFloat, width: CGFloat, maxH: CGFloat, density: CGFloat, cap: Int) {
        self.minX = minX
        self.topY = topY
        self.width = width
        maxLeaves = max(16, min(cap, Int(width * density)))
        let n = max(1, Int((width / Cfg.colW).rounded(.up)))
        h = Array(repeating: 0, count: n)
        occ = Array(repeating: false, count: n)
        caps = (0..<n).map { i in
            let edge = min(CGFloat(i) + 0.5, CGFloat(n - i) - 0.5) * Cfg.colW
            return maxH * min(1, edge / (maxH * 3)).squareRoot()
        }
    }

    var count: Int { h.count }
    func col(at x: CGFloat) -> Int? { let c = Int((x - minX) / Cfg.colW); return (c >= 0 && c < count) ? c : nil }
    func colX(_ c: Int) -> CGFloat { minX + (CGFloat(c) + 0.5) * Cfg.colW }
    func surface(_ c: Int) -> CGFloat { topY + h[c] }

    func bump(_ c: Int, _ amt: CGFloat) {
        let spread: [(Int, CGFloat)] = [(0, 1), (-1, 0.6), (1, 0.6), (-2, 0.3), (2, 0.3)]
        for (o, w) in spread {
            let i = c + o
            if i >= 0 && i < count { h[i] = clamp(h[i] + amt * w, 0, caps[i]) }
        }
    }
}

// MARK: - Scene

final class LeafScene: SKScene {
    var airborne: [Leaf] = []
    var pool: [Leaf] = []
    var piles: [Int: Pile] = [:]                      // window number -> pile on top of it
    var lastRect: [Int: CGRect] = [:]
    var order: [(id: Int, rect: CGRect)] = []         // windows, front to back
    var ground: Pile?
    var texs: [SKTexture] = []
    let world = SKNode()
    let myPID = getpid()
    var lastT: TimeInterval = 0
    var pollAcc: CGFloat = 0
    var groundAcc: CGFloat = 0
    var t: CGFloat = 0
    var wind: CGFloat = 0
    var lastMouse = NSEvent.mouseLocation

    override func didMove(to view: SKView) {
        backgroundColor = .clear
        for shape in LeafShape.allCases { for rgb in palette { texs.append(makeLeafTexture(shape, rgb)) } }
        addChild(world)
        resetGround()
        for _ in 0..<Cfg.targetLeaves { spawnLeaf(y: rnd(0, size.height)) }
    }

    override func didChangeSize(_ oldSize: CGSize) {
        guard !texs.isEmpty else { return }
        resetGround()
    }

    /// The ground is the top of the Dock when it sits at the bottom of the screen (else the screen bottom)
    func groundTop() -> CGFloat {
        guard let s = NSScreen.screens.first else { return 0 }
        return max(0, s.visibleFrame.minY - s.frame.minY)
    }

    func resetGround() {
        if let g = ground { release(g, vel: .zero, id: -1) }
        ground = Pile(minX: 0, topY: groundTop(), width: size.width, maxH: Cfg.groundPileMax, density: 0.28, cap: 520)
    }

    func clearAll() {
        let all = Array(piles.values) + (ground.map { [$0] } ?? [])
        for p in all {
            for l in p.leaves { retire(l) }
            p.leaves.removeAll()
            p.h = Array(repeating: 0, count: p.count)
        }
    }

    // MARK: Leaf pool

    func obtain() -> Leaf {
        let l = pool.popLast() ?? Leaf(texture: texs[0])
        world.addChild(l.node)
        l.node.isHidden = false
        airborne.append(l)
        return l
    }

    func retire(_ l: Leaf) {
        l.node.removeFromParent()
        l.pile = nil
        pool.append(l)
    }

    func spawnLeaf(y: CGFloat? = nil) {
        let l = obtain()
        let r = CGFloat.random(in: 0...1)
        let li = r < 0.40 ? 0 : (r < 0.75 ? 1 : 2)   // 40% far, 35% middle, 25% near
        let L = layers[li]
        let s = CGFloat.random(in: L.size)
        l.node.texture = texs.randomElement()
        l.node.size = CGSize(width: s, height: s)
        l.node.alpha = CGFloat.random(in: L.alpha)
        l.node.zPosition = L.z
        l.fall = CGFloat.random(in: L.speed) * Cfg.fallSpeed
        l.swayAmp = CGFloat.random(in: L.sway)
        l.swayFreq = rnd(0.8, 1.8)
        l.phase = rnd(0, 6.28)
        l.flipFreq = rnd(1.5, 3.5)
        l.flipPhase = rnd(0, 6.28)
        l.rot0 = rnd(0, 6.28)
        l.spin = rnd(-1.2, 1.2)
        l.windFactor = L.wind
        l.inFront = li == 0 && CGFloat.random(in: 0...1) < Cfg.inFrontFraction
        l.ignoreID = -1
        l.vel = CGVector(dx: wind * L.wind, dy: -l.fall)
        l.node.position = CGPoint(x: rnd(-150, size.width + 40), y: y ?? (size.height + rnd(10, 300)))
    }

    // MARK: Settling and flying off

    func settle(_ l: Leaf, on p: Pile) {
        let n = l.node
        let x = clamp(n.position.x, p.minX + 2, p.minX + p.width - 2)
        guard let c = p.col(at: x) else { retire(l); return }
        n.removeFromParent()
        world.addChild(n)                              // newest leaf is drawn on top
        n.position = CGPoint(x: x, y: p.topY + p.h[c] + n.size.width * 0.12)
        n.zPosition = 5
        n.alpha = 1
        n.isHidden = false
        if CGFloat.random(in: 0...1) < 0.35 {          // seen from above
            n.zRotation = rnd(0, 6.28)
            n.xScale = rnd(0.8, 1)
        } else {                                       // lying on its side, flattened
            let side: CGFloat = Bool.random() ? 1 : -1
            n.zRotation = side * CGFloat.pi / 2 + rnd(-0.5, 0.5)
            n.xScale = rnd(0.3, 0.55)
        }
        n.yScale = 1
        l.pile = p
        l.col = c
        p.bump(c, Cfg.leafHeight)
        p.leaves.append(l)
        if p.leaves.count > p.maxLeaves {              // oldest leaf blows away
            let old = p.leaves.removeFirst()
            p.bump(old.col, -Cfg.leafHeight)
            retire(old)
        }
    }

    func launch(_ l: Leaf, vel: CGVector, from id: Int) {
        l.pile = nil
        l.node.isHidden = false
        l.node.zPosition = 6
        l.rot0 = l.node.zRotation
        l.vel = vel
        l.inFront = false
        l.ignoreID = id
        l.ignoreUntil = t + 0.4
        airborne.append(l)
    }

    /// Turn a whole pile into flying leaves. `vel` is the window's velocity, so faster drags fling leaves farther.
    func release(_ p: Pile, vel: CGVector, id: Int) {
        let f = CGVector(dx: clamp(vel.dx * 0.6, -900, 900), dy: clamp(vel.dy * 0.5, -300, 500))
        for l in p.leaves {
            launch(l, vel: CGVector(dx: f.dx + rnd(-60, 60), dy: f.dy + rnd(10, 120)), from: id)
        }
        p.leaves.removeAll()
        p.h = Array(repeating: 0, count: p.count)
    }

    // MARK: Per-frame update

    override func update(_ currentTime: TimeInterval) {
        if lastT == 0 { lastT = currentTime }
        let dt = CGFloat(min(currentTime - lastT, 1.0 / 20.0))
        lastT = currentTime
        t += dt
        pollAcc += dt
        if Double(pollAcc) >= Cfg.pollInterval { pollWindows(dt: pollAcc); pollAcc = 0 }

        // gentle breeze plus an occasional gust
        wind = 25 + 35 * sin(t * 0.21) + 70 * pow(max(0, sin(t * 0.07)), 8)

        stepLeaves(dt)
        if Cfg.swish { swish(dt) }
        var spawned = 0
        while airborne.count < Cfg.targetLeaves && spawned < 2 { spawnLeaf(); spawned += 1 }
    }

    func stepLeaves(_ dt: CGFloat) {
        let W = size.width
        let k = min(1, dt * 1.6)
        var i = airborne.count - 1
        while i >= 0 {
            let l = airborne[i], n = l.node
            let prevY = n.position.y
            let sw = sin(t * l.swayFreq + l.phase)
            l.vel.dx += (wind * l.windFactor + sw * l.swayAmp - l.vel.dx) * k
            l.vel.dy += (-l.fall - l.vel.dy) * k
            n.position.x += l.vel.dx * dt
            n.position.y += l.vel.dy * dt
            l.rot0 += l.spin * dt
            n.zRotation = l.rot0 + sw * 0.7
            n.xScale = 0.3 + 0.7 * abs(cos(t * l.flipFreq + l.flipPhase))   // fake 3D tumble
            n.yScale = 1
            if l.vel.dy < 0, let p = landing(l, prevY: prevY) {
                airborne.swapAt(i, airborne.count - 1); airborne.removeLast()
                settle(l, on: p)
            } else if n.position.y < -80 || n.position.x < -250 || n.position.x > W + 250 {
                airborne.swapAt(i, airborne.count - 1); airborne.removeLast()
                retire(l)
            }
            i -= 1
        }
    }

    /// First surface a falling leaf crosses this frame: window tops (front to back), then the ground
    func landing(_ l: Leaf, prevY: CGFloat) -> Pile? {
        let x = l.node.position.x, y = l.node.position.y
        func crosses(_ p: Pile) -> Bool {
            guard let c = p.col(at: x), !p.occ[c] else { return false }
            let s = p.surface(c)
            return prevY >= s && y < s
        }
        if !l.inFront {
            for item in order {
                guard let p = piles[item.id] else { continue }
                if l.ignoreID == item.id && t < l.ignoreUntil { continue }
                if crosses(p) { return p }
            }
        }
        if let g = ground, let c = g.col(at: x), y < g.surface(c) { return g }
        return nil
    }

    // MARK: Mouse swish

    func swish(_ dt: CGFloat) {
        let m = NSEvent.mouseLocation
        defer { lastMouse = m }
        guard dt > 0 else { return }
        let v = CGVector(dx: (m.x - lastMouse.x) / dt, dy: (m.y - lastMouse.y) / dt)
        guard hypot(v.dx, v.dy) > Cfg.swishMinSpeed else { return }
        let r2 = Cfg.swishRadius * Cfg.swishRadius
        var all: [(Int, Pile)] = piles.map { ($0.key, $0.value) }
        if let g = ground { all.append((-1, g)) }
        for (id, p) in all {
            guard m.x > p.minX - 60, m.x < p.minX + p.width + 60,
                  m.y > p.topY - 40, m.y < p.topY + 120 else { continue }
            var keep: [Leaf] = []
            for l in p.leaves {
                let dx = l.node.position.x - m.x, dy = l.node.position.y - m.y
                if !l.node.isHidden && dx * dx + dy * dy < r2 {
                    p.bump(l.col, -Cfg.leafHeight)
                    let kick = CGVector(dx: clamp(v.dx * 0.45, -700, 700) + rnd(-80, 80),
                                        dy: clamp(v.dy * 0.45, -400, 700) + rnd(60, 220))
                    launch(l, vel: kick, from: id)
                } else {
                    keep.append(l)
                }
            }
            p.leaves = keep
        }
    }

    // MARK: Windows (macOS origin is top-left, SpriteKit is bottom-left, so flip y)

    func pollWindows(dt: CGFloat) {
        let H = size.height, W = size.width
        var newOrder: [(id: Int, rect: CGRect)] = []
        if let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] {
            for w in info {
                guard let layerN = w[kCGWindowLayer as String] as? NSNumber, layerN.intValue == 0,
                      let pidN = w[kCGWindowOwnerPID as String] as? NSNumber, pidN.int32Value != myPID,
                      let numN = w[kCGWindowNumber as String] as? NSNumber,
                      let bd = w[kCGWindowBounds as String] as? NSDictionary,
                      let b = CGRect(dictionaryRepresentation: bd as CFDictionary) else { continue }
                let alpha = (w[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1
                if alpha < 0.05 || b.width < 100 || b.height < 50 { continue }
                let r = CGRect(x: b.minX, y: H - b.maxY, width: b.width, height: b.height)
                if r.maxY >= H - 1 || r.maxX < 20 || r.minX > W - 20 { continue }   // fullscreen / other display
                newOrder.append((id: numN.intValue, rect: r))
            }
        }

        // Closed or minimized windows: their leaves just fall
        let alive = Set(newOrder.map { $0.id })
        for (id, pile) in piles where !alive.contains(id) {
            release(pile, vel: .zero, id: id)
            piles[id] = nil
            lastRect[id] = nil
        }

        for item in newOrder {
            let id = item.id, r = item.rect
            if let pile = piles[id], let old = lastRect[id] {
                if abs(old.width - r.width) > 0.5 {
                    release(pile, vel: .zero, id: id)   // resized: start a fresh pile
                    piles[id] = makeWindowPile(r)
                } else if abs(old.minX - r.minX) > 0.3 || abs(old.maxY - r.maxY) > 0.3 {
                    // dragged: fling the leaves off
                    let v = CGVector(dx: (r.minX - old.minX) / dt, dy: (r.maxY - old.maxY) / dt)
                    release(pile, vel: v, id: id)
                    pile.minX = r.minX
                    pile.topY = r.maxY
                }
            } else {
                piles[id] = makeWindowPile(r)
            }
            lastRect[id] = r
        }
        order = newOrder

        // The Dock can show / hide: keep the ground at its top edge
        groundAcc += dt
        if groundAcc >= 1 {
            groundAcc = 0
            if let g = ground, abs(g.topY - groundTop()) > 1 { resetGround() }
        }

        computeOcclusion()
    }

    func makeWindowPile(_ r: CGRect) -> Pile {
        Pile(minX: r.minX, topY: r.maxY, width: r.width, maxH: Cfg.windowPileMax, density: 0.11, cap: 140)
    }

    /// Hide the part of a pile that sits behind a window in front of it
    func computeOcclusion() {
        for (idx, item) in order.enumerated() {
            guard let p = piles[item.id] else { continue }
            for c in 0..<p.count {
                let pt = CGPoint(x: p.colX(c), y: p.topY + 1)
                var hidden = false
                for j in 0..<idx where order[j].rect.contains(pt) { hidden = true; break }
                p.occ[c] = hidden
            }
            for l in p.leaves { l.node.isHidden = p.occ[l.col] }
        }
    }
}

// MARK: - App: transparent click-through overlay + menu bar item

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var scene: LeafScene!
    var statusItem: NSStatusItem!
    var pauseItem: NSMenuItem!
    var swishItem: NSMenuItem!
    var amountItems: [NSMenuItem] = []
    var paused = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let screen = NSScreen.screens.first else { NSApp.terminate(nil); return }
        window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.level = .statusBar                      // above windows and the Dock
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true               // every click goes through to what is underneath
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]

        let skView = SKView(frame: NSRect(origin: .zero, size: screen.frame.size))
        skView.allowsTransparency = true
        window.contentView = skView
        scene = LeafScene(size: screen.frame.size)
        scene.scaleMode = .resizeFill
        skView.presentScene(scene)
        window.orderFrontRegardless()

        buildMenu()
        NotificationCenter.default.addObserver(self, selector: #selector(screenChanged),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    func buildMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "🍂"
        let menu = NSMenu()

        pauseItem = NSMenuItem(title: "Pause", action: #selector(togglePause), keyEquivalent: "p")
        pauseItem.target = self
        menu.addItem(pauseItem)
        menu.addItem(.separator())

        for (title, n) in [("Light", 40), ("Medium", 90), ("Heavy", 180)] {
            let item = NSMenuItem(title: "\(title) leaf fall", action: #selector(setAmount(_:)), keyEquivalent: "")
            item.tag = n
            item.target = self
            item.state = n == Cfg.targetLeaves ? .on : .off
            amountItems.append(item)
            menu.addItem(item)
        }
        menu.addItem(.separator())

        swishItem = NSMenuItem(title: "Swish mouse to scatter leaves", action: #selector(toggleSwish), keyEquivalent: "")
        swishItem.target = self
        swishItem.state = .on
        menu.addItem(swishItem)

        let clear = NSMenuItem(title: "Sweep up all leaves", action: #selector(clearLeaves), keyEquivalent: "")
        clear.target = self
        menu.addItem(clear)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    @objc func togglePause() {
        paused.toggle()
        scene.isPaused = paused
        if paused { window.orderOut(nil) } else { window.orderFrontRegardless() }
        pauseItem.title = paused ? "Resume" : "Pause"
    }

    @objc func setAmount(_ sender: NSMenuItem) {
        Cfg.targetLeaves = sender.tag
        for i in amountItems { i.state = i === sender ? .on : .off }
    }

    @objc func toggleSwish() {
        Cfg.swish.toggle()
        swishItem.state = Cfg.swish ? .on : .off
    }

    @objc func clearLeaves() { scene.clearAll() }

    @objc func screenChanged() {
        guard let s = NSScreen.screens.first else { return }
        window.setFrame(s.frame, display: true)
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)     // no Dock icon
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()                               // blocks here, so `delegate` stays alive
}
