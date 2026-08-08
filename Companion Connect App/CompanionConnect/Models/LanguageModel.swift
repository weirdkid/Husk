//
//  LanguageModel.swift
//  CompanionConnect
//
//  Created by Nathan Ellis on 30/05/2025.
//
import Foundation

struct LanguageModel: Equatable, Hashable, Identifiable {
    var id: String { "\(provider.rawValue):\(name)" }
    var name: String
    var provider: Provider
}
