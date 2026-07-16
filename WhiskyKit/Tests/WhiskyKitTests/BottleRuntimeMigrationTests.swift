//
//  BottleRuntimeMigrationTests.swift
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

final class BottleRuntimeMigrationTests: XCTestCase {
    func testMigrationBacksUpAndBootsTargetRuntime() async throws {
        let runtimeID = "wine-11.0-arm64"
        let (root, bottle) = try makeBottle(withTargetStatus: 0)
        defer { try? FileManager.default.removeItem(at: root) }

        let backup = try await Wine.migrateBottle(bottle, to: runtimeID)

        XCTAssertEqual(bottle.settings.runtimeID, runtimeID)
        XCTAssertTrue(FileManager.default.fileExists(atPath: backup.appending(path: "Metadata.plist").path))
    }

    func testFailedMigrationRestoresBackup() async throws {
        let runtimeID = "wine-11.0-arm64"
        let (root, bottle) = try makeBottle(withTargetStatus: 1)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("legacy".utf8).write(to: bottle.url.appending(path: "marker"))

        do {
            _ = try await Wine.migrateBottle(bottle, to: runtimeID)
            XCTFail("Migration should fail when wineboot fails")
        } catch WineRuntimeMigrationError.smokeTestFailed {
            XCTAssertEqual(bottle.settings.runtimeID, "legacy")
            XCTAssertEqual(try Data(contentsOf: bottle.url.appending(path: "marker")), Data("legacy".utf8))
        }
    }

    private func makeBottle(withTargetStatus status: Int) throws -> (URL, Bottle) {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let originalRoot = WhiskyWineInstaller.testingApplicationFolder
        WhiskyWineInstaller.testingApplicationFolder = root
        addTeardownBlock { WhiskyWineInstaller.testingApplicationFolder = originalRoot }
        let runtimeID = "wine-11.0-arm64"
        let targetBin = try createRuntime(at: root, id: runtimeID).appending(path: "Wine/bin")
        try writeCommand(to: targetBin.appending(path: "wine64"), status: status)
        try writeCommand(to: root.appending(path: "Libraries/Wine/bin/wineserver"), status: 0)
        let bottleURL = root.appending(path: "Bottles/test")
        try FileManager.default.createDirectory(at: bottleURL, withIntermediateDirectories: true)
        return (root, Bottle(bottleUrl: bottleURL))
    }

    private func createRuntime(at root: URL, id: String) throws -> URL {
        let libraries = root.appending(path: "Runtimes/\(id)/Libraries")
        let wine = libraries.appending(path: "Wine/bin/wine64")
        try FileManager.default.createDirectory(at: wine.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: wine)
        try PropertyListEncoder().encode(WhiskyWineVersion()).write(
            to: libraries.appending(path: "WhiskyWineVersion").appendingPathExtension("plist")
        )
        return libraries
    }

    private func writeCommand(to url: URL, status: Int) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("#!/bin/sh\nexit \(status)\n".utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }
}
