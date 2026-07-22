//
//  GraphicsBackendTests.swift
//  WhiskyKitTests
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
import XCTest
@testable import WhiskyKit

final class GraphicsBackendTests: XCTestCase {
    func testOldMetadataKeepsLegacyGraphicsMeaning() throws {
        let encoded = try PropertyListEncoder().encode(BottleSettings())
        var propertyList = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: encoded, format: nil) as? [String: Any]
        )
        propertyList.removeValue(forKey: "graphicsConfig")
        let legacyData = try PropertyListSerialization.data(
            fromPropertyList: propertyList, format: .xml, options: 0
        )

        let decoded = try PropertyListDecoder().decode(BottleSettings.self, from: legacyData)
        XCTAssertEqual(decoded.graphicsBackend, .legacy)
        XCTAssertNil(decoded.d3dMetalInstallation)
    }

    func testExplicitGraphicsSelectionRoundTripsWithoutChangingLegacyDXVKFlag() throws {
        var settings = BottleSettings()
        settings.dxvk = true
        settings.graphicsBackend = .wineD3D
        let data = try PropertyListEncoder().encode(settings)
        let decoded = try PropertyListDecoder().decode(BottleSettings.self, from: data)

        XCTAssertEqual(decoded.graphicsBackend, .wineD3D)
        XCTAssertTrue(decoded.dxvk)
        XCTAssertFalse(decoded.usesDXVK)
    }

    func testD3DMetalDetectionAndEnvironmentUseSelectedDirectoryInPlace() throws {
        let root = try makeD3DMetalInstallation(version: "4.0b1")
        defer { try? FileManager.default.removeItem(at: root) }

        let installation = try D3DMetalInstallation.detect(at: root)
        XCTAssertEqual(installation.version, "4.0b1")

        var environment = ["WINEDLLPATH": "/runtime/wine"]
        installation.environmentVariables(wineEnv: &environment)
        XCTAssertEqual(environment["CX_APPLEGPTK_LIBD3DSHARED_PATH"], installation.sharedLibraryURL.path)
        XCTAssertEqual(environment["D3DMETAL_FRAMEWORK_PATH"], installation.frameworkURL.path)
        XCTAssertEqual(environment["WINEDLLPATH"], "\(installation.wineLibraryURL.path):/runtime/wine")
    }

    func testD3DMetalDetectionRejects32BitDLL() throws {
        let root = try makeD3DMetalInstallation(version: "4.0b1")
        defer { try? FileManager.default.removeItem(at: root) }
        try makePE(at: root.appending(path: "redist/lib/wine/x86_64-windows/d3d11.dll"), magic: 0x10b)

        XCTAssertThrowsError(try D3DMetalInstallation.detect(at: root))
    }

    func testBackendSwitchRestoresRuntimeDLLs() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let installationRoot = try makeD3DMetalInstallation(version: "4.0b1")
        let originalRoot = WhiskyWineInstaller.testingApplicationFolder
        WhiskyWineInstaller.testingApplicationFolder = root
        defer {
            WhiskyWineInstaller.testingApplicationFolder = originalRoot
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: installationRoot)
        }

        let runtimeID = "cx-26.3-wine-11"
        let library = WhiskyWineInstaller.libraryFolder(for: runtimeID)
        try makeRuntime(at: library)
        let bottleURL = root.appending(path: "Bottle")
        let system32 = bottleURL.appending(path: "drive_c/windows/system32")
        let syswow64 = bottleURL.appending(path: "drive_c/windows/syswow64")
        try FileManager.default.createDirectory(at: system32, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: syswow64, withIntermediateDirectories: true)
        for name in ["d3d10.dll", "d3d11.dll", "d3d12.dll", "dxgi.dll"] {
            try Data("prefix".utf8).write(to: system32.appending(path: name))
            try Data("prefix".utf8).write(to: syswow64.appending(path: name))
        }

        let bottle = Bottle(bottleUrl: bottleURL)
        bottle.settings.runtimeID = runtimeID
        bottle.settings.d3dMetalInstallation = try D3DMetalInstallation.detect(at: installationRoot)
        bottle.settings.graphicsBackend = .d3dMetal
        try Wine.prepareGraphicsBackend(for: bottle)
        XCTAssertEqual(
            try Data(contentsOf: system32.appending(path: "d3d11.dll")),
            try Data(contentsOf: installationRoot.appending(path: "redist/lib/wine/x86_64-windows/d3d11.dll"))
        )
        XCTAssertEqual(try String(contentsOf: syswow64.appending(path: "d3d11.dll")), "dxvk")

        bottle.settings.graphicsBackend = .wineD3D
        try Wine.prepareGraphicsBackend(for: bottle)
        XCTAssertEqual(try String(contentsOf: system32.appending(path: "d3d11.dll")), "wine-x64")
        XCTAssertEqual(try String(contentsOf: syswow64.appending(path: "d3d11.dll")), "wine-x32")
    }

    private func makeD3DMetalInstallation(version: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let windows = root.appending(path: "redist/lib/wine/x86_64-windows")
        let framework = root.appending(
            path: "redist/lib/external/D3DMetal.framework/Versions/A/Resources"
        )
        try FileManager.default.createDirectory(at: windows, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: framework, withIntermediateDirectories: true)
        for name in ["d3d10.dll", "d3d11.dll", "d3d12.dll", "dxgi.dll"] {
            try makePE(at: windows.appending(path: name), magic: 0x20b)
        }
        try Data().write(to: root.appending(path: "redist/lib/external/libd3dshared.dylib"))
        try Data().write(to: framework.deletingLastPathComponent().appending(path: "D3DMetal"))
        try PropertyListSerialization.data(
            fromPropertyList: ["CFBundleShortVersionString": version], format: .xml, options: 0
        ).write(to: framework.appending(path: "Info.plist"))
        return root
    }

    private func makePE(at url: URL, magic: UInt16) throws {
        var data = Data(repeating: 0, count: 0x9a)
        data.replaceSubrange(0x3c..<0x40, with: withUnsafeBytes(of: UInt32(0x80).littleEndian, Array.init))
        data.replaceSubrange(0x80..<0x84, with: [0x50, 0x45, 0, 0])
        data.replaceSubrange(0x94..<0x96, with: withUnsafeBytes(of: UInt16(2).littleEndian, Array.init))
        data.replaceSubrange(0x98..<0x9a, with: withUnsafeBytes(of: magic.littleEndian, Array.init))
        try data.write(to: url)
    }

    private func makeRuntime(at library: URL) throws {
        let wine = library.appending(path: "Wine")
        try FileManager.default.createDirectory(
            at: wine.appending(path: "bin"), withIntermediateDirectories: true
        )
        try Data().write(to: wine.appending(path: "bin/wine64"))
        try FileManager.default.createDirectory(
            at: wine.appending(path: "lib/wine/x86_64-unix"), withIntermediateDirectories: true
        )
        try Data().write(to: wine.appending(path: "lib/wine/x86_64-unix/ntdll.so"))
        try PropertyListEncoder().encode(WhiskyWineVersion()).write(
            to: library.appending(path: "WhiskyWineVersion.plist")
        )
        try PropertyListSerialization.data(
            fromPropertyList: ["wineDistribution": "crossover"], format: .xml, options: 0
        ).write(to: library.appending(path: "WhiskyWineProvenance.plist"))

        for (directory, marker) in [
            ("Wine/lib/wine/x86_64-windows", "wine-x64"),
            ("Wine/lib/wine/i386-windows", "wine-x32")
        ] {
            let destination = library.appending(path: directory)
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            for name in ["d3d10.dll", "d3d11.dll", "d3d12.dll", "dxgi.dll"] {
                try Data(marker.utf8).write(to: destination.appending(path: name))
            }
        }
        for (directory, marker) in [("DXVK/x64", "dxvk-x64"), ("DXVK/x32", "dxvk")] {
            let destination = library.appending(path: directory)
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            for name in ["d3d11.dll", "dxgi.dll"] {
                try Data(marker.utf8).write(to: destination.appending(path: name))
            }
        }
    }
}
