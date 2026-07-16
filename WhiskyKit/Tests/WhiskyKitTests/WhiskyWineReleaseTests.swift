//
//  WhiskyWineReleaseTests.swift
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
import CryptoKit
import SemanticVersion
import XCTest
@testable import WhiskyKit

final class WhiskyWineReleaseTests: XCTestCase {
    func testArchiveChecksum() throws {
        let archive = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: archive) }
        try Data("abc".utf8).write(to: archive)

        try WhiskyWineInstaller.verifyArchive(
            at: archive,
            sha256: "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
        XCTAssertThrowsError(
            try WhiskyWineInstaller.verifyArchive(
                at: archive,
                sha256: String(repeating: "0", count: 64)
            )
        )
    }

    func testReleaseManifestDecodes() throws {
        let release = WhiskyWineRelease(
            id: "wine-11.0",
            version: SemanticVersion(11, 0, 0),
            archiveURL: try XCTUnwrap(URL(string: "https://example.com/wine-11.0.tar.gz")),
            sha256: String(repeating: "a", count: 64)
        )
        let decoded = try PropertyListDecoder().decode(
            WhiskyWineRelease.self,
            from: PropertyListEncoder().encode(release)
        )
        XCTAssertEqual(decoded, release)
    }

    func testPublishedManifestDecodes() throws {
        let manifest: [String: Any] = [
            "id": "wine-11.0-arm64",
            "version": ["major": 11, "minor": 0, "patch": 0, "preRelease": "", "build": ""],
            "archiveURL": "https://example.com/wine-11.0-arm64.tar.gz",
            "sha256": String(repeating: "a", count: 64)
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: manifest, format: .xml, options: 0)
        let decoded = try PropertyListDecoder().decode(WhiskyWineVersion.self, from: data)

        XCTAssertEqual(decoded.id, "wine-11.0-arm64")
        XCTAssertEqual(decoded.version, SemanticVersion(11, 0, 0))

        var legacyManifest = WhiskyWineVersion()
        legacyManifest.archiveURL = URL(string: "https://example.com/legacy.tar.gz")
        let legacyData = try PropertyListEncoder().encode(legacyManifest)
        XCTAssertEqual(
            try PropertyListDecoder().decode(WhiskyWineVersion.self, from: legacyData).archiveURL,
            legacyManifest.archiveURL
        )
    }

    func testVersionedInstallActivatesAndRollsBack() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let originalRoot = WhiskyWineInstaller.testingApplicationFolder
        WhiskyWineInstaller.testingApplicationFolder = root
        defer {
            WhiskyWineInstaller.testingApplicationFolder = originalRoot
            try? FileManager.default.removeItem(at: root)
        }

        let legacyLibraries = root.appending(path: "Libraries")
        let source = root.appending(path: "source")
        let archive = root.appending(path: "wine-11.0.tar.gz")
        try FileManager.default.createDirectory(at: legacyLibraries, withIntermediateDirectories: true)
        let libraries = source.appending(path: "Libraries")
        let wine = libraries.appending(path: "Wine/bin/wine64")
        try FileManager.default.createDirectory(at: wine.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: wine)
        try PropertyListEncoder().encode(WhiskyWineVersion()).write(
            to: libraries.appending(path: "WhiskyWineVersion").appendingPathExtension("plist")
        )
        try archiveLibraries(at: source, to: archive)

        let checksum = SHA256.hash(data: try Data(contentsOf: archive))
            .map { String(format: "%02x", $0) }
            .joined()
        let release = WhiskyWineRelease(
            id: "wine-11.0",
            version: SemanticVersion(11, 0, 0),
            archiveURL: try XCTUnwrap(URL(string: "https://example.com/wine-11.0.tar.gz")),
            sha256: checksum
        )

        try WhiskyWineInstaller.install(release: release, from: archive)
        XCTAssertEqual(WhiskyWineInstaller.activeRuntimeID(), "wine-11.0")
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: root.appending(path: "Runtimes/wine-11.0/Libraries").path
            )
        )

        XCTAssertEqual(try WhiskyWineInstaller.rollbackRuntime(), "legacy")
        XCTAssertEqual(WhiskyWineInstaller.activeRuntimeID(), "legacy")
    }

    func testLegacyBottleMetadataDefaultsToLegacyRuntime() throws {
        let encoded = try PropertyListEncoder().encode(BottleWineConfig())
        var propertyList = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: encoded, format: nil) as? [String: Any]
        )
        propertyList.removeValue(forKey: "runtimeID")
        let legacyMetadata = try PropertyListSerialization.data(
            fromPropertyList: propertyList,
            format: .xml,
            options: 0
        )

        let decoded = try PropertyListDecoder().decode(BottleWineConfig.self, from: legacyMetadata)
        XCTAssertEqual(decoded.runtimeID, "legacy")
    }

    func testMissingBottleMetadataCreatesLegacySettings() throws {
        let bottleURL = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: bottleURL) }
        try FileManager.default.createDirectory(at: bottleURL, withIntermediateDirectories: true)

        let bottle = Bottle(bottleUrl: bottleURL)
        let metadata = bottleURL.appending(path: "Metadata").appendingPathExtension("plist")

        XCTAssertEqual(bottle.settings.runtimeID, "legacy")
        XCTAssertTrue(FileManager.default.fileExists(atPath: metadata.path))
        XCTAssertEqual(try BottleSettings.decode(from: metadata).runtimeID, "legacy")
    }

    func testBottleRuntimeSelectionRoundTrips() throws {
        var settings = BottleSettings()
        XCTAssertEqual(settings.runtimeID, "legacy")
        settings.runtimeID = "wine-11.0-arm64"

        let metadata = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: metadata) }
        try settings.encode(to: metadata)

        XCTAssertEqual(try BottleSettings.decode(from: metadata).runtimeID, "wine-11.0-arm64")
    }

    func testBottleUsesBoundRuntime() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let originalRoot = WhiskyWineInstaller.testingApplicationFolder
        WhiskyWineInstaller.testingApplicationFolder = root
        defer {
            WhiskyWineInstaller.testingApplicationFolder = originalRoot
            try? FileManager.default.removeItem(at: root)
        }

        let runtimeID = "wine-11.0-arm64"
        let runtimeBin = try createInstalledRuntime(at: root, id: runtimeID).appending(path: "Wine/bin")
        let bottleURL = root.appending(path: "Bottles/test")
        try FileManager.default.createDirectory(at: bottleURL, withIntermediateDirectories: true)
        let bottle = Bottle(bottleUrl: bottleURL)
        bottle.settings.runtimeID = runtimeID

        XCTAssertEqual(Wine.wineBinary(for: bottle), runtimeBin.appending(path: "wine64"))
    }

    func testBottleRuntimeMigrationPersistsAndCanRollback() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let originalRoot = WhiskyWineInstaller.testingApplicationFolder
        WhiskyWineInstaller.testingApplicationFolder = root
        defer {
            WhiskyWineInstaller.testingApplicationFolder = originalRoot
            try? FileManager.default.removeItem(at: root)
        }

        let runtimeID = "wine-11.0-dxvk"
        try FileManager.default.createDirectory(
            at: root.appending(path: "Libraries"), withIntermediateDirectories: true
        )
        _ = try createInstalledRuntime(at: root, id: runtimeID)
        let bottleURL = root.appending(path: "Bottles/test")
        try FileManager.default.createDirectory(at: bottleURL, withIntermediateDirectories: true)

        let bottle = Bottle(bottleUrl: bottleURL)
        bottle.settings.runtimeID = runtimeID
        XCTAssertEqual(Bottle(bottleUrl: bottleURL).settings.runtimeID, runtimeID)

        bottle.settings.runtimeID = "legacy"
        XCTAssertEqual(Bottle(bottleUrl: bottleURL).settings.runtimeID, "legacy")
        XCTAssertEqual(WhiskyWineInstaller.installedRuntimeIDs(), ["legacy", runtimeID])
    }

    func testVulkanRuntimeConfiguresBundledVulkanWithoutDXVK() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let originalRoot = WhiskyWineInstaller.testingApplicationFolder
        WhiskyWineInstaller.testingApplicationFolder = root
        defer {
            WhiskyWineInstaller.testingApplicationFolder = originalRoot
            try? FileManager.default.removeItem(at: root)
        }

        let runtimeID = "wine-11.0-dxvk"
        let vulkanFolder = try createInstalledRuntime(at: root, id: runtimeID).appending(path: "Vulkan")
        try FileManager.default.createDirectory(at: vulkanFolder, withIntermediateDirectories: true)
        FileManager.default.createFile(
            atPath: vulkanFolder.appending(path: "MoltenVK_icd.json").path,
            contents: Data()
        )

        let bottleURL = root.appending(path: "Bottles/test")
        try FileManager.default.createDirectory(at: bottleURL, withIntermediateDirectories: true)
        let bottle = Bottle(bottleUrl: bottleURL)
        bottle.settings.runtimeID = runtimeID

        let command = Wine.generateRunCommand(
            at: root.appending(path: "game.exe"), bottle: bottle, args: "", environment: [:]
        )
        XCTAssertTrue(command.contains(
            "VK_ICD_FILENAMES=\"\(vulkanFolder.appending(path: "MoltenVK_icd.json").path)\""
        ))
        XCTAssertTrue(command.contains("DYLD_FALLBACK_LIBRARY_PATH=\"\(vulkanFolder.path)\""))
    }

    func testDXVKSupportRequiresBothArchitectures() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let originalRoot = WhiskyWineInstaller.testingApplicationFolder
        WhiskyWineInstaller.testingApplicationFolder = root
        defer {
            WhiskyWineInstaller.testingApplicationFolder = originalRoot
            try? FileManager.default.removeItem(at: root)
        }

        let runtimeID = "wine-11.0-dxvk"
        let library = try createInstalledRuntime(at: root, id: runtimeID).appending(path: "DXVK")
        try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
        XCTAssertFalse(WhiskyWineInstaller.supportsDXVK(id: runtimeID))

        for path in ["x64/d3d11.dll", "x64/dxgi.dll", "x32/d3d11.dll", "x32/dxgi.dll"] {
            let file = library.appending(path: path)
            try FileManager.default.createDirectory(
                at: file.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            FileManager.default.createFile(atPath: file.path, contents: Data())
        }
        XCTAssertTrue(WhiskyWineInstaller.supportsDXVK(id: runtimeID))
    }

    func testDXVKAsyncIsDisabledWithDXVK() {
        var settings = BottleSettings()
        var environment: [String: String] = [:]
        settings.environmentVariables(wineEnv: &environment)
        XCTAssertNil(environment["DXVK_ASYNC"])

        settings.dxvk = true
        settings.environmentVariables(wineEnv: &environment)
        XCTAssertEqual(environment["DXVK_ASYNC"], "1")
    }

    func testReplaceDLLsSkipsNonDLLFiles() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }

        let source = root.appending(path: "source")
        let destination = root.appending(path: "destination")
        try FileManager.default.createDirectory(
            at: source.appending(path: "0-non-dll"), withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let sourceDLL = source.appending(path: "z-dxgi.dll")
        let destinationDLL = destination.appending(path: "z-dxgi.dll")
        try Data("new".utf8).write(to: sourceDLL)
        try Data("old".utf8).write(to: destinationDLL)

        try FileManager.default.replaceDLLs(in: destination, withContentsIn: source)
        XCTAssertEqual(try Data(contentsOf: destinationDLL), Data("new".utf8))
    }

    private func archiveLibraries(at source: URL, to archive: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["-C", source.path, "-zcf", archive.path, "Libraries"]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
    }

    private func createInstalledRuntime(at root: URL, id: String) throws -> URL {
        let libraries = root.appending(path: "Runtimes/\(id)/Libraries")
        let wine = libraries.appending(path: "Wine/bin/wine64")
        try FileManager.default.createDirectory(at: wine.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: wine)
        try PropertyListEncoder().encode(WhiskyWineVersion()).write(
            to: libraries.appending(path: "WhiskyWineVersion").appendingPathExtension("plist")
        )
        return libraries
    }
}
