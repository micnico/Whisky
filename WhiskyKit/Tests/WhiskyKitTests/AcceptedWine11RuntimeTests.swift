//
//  AcceptedWine11RuntimeTests.swift
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

final class AcceptedWine11RuntimeTests: XCTestCase {
    func testAcceptedCandidateMetadata() {
        XCTAssertEqual(
            WhiskyWineInstaller.acceptedWine11RuntimeID,
            "wine-11.0-dxvk-moltenvk-x86_64"
        )
        XCTAssertEqual(
            WhiskyWineInstaller.acceptedWine11RuntimeSHA256,
            "ccec9f0717135b8405674b0a8e5408d3f9b2b8283f48d0c0c07319045e3d9c9e"
        )
    }

    func testAcceptedCandidateRejectsDifferentArchive() throws {
        let root = try useTemporaryRuntimeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let archive = root.appending(path: "runtime.tar.gz")
        try Data("not-the-accepted-runtime".utf8).write(to: archive)

        XCTAssertThrowsError(try WhiskyWineInstaller.installAcceptedWine11Runtime(from: archive)) { error in
            guard case WhiskyWineReleaseError.checksumMismatch = error else {
                return XCTFail("Expected checksumMismatch, got \(error)")
            }
        }
        XCTAssertFalse(WhiskyWineInstaller.isRuntimeInstalled(id: WhiskyWineInstaller.acceptedWine11RuntimeID))
    }

    func testChangingDefaultRuntimeDoesNotRewriteExistingBottle() throws {
        let root = try useTemporaryRuntimeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try createRuntime(at: root, id: "wine-11.0")
        let bottleURL = root.appending(path: "Bottles/existing")
        try FileManager.default.createDirectory(at: bottleURL, withIntermediateDirectories: true)
        let bottle = Bottle(bottleUrl: bottleURL)
        XCTAssertEqual(bottle.settings.runtimeID, "legacy")

        try WhiskyWineInstaller.activateRuntime(id: "wine-11.0")

        XCTAssertEqual(WhiskyWineInstaller.activeRuntimeID(), "wine-11.0")
        XCTAssertEqual(Bottle(bottleUrl: bottleURL).settings.runtimeID, "legacy")
    }

    func testLoadingBottleDoesNotRewriteUnchangedMetadata() throws {
        let bottleURL = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: bottleURL) }
        try FileManager.default.createDirectory(at: bottleURL, withIntermediateDirectories: true)
        let metadata = bottleURL.appending(path: "Metadata.plist")
        var settings = BottleSettings()
        settings.runtimeID = "wine-11.0-dxvk-moltenvk-x86_64"
        try settings.encode(to: metadata)
        let originalDate = Date(timeIntervalSinceReferenceDate: 1)
        try FileManager.default.setAttributes([.modificationDate: originalDate], ofItemAtPath: metadata.path)

        _ = Bottle(bottleUrl: bottleURL)

        let attributes = try FileManager.default.attributesOfItem(atPath: metadata.path)
        XCTAssertEqual(attributes[.modificationDate] as? Date, originalDate)
        XCTAssertEqual(try BottleSettings.decode(from: metadata).runtimeID, settings.runtimeID)
    }

    func testSettingProgramPinnedTwiceDoesNotDuplicatePin() throws {
        let bottleURL = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: bottleURL) }
        try FileManager.default.createDirectory(at: bottleURL, withIntermediateDirectories: true)
        let bottle = Bottle(bottleUrl: bottleURL)
        let program = Program(url: bottleURL.appending(path: "program.exe"), bottle: bottle)

        program.pinned = true
        program.pinned = true

        XCTAssertEqual(bottle.settings.pins.count, 1)
    }

    private func useTemporaryRuntimeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let originalRoot = WhiskyWineInstaller.testingApplicationFolder
        WhiskyWineInstaller.testingApplicationFolder = root
        addTeardownBlock { WhiskyWineInstaller.testingApplicationFolder = originalRoot }
        try FileManager.default.createDirectory(
            at: root.appending(path: "Libraries"), withIntermediateDirectories: true
        )
        return root
    }

    private func createRuntime(at root: URL, id: String) throws {
        let libraries = root.appending(path: "Runtimes/\(id)/Libraries")
        let wine = libraries.appending(path: "Wine/bin/wine64")
        try FileManager.default.createDirectory(
            at: wine.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Data().write(to: wine)
        try PropertyListEncoder().encode(WhiskyWineVersion()).write(
            to: libraries.appending(path: "WhiskyWineVersion.plist")
        )
    }
}
