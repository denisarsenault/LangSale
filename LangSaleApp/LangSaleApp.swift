//
//  LangSaleApp.swift
//  LangSale
//
//
//  Created by Denis Arsenault on 11/11/26.
//
//

import SwiftUI

@main
struct LangSaleApp: App {
    var body: some Scene {
        WindowGroup {
            #if DEBUG
            // UI tests pass -uiTesting to skip the model download and use fixed preview state.
            ContentView(model: ProcessInfo.processInfo.arguments.contains("-uiTesting")
                        ? .preview() : AppModel())
            #else
            ContentView()
            #endif
        }
    }
}
