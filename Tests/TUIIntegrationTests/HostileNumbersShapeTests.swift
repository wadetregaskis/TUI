//  🖥️ TUI — A Terminal UI framework for Swift
//  HostileNumbersShapeTests.swift
//
//  Shapes and gradients built from hostile numbers — corner radii, trims,
//  stroke widths, insets, stop locations, radii, angles, unit points and mesh
//  grids whose counts do not match their points: each must draw without
//  trapping or hanging. See HostileNumbersSupport.swift.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

import TUI
@testable import TUIAppTestSupport
@testable import TUIFoundation
@testable import TUITestSupport

@MainActor
@Suite("Hostile numbers: shapes and gradients")
struct HostileNumbersShapeTests {

    @Test("A shape of any corner radius, trim, stroke or inset draws", arguments: Hostile.doubles)
    func shapes(value: Double) {
        let length = CGFloat(value)
        drawHostile(RoundedRectangle(cornerRadius: length).fill(.red))
        drawHostile(Rectangle().fill(.red).frame(width: 10, height: 4).clipShape(.rect(cornerRadius: length)))
        drawHostile(Circle().trim(from: length, to: 1).stroke(.red))
        drawHostile(Circle().trim(from: 0, to: length).stroke(.red))
        drawHostile(Circle().trim(from: length, to: length).fill(.red))
        drawHostile(Rectangle().stroke(.red, lineWidth: length))
        drawHostile(Circle().stroke(lineWidth: length))
        drawHostile(Capsule().strokeBorder(.red, lineWidth: length))
        drawHostile(Ellipse().inset(by: length).fill(.red))
        drawHostile(RoundedRectangle(cornerRadius: 2).inset(by: length).fill(.red))
        drawHostile(Rectangle().rotation(.degrees(value)).fill(.red))
        drawHostile(Rectangle().scale(length).fill(.red))
        drawHostile(Rectangle().scale(x: length, y: 1).fill(.red))
        drawHostile(Rectangle().offset(x: length, y: length).fill(.red))
        drawHostile(Rectangle().size(width: length, height: length).fill(.red))
        drawHostile(Rectangle().stroke(.red, style: StrokeStyle(lineWidth: 1, dash: [length, length])))
        drawHostile(Rectangle().stroke(.red, style: StrokeStyle(lineWidth: 1, dash: [2, 2], dashPhase: length)))
        drawHostile(Rectangle().rotation(.degrees(30), anchor: UnitPoint(x: value, y: value)).fill(.red))
    }

    @Test("A path of any geometry draws", arguments: Hostile.doubles)
    func paths(value: Double) {
        let length = CGFloat(value)
        let rect = CGRect(x: length, y: 0, width: 10, height: length)
        drawHostile(Path(roundedRect: CGRect(x: 0, y: 0, width: 10, height: 4), cornerRadius: length).fill(.red))
        drawHostile(Path(rect).stroke(.red))
        drawHostile(Path(ellipseIn: rect).fill(.red))
        drawHostile(
            Path { path in
                path.move(to: .zero)
                path.addLine(to: CGPoint(x: length, y: length))
                path.addArc(
                    center: CGPoint(x: 5, y: 2), radius: length, startAngle: .degrees(0), endAngle: .degrees(value),
                    clockwise: false)
                path.addQuadCurve(to: CGPoint(x: 1, y: 1), control: CGPoint(x: length, y: 0))
                path.closeSubpath()
            }
            .stroke(.red, lineWidth: 1))
    }

    @Test("A gradient of any stop, point, radius or angle draws", arguments: Hostile.doubles)
    func gradients(value: Double) {
        let stops = [Gradient.Stop(color: .red, location: value), Gradient.Stop(color: .blue, location: 1)]
        let point = UnitPoint(x: value, y: value)
        drawHostile(Rectangle().fill(LinearGradient(stops: stops, startPoint: .leading, endPoint: .trailing)))
        drawHostile(Rectangle().fill(LinearGradient(colors: [.red, .blue], startPoint: point, endPoint: .trailing)))
        drawHostile(Rectangle().fill(LinearGradient(colors: [.red, .blue], startPoint: point, endPoint: point)))
        drawHostile(Rectangle().fill(RadialGradient(stops: stops, center: .center, startRadius: 0, endRadius: 10)))
        drawHostile(Rectangle().fill(RadialGradient(colors: [.red, .blue], center: point, startRadius: 0, endRadius: 10)))
        drawHostile(Rectangle().fill(AngularGradient(stops: stops, center: .center)))
        drawHostile(
            Rectangle().fill(
                AngularGradient(
                    colors: [.red, .blue], center: point, startAngle: .degrees(value), endAngle: .degrees(360))))
        drawHostile(Rectangle().fill(AngularGradient(colors: [.red, .blue], center: .center, angle: .radians(value))))
        drawHostile(
            Rectangle().fill(
                EllipticalGradient(
                    colors: [.red, .blue], center: point, startRadiusFraction: value, endRadiusFraction: value)))
        drawHostile(Rectangle().fill(EllipticalGradient(stops: stops)))
        drawHostile(Text("gradient").foregroundStyle(LinearGradient(stops: stops, startPoint: .top, endPoint: .bottom)))
    }

    @Test("A radial gradient of any radius draws", arguments: Hostile.ints)
    func radialRadii(radius: Int) {
        drawHostile(
            Rectangle().fill(RadialGradient(colors: [.red, .blue], center: .center, startRadius: radius, endRadius: 10)))
        drawHostile(
            Rectangle().fill(RadialGradient(colors: [.red, .blue], center: .center, startRadius: 0, endRadius: radius)))
        drawHostile(
            Rectangle().fill(
                RadialGradient(colors: [.red, .blue], center: .center, startRadius: radius, endRadius: radius)))
    }

    @Test("A mesh gradient of any point draws", arguments: Hostile.doubles)
    func meshPoints(value: Double) {
        let float = Float(value)
        let points: [SIMD2<Float>] = [[0, 0], [float, 0], [0, 1], [1, float]]
        drawHostile(
            Rectangle().fill(MeshGradient(width: 2, height: 2, points: points, colors: [.red, .blue, .green, .yellow])))
    }

    @Test("A mesh gradient of any grid draws, its counts matching or not", arguments: Hostile.ints)
    func meshCounts(count: Int) {
        let points: [SIMD2<Float>] = [[0, 0], [1, 0], [0, 1], [1, 1]]
        let colors: [Color] = [.red, .blue, .green, .yellow]
        drawHostile(Rectangle().fill(MeshGradient(width: count, height: 2, points: points, colors: colors)))
        drawHostile(Rectangle().fill(MeshGradient(width: 2, height: count, points: points, colors: colors)))
        drawHostile(Rectangle().fill(MeshGradient(width: count, height: count, points: points, colors: colors)))
        drawHostile(Rectangle().fill(MeshGradient(width: 3, height: 3, points: points, colors: colors)))
        drawHostile(Rectangle().fill(MeshGradient(width: 2, height: 2, points: [], colors: colors)))
        drawHostile(Rectangle().fill(MeshGradient(width: 2, height: 2, points: points, colors: [])))
        drawHostile(Rectangle().fill(MeshGradient(width: 1, height: 1, points: [[0, 0]], colors: [.red])))
    }
}
