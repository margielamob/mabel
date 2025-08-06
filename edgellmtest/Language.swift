//
//  Language.swift
//  edgellmtest
//
//  Created by Ahmed El Shami on 2025-07-18.
//
import Foundation

/// Represents a language with a name and a unique identifier.
struct Language: Identifiable, Hashable, Equatable {
    let id: String
    let name: String
    var bcp47Code: String
    static func == (lhs: Language, rhs: Language) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

extension Language {
    // Define the list of supported languages.
    static let english  = Language(id: "en", name: "English",  bcp47Code: "en-US")
      static let french   = Language(id: "fr", name: "French",   bcp47Code: "fr-FR")
      static let spanish  = Language(id: "es", name: "Spanish",  bcp47Code: "es-ES") 
      static let german   = Language(id: "de", name: "German",   bcp47Code: "de-DE")
      static let japanese = Language(id: "ja", name: "Japanese", bcp47Code: "ja-JP")
      static let arabic   = Language(id: "ar", name: "Arabic",   bcp47Code: "ar-SA")
    /// Provides an array of all available languages for selection.
    static var all: [Language] {
        [
            .english,
            .french,
            .spanish,
            .german,
            .japanese,
            .arabic
        ]
    }
}
