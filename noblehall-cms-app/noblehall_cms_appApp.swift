//
//  noblehall_cms_appApp.swift
//  noblehall-cms-app
//

import SwiftData
import SwiftUI
import UIKit

@main
struct noblehall_cms_appApp: App {
    @UIApplicationDelegateAdaptor(NoblehallAppDelegate.self) private var appDelegate

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
