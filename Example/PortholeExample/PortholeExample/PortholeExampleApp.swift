//
//  PortholeExampleApp.swift
//  PortholeExample
//
//  Created by Sohan Jain on 18/07/26.
//

import SwiftUI
import Atlantis

@main
struct PortholeExampleApp: App {
    init() {
        Atlantis.start()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
