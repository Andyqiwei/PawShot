//
//  PawShotApp.swift
//  PawShot
//
//  Created by Andy Liu on 2/7/26.
//

import SwiftUI

@main
struct PawShotApp: App {
    @StateObject private var appSettings = AppSettingsStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appSettings)
        }
    }
}
