//
//  WhiskyWineInstallerTests.swift
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

import Foundation
import CryptoKit
import SemanticVersion
import XCTest
@testable import WhiskyKit

final class WhiskyWineInstallerTests: XCTestCase {
    func testMissingBottleRuntimeUsesActiveRuntime() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let originalRoot = WhiskyWineInstaller.testingApplicationFolder
        WhiskyWineInstaller.testingApplicationFolder = root
        defer {
            WhiskyWineInstaller.testingApplicationFolder = originalRoot
            try? FileManager.default.removeItem(at: root)
        }

        let legacyBin = root.appending(path: "Libraries/Wine/bin")
        try FileManager.default.createDirectory(at: legacyBin, withIntermediateDirectories: true)
        let bottleURL = root.appending(path: "Bottles/test")
        try FileManager.default.createDirectory(at: bottleURL, withIntermediateDirectories: true)
        let bottle = Bottle(bottleUrl: bottleURL)
        bottle.settings.runtimeID = "missing-runtime"

        XCTAssertEqual(WhiskyWineInstaller.resolvedRuntimeID(bottle.settings.runtimeID), "legacy")
        XCTAssertEqual(Wine.wineBinary(for: bottle), legacyBin.appending(path: "wine64"))
    }

    func testReleaseArchiveURLRequiresHTTPS() {
        XCTAssertTrue(WhiskyWineInstaller.isSecureArchiveURL(URL(string: "https://example.com/wine.tar.gz")!))
        XCTAssertFalse(WhiskyWineInstaller.isSecureArchiveURL(URL(string: "http://example.com/wine.tar.gz")!))
        XCTAssertFalse(WhiskyWineInstaller.isSecureArchiveURL(URL(fileURLWithPath: "/tmp/wine.tar.gz")))
    }

    func testVersionedInstallRejectsIncompleteRuntimeArchive() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let originalRoot = WhiskyWineInstaller.testingApplicationFolder
        WhiskyWineInstaller.testingApplicationFolder = root
        defer {
            WhiskyWineInstaller.testingApplicationFolder = originalRoot
            try? FileManager.default.removeItem(at: root)
        }

        let source = root.appending(path: "source")
        let archive = root.appending(path: "incomplete.tar.gz")
        try FileManager.default.createDirectory(
            at: source.appending(path: "Libraries"), withIntermediateDirectories: true
        )
        try archiveLibraries(at: source, to: archive)
        let checksum = SHA256.hash(data: try Data(contentsOf: archive))
            .map { String(format: "%02x", $0) }
            .joined()
        let release = WhiskyWineRelease(
            id: "wine-11.0", version: SemanticVersion(11, 0, 0),
            archiveURL: URL(string: "https://example.com/wine-11.0.tar.gz")!, sha256: checksum
        )

        XCTAssertThrowsError(try WhiskyWineInstaller.install(release: release, from: archive))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appending(path: "Runtimes/wine-11.0").path))
    }

    func testVersionedInstallRejectsExistingIncompleteRuntime() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let originalRoot = WhiskyWineInstaller.testingApplicationFolder
        WhiskyWineInstaller.testingApplicationFolder = root
        defer {
            WhiskyWineInstaller.testingApplicationFolder = originalRoot
            try? FileManager.default.removeItem(at: root)
        }

        let source = root.appending(path: "source")
        let libraries = source.appending(path: "Libraries")
        let wine = libraries.appending(path: "Wine/bin/wine64")
        let archive = root.appending(path: "wine-11.0.tar.gz")
        try FileManager.default.createDirectory(at: wine.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: wine)
        try PropertyListEncoder().encode(WhiskyWineVersion()).write(
            to: libraries.appending(path: "WhiskyWineVersion").appendingPathExtension("plist")
        )
        try archiveLibraries(at: source, to: archive)
        try FileManager.default.createDirectory(
            at: root.appending(path: "Runtimes/wine-11.0/Libraries"), withIntermediateDirectories: true
        )

        let checksum = SHA256.hash(data: try Data(contentsOf: archive)).map { String(format: "%02x", $0) }.joined()
        let release = WhiskyWineRelease(
            id: "wine-11.0", version: SemanticVersion(11, 0, 0),
            archiveURL: URL(string: "https://example.com/wine-11.0.tar.gz")!, sha256: checksum
        )

        XCTAssertThrowsError(try WhiskyWineInstaller.install(release: release, from: archive))
        XCTAssertEqual(WhiskyWineInstaller.activeRuntimeID(), "legacy")
    }

    func testVersionedInstallRejectsRuntimeWithExternalSymlink() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let originalRoot = WhiskyWineInstaller.testingApplicationFolder
        WhiskyWineInstaller.testingApplicationFolder = root
        defer {
            WhiskyWineInstaller.testingApplicationFolder = originalRoot
            try? FileManager.default.removeItem(at: root)
        }

        let source = root.appending(path: "source")
        let libraries = source.appending(path: "Libraries")
        let wine = libraries.appending(path: "Wine/bin/wine64")
        let archive = root.appending(path: "wine-11.0.tar.gz")
        let outsideWine = root.appending(path: "outside-wine")
        try FileManager.default.createDirectory(at: wine.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: outsideWine)
        try FileManager.default.createSymbolicLink(at: wine, withDestinationURL: outsideWine)
        try PropertyListEncoder().encode(WhiskyWineVersion()).write(
            to: libraries.appending(path: "WhiskyWineVersion").appendingPathExtension("plist")
        )
        try archiveLibraries(at: source, to: archive)

        let checksum = SHA256.hash(data: try Data(contentsOf: archive)).map { String(format: "%02x", $0) }.joined()
        let release = WhiskyWineRelease(
            id: "wine-11.0", version: SemanticVersion(11, 0, 0),
            archiveURL: URL(string: "https://example.com/wine-11.0.tar.gz")!, sha256: checksum
        )

        XCTAssertThrowsError(try WhiskyWineInstaller.install(release: release, from: archive))
        XCTAssertFalse(WhiskyWineInstaller.isRuntimeInstalled(id: release.id))
    }

    private func archiveLibraries(at source: URL, to archive: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["-C", source.path, "-zcf", archive.path, "Libraries"]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
    }

}
