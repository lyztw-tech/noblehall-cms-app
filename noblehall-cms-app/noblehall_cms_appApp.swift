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
    @State private var notificationInbox = NotificationInboxStore()
    @State private var notificationNav = NotificationNavigationCoordinator()

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environment(sessionStore)
                .environment(networkMonitor)
                .environment(notificationInbox)
                .environment(notificationNav)
                .modelContainer(AppModelContainer.shared)
                .onAppear {
                    notificationInbox.bind(session: sessionStore)
                }
        }
    }
}
