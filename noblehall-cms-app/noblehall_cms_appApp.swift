//
//  noblehall_cms_appApp.swift
//  noblehall-cms-app
//

import SwiftData
import SwiftUI

@main
struct noblehall_cms_appApp: App {
    @State private var sessionStore = SessionStore()
    @State private var networkMonitor = NetworkPathMonitor()

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environment(sessionStore)
                .environment(networkMonitor)
                .modelContainer(AppModelContainer.shared)
        }
    }
}
