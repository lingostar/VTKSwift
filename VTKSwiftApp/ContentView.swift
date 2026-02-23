//
//  ContentView.swift
//  VTKSwiftApp
//
//  Main content view displaying a VTK-rendered 3D sphere.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        VTKView()
            .ignoresSafeArea()
    }
}

#Preview {
    ContentView()
}
