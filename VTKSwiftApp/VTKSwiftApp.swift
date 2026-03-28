//
//  VTKSwiftApp.swift
//  VTKSwiftApp
//
//  Entry point for the VTK + SwiftUI multiplatform app.
//  Targets: iPad (iOS) and Mac (macOS).
//

import SwiftUI
import SwiftData

@main
struct VTKSwiftApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [CaseRecord.self, ReportRecord.self])
    }
}
