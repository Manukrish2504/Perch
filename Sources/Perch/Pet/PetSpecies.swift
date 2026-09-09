import SwiftUI

/// A pet: the mascot silhouette in its own palette, with one distinguishing mark.
///
/// Every species shares the same rig — body, eyes, two hands, four legs — because
/// the animations are built on named parts. Giving each a different skeleton would
/// mean a different walk, lean and jump for each one.
struct PetSpecies: Identifiable, Hashable {
    enum Mark: Hashable {
        case none
        case leaf
        case antenna
        case tuft
        case cloud
    }

    let id: String
    let name: String
    let blurb: String
    let mark: Mark

    let body: RGB
    let shade: RGB
    let dark: RGB
    let accent: RGB

    struct RGB: Hashable {
        let r, g, b: Double
        var color: Color { Color(red: r, green: g, blue: b) }
    }

    static let all: [PetSpecies] = [pip, sprig, byte, ember, nimbus]

    static func named(_ id: String) -> PetSpecies {
        all.first { $0.id == id } ?? pip
    }

    /// The original terracotta, #DD775B.
    static let pip = PetSpecies(
        id: "pip", name: "Pip",
        blurb: "The classic. Terracotta, four legs, quietly pleased with itself.",
        mark: .none,
        body: RGB(r: 0.867, g: 0.467, b: 0.357),
        shade: RGB(r: 0.741, g: 0.373, b: 0.278),
        dark: RGB(r: 0.106, g: 0.094, b: 0.090),
        accent: RGB(r: 0.98, g: 0.98, b: 0.98)
    )

    static let sprig = PetSpecies(
        id: "sprig", name: "Sprig",
        blurb: "Grows a little every day you show up.",
        mark: .leaf,
        body: RGB(r: 0.510, g: 0.729, b: 0.475),
        shade: RGB(r: 0.396, g: 0.596, b: 0.373),
        dark: RGB(r: 0.086, g: 0.129, b: 0.086),
        accent: RGB(r: 0.945, g: 0.867, b: 0.400)
    )

    static let byte = PetSpecies(
        id: "byte", name: "Byte",
        blurb: "Reads the logs so you don't have to.",
        mark: .antenna,
        body: RGB(r: 0.451, g: 0.573, b: 0.780),
        shade: RGB(r: 0.337, g: 0.435, b: 0.612),
        dark: RGB(r: 0.078, g: 0.106, b: 0.180),
        accent: RGB(r: 0.400, g: 0.878, b: 0.929)
    )

    static let ember = PetSpecies(
        id: "ember", name: "Ember",
        blurb: "Burns brightest on a streak.",
        mark: .tuft,
        body: RGB(r: 0.929, g: 0.596, b: 0.278),
        shade: RGB(r: 0.796, g: 0.451, b: 0.184),
        dark: RGB(r: 0.196, g: 0.106, b: 0.055),
        accent: RGB(r: 0.976, g: 0.827, b: 0.353)
    )

    static let nimbus = PetSpecies(
        id: "nimbus", name: "Nimbus",
        blurb: "Floats above the token count.",
        mark: .cloud,
        body: RGB(r: 0.784, g: 0.706, b: 0.859),
        shade: RGB(r: 0.639, g: 0.561, b: 0.729),
        dark: RGB(r: 0.145, g: 0.114, b: 0.196),
        accent: RGB(r: 0.949, g: 0.949, b: 0.976)
    )
}
