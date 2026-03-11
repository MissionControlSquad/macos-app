//
//  ContentView.swift
//  app
//
//  Created by DHARMIK JAGODANA on 10/03/26.
//

import SwiftUI

struct ContentView: View {
    @State private var appState = AppState()

    var body: some View {
        Group {
            if appState.isChecking {
                loadingView
            } else if appState.needsSetup {
                OnboardingView(appState: appState)
            } else {
                DashboardView()
            }
        }
        .frame(minWidth: 700, minHeight: 500)
        .task {
            await appState.checkAll()
        }
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text("Checking your system...")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    ContentView()
}
