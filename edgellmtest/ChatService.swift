//
//  ChatService.swift
//  edgellmtest
//
//  Created by Ahmed El Shami on 2025-08-01.
//


// App-wide singleton you inject with `.environment`
final actor ChatService {
    static let shared = ChatService()
    private var engine: Chat?

    func engine(for model: OnDeviceModel) async throws -> Chat {
        if let e = engine { return e }
        engine = try Chat(model: model)   // heavy work, but not on MainActor
        return engine!
    }
}
