//
//  AIChatRole.swift
//  husk
//

import Foundation

/// Provider-neutral roles used by Husk's persistence and UI layers.
enum Role: String, Codable, Sendable {
    case system
    case user
    case assistant
    case tool
}

