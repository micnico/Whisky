//
//  Wine+GraphicsBackend.swift
//  WhiskyKit
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

import Foundation

public extension Wine {
    static func enableDXVK(bottle: Bottle) throws {
        guard WhiskyWineInstaller.supportsDXVK(id: runtimeID(for: bottle)) else { return }
        try replaceGraphicsDLLs(for: bottle, x64: "DXVK/x64", x32: "DXVK/x32")
    }

    static func prepareGraphicsBackend(for bottle: Bottle) throws {
        switch bottle.settings.graphicsBackend {
        case .legacy:
            if bottle.settings.dxvk { try enableDXVK(bottle: bottle) }
        case .wineD3D:
            try restoreWineD3D(bottle: bottle)
        case .dxvk:
            guard WhiskyWineInstaller.supportsDXVK(id: runtimeID(for: bottle)) else {
                throw GraphicsBackendError.dxvkUnavailable
            }
            try restoreWineD3D(bottle: bottle)
            try enableDXVK(bottle: bottle)
        case .d3dMetal:
            guard WhiskyWineInstaller.supportsD3DMetal(id: runtimeID(for: bottle)) else {
                throw GraphicsBackendError.d3dMetalUnsupportedRuntime
            }
            guard let saved = bottle.settings.d3dMetalInstallation else {
                throw GraphicsBackendError.d3dMetalNotConfigured
            }
            let current = try D3DMetalInstallation.detect(at: saved.rootURL)
            guard current.version == saved.version,
                  current.contentSHA256 == saved.contentSHA256 else {
                throw GraphicsBackendError.d3dMetalInstallationChanged
            }
            try restoreWineD3D(bottle: bottle)
            try FileManager.default.replaceDLLs(
                in: bottle.url.appending(path: "drive_c/windows/system32"),
                withContentsIn: current.windowsDLLURL,
                names: ["d3d10.dll", "d3d11.dll", "d3d12.dll", "dxgi.dll"],
                symbolicLinks: true
            )
            if WhiskyWineInstaller.supportsDXVK(id: runtimeID(for: bottle)) {
                try replaceGraphicsDLLs(for: bottle, x32: "DXVK/x32")
            }
        }
    }

    static func restoreWineD3D(bottle: Bottle) throws {
        try replaceGraphicsDLLs(
            for: bottle, x64: "Wine/lib/wine/x86_64-windows", x32: "Wine/lib/wine/i386-windows",
            names: graphicsDLLNames
        )
    }

    private static var graphicsDLLNames: Set<String> {
        [
            "d3d9.dll", "d3d10.dll", "d3d10_1.dll", "d3d10core.dll",
            "d3d11.dll", "d3d12.dll", "d3d12core.dll", "dxgi.dll"
        ]
    }

    private static func replaceGraphicsDLLs(
        for bottle: Bottle, x64: String? = nil, x32: String? = nil, names: Set<String>? = nil
    ) throws {
        let library = WhiskyWineInstaller.libraryFolder(for: runtimeID(for: bottle))
        if let x64 {
            try FileManager.default.replaceDLLs(
                in: bottle.url.appending(path: "drive_c/windows/system32"),
                withContentsIn: library.appending(path: x64),
                names: names
            )
        }
        if let x32 {
            try FileManager.default.replaceDLLs(
                in: bottle.url.appending(path: "drive_c/windows/syswow64"),
                withContentsIn: library.appending(path: x32),
                names: names
            )
        }
    }
}

public enum GraphicsBackendError: LocalizedError, Equatable {
    case dxvkUnavailable
    case d3dMetalUnsupportedRuntime
    case d3dMetalNotConfigured
    case d3dMetalInstallationChanged

    public var errorDescription: String? {
        switch self {
        case .dxvkUnavailable: return "The selected runtime does not contain both DXVK architectures."
        case .d3dMetalUnsupportedRuntime: return "D3DMetal requires a verified CrossOver Wine runtime."
        case .d3dMetalNotConfigured: return "No user-provided D3DMetal installation is bound to this Bottle."
        case .d3dMetalInstallationChanged:
            return "D3DMetal changed; select the installation again before launching."
        }
    }
}
