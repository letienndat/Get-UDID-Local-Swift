//
//  Get_UDID_Local_SwiftApp.swift
//  Get UDID Local Swift
//
//  Created by Le Tien Dat on 2/25/26.
//

import SwiftUI

@main
struct Get_UDID_Local_SwiftApp: App {
    @StateObject private var localServer = LocalServer.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
                    localServer.appDidEnterBackground()
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                    localServer.appWillEnterForgeground()
                }
        }
    }
}
