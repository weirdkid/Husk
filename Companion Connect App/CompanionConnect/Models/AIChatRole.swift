//
//  AIChatRole.swift
//  CompanionConnect
//

import Foundation

/// Provider-neutral roles used by Companion Connect's persistence and UI layers.
enum Role: String, Codable, Sendable {
    case system
    case user
    case assistant
    case tool
}
