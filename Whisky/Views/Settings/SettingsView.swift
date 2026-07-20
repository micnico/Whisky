//
//  SettingsView.swift
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

struct SettingsView: View {
    @AppStorage("SUEnableAutomaticChecks") var whiskyUpdate = true
    @AppStorage("killOnTerminate") var killOnTerminate = true
    @AppStorage("checkWhiskyWineUpdates") var checkWhiskyWineUpdates = true
    @AppStorage("defaultBottleLocation") var defaultBottleLocation = BottleData.defaultBottleDir
    @State private var activeRuntimeID = WhiskyWineInstaller.activeRuntimeID()
    @State private var importingRuntime = false
    @State private var runtimeMessage: String?
    @State private var runtimeImportFailed = false

    var body: some View {
        Form {
            Section("settings.general") {
                Toggle("settings.toggle.kill.on.terminate", isOn: $killOnTerminate)
                ActionView(
                    text: "settings.path",
                    subtitle: defaultBottleLocation.prettyPath(),
                    actionName: "create.browse"
                ) {
                    let panel = NSOpenPanel()
                    panel.canChooseFiles = false
                    panel.canChooseDirectories = true
                    panel.allowsMultipleSelection = false
                    panel.canCreateDirectories = true
                    panel.directoryURL = BottleData.containerDir
                    panel.begin { result in
                        if result == .OK, let url = panel.urls.first {
                            defaultBottleLocation = url
                        }
                    }
                }
            }
            Section("settings.updates") {
                Toggle("settings.toggle.whisky.updates", isOn: $whiskyUpdate)
                Toggle("settings.toggle.whiskywine.updates", isOn: $checkWhiskyWineUpdates)
            }
            Section("settings.runtime") {
                Picker("settings.runtime.default", selection: activeRuntimeBinding) {
                    ForEach(WhiskyWineInstaller.installedRuntimeIDs(), id: \.self) { runtimeID in
                        Text(runtimeID).tag(runtimeID)
                    }
                }
                ActionView(
                    text: "settings.runtime.import",
                    subtitle: String(localized: "settings.runtime.import.subtitle"),
                    actionName: "settings.runtime.choose",
                    action: chooseRuntimeArchive
                )
                .disabled(importingRuntime)
                if importingRuntime {
                    ProgressView()
                        .controlSize(.small)
                }
                if let runtimeMessage {
                    Text(runtimeMessage)
                        .font(.callout)
                        .foregroundStyle(runtimeImportFailed ? .red : .secondary)
                }
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
        .frame(width: ViewWidth.medium)
    }
}

private extension SettingsView {
    var activeRuntimeBinding: Binding<String> {
        Binding(
            get: { activeRuntimeID },
            set: { runtimeID in
                do {
                    try WhiskyWineInstaller.activateRuntime(id: runtimeID)
                    activeRuntimeID = runtimeID
                    runtimeMessage = nil
                } catch {
                    runtimeImportFailed = true
                    runtimeMessage = error.localizedDescription
                }
            }
        )
    }

    func chooseRuntimeArchive() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.gzip]
        panel.begin { result in
            guard result == .OK, let archive = panel.url else { return }
            importingRuntime = true
            runtimeMessage = nil
            Task.detached(priority: .userInitiated) {
                do {
                    try WhiskyWineInstaller.installAcceptedWine11Runtime(from: archive)
                    await MainActor.run {
                        activeRuntimeID = WhiskyWineInstaller.acceptedWine11RuntimeID
                        importingRuntime = false
                        runtimeImportFailed = false
                        runtimeMessage = String(localized: "settings.runtime.import.success")
                    }
                } catch {
                    await MainActor.run {
                        importingRuntime = false
                        runtimeImportFailed = true
                        runtimeMessage = error.localizedDescription
                    }
                }
            }
        }
    }
}

#Preview {
    SettingsView()
}
