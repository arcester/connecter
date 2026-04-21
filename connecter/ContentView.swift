//
//  ContentView.swift
//  connecter
//
//  Created by J. Guzmán Arce Sáez on 13/04/2026.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var mountManager: MountManager

    var body: some View {
        TabView {
            SharesTab()
                .tabItem { Label("Shares", systemImage: "externaldrive") }

            SettingsTab()
                .tabItem { Label("Settings", systemImage: "gear") }

            LogView()
                .tabItem { Label("Log", systemImage: "terminal") }
        }
        .frame(minWidth: 560, minHeight: 400)
        .onAppear { mountManager.startMonitoring() }
    }
}

#Preview {
    ContentView()
        .environmentObject(MountManager())
        .environmentObject(LoginItemManager())
}
