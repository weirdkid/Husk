//
//  Provider.swift
//  husk
//
//  Created by Nathan Ellis on 30/05/2025.
//
import Foundation

struct Provider: RawRepresentable, Codable, Hashable, Sendable {
    let rawValue: String

    static let openAICompatible = Provider(rawValue: "openAICompatible")

    var displayName: String {
        rawValue == Self.openAICompatible.rawValue ? "OpenAI-compatible" : rawValue
    }
}
