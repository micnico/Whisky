//
//  GraphicsBackendSettingsView.swift
//  Whisky
//
//  This file is part of Whisky.
//
//  Whisky is free software: you can redistribute it and/or modify it under the terms
//  of the GNU General Public License as published by the Free Software Foundation,
//  either version 3 of the License, or (at your option) any later version.
//
//  Whisky is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
//  without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
//  See the GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License along with Whisky.
//  If not, see https://www.gnu.org/licenses/.
//

import SwiftUI
import UniformTypeIdentifiers
import WhiskyKit

struct GraphicsBackendSettingsView: View {
    @ObservedObject var bottle: Bottle
    @State private var importerPresented = false
    @State private var errorMessage: String?

    var body: some View {
        Group {
            Picker("Graphics backend", selection: backendBinding) {
                ForEach(availableBackends, id: \.self) { backend in
                    Text(label(for: backend)).tag(backend)
                }
            }
            Button("Select GPTK 4 folder…") {
                importerPresented = true
            }
            if let installation = bottle.settings.d3dMetalInstallation {
                Text("D3DMetal \(installation.version) — \(installation.rootURL.path)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .fileImporter(
            isPresented: $importerPresented,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false,
            onCompletion: { result in importD3DMetal(result) }
        )
        .alert(
            "Graphics backend",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var availableBackends: [GraphicsBackend] {
        var backends: [GraphicsBackend] = [.wineD3D]
        if WhiskyWineInstaller.supportsDXVK(id: bottle.settings.runtimeID) { backends.append(.dxvk) }
        if WhiskyWineInstaller.supportsD3DMetal(id: bottle.settings.runtimeID),
           bottle.settings.d3dMetalInstallation != nil {
            backends.append(.d3dMetal)
        }
        if !backends.contains(bottle.settings.graphicsBackend) {
            backends.insert(bottle.settings.graphicsBackend, at: 0)
        }
        return backends
    }

    private var backendBinding: Binding<GraphicsBackend> {
        Binding(
            get: { bottle.settings.graphicsBackend },
            set: { backend in selectBackend(backend) }
        )
    }

    private func selectBackend(_ backend: GraphicsBackend) {
        let previous = bottle.settings.graphicsBackend
        bottle.settings.graphicsBackend = backend
        do {
            try Wine.prepareGraphicsBackend(for: bottle)
        } catch {
            bottle.settings.graphicsBackend = previous
            errorMessage = error.localizedDescription
        }
    }

    private func importD3DMetal(_ result: Result<[URL], Error>) {
        do {
            let url = try result.get().first
            guard let url else { return }
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            bottle.settings.d3dMetalInstallation = try D3DMetalInstallation.detect(at: url)
            if WhiskyWineInstaller.supportsD3DMetal(id: bottle.settings.runtimeID) {
                selectBackend(.d3dMetal)
            } else {
                errorMessage = GraphicsBackendError.d3dMetalUnsupportedRuntime.localizedDescription
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func label(for backend: GraphicsBackend) -> String {
        switch backend {
        case .legacy: return "Existing Bottle behavior"
        case .wineD3D: return "WineD3D / runtime default"
        case .dxvk: return "DXVK / MoltenVK"
        case .d3dMetal: return "D3DMetal 4 + 32-bit DXVK"
        }
    }
}
