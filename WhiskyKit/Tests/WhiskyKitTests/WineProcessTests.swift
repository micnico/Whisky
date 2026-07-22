//
//  WineProcessTests.swift
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

final class WineProcessTests: XCTestCase {
    func testRunWineThrowsForNonzeroExitStatus() async throws {
        let context = try makeBottle()
        defer { try? FileManager.default.removeItem(at: context.root) }
        try writeCommand("#!/bin/sh\nexit 23\n", to: context.wine)

        do {
            _ = try await Wine.runWine(["test.exe"], bottle: context.bottle)
            XCTFail("A failed Wine command must throw")
        } catch let error as WineProcessError {
            XCTAssertEqual(error, .terminated(23))
        }
    }

    func testBottleInitializationUsesNoninteractiveWineCommands() async throws {
        let context = try makeBottle()
        defer { try? FileManager.default.removeItem(at: context.root) }
        try writeCommand(
            """
            #!/bin/sh
            printf '%s %s %s|%s\n' "$1" "$2" "$3" "$WINEDLLOVERRIDES" >> "$WINEPREFIX/commands"
            exit 0
            """,
            to: context.wine
        )

        try await Wine.initializeBottle(context.bottle)
        try await Wine.changeWinVersion(bottle: context.bottle, win: .win10)

        let commands = try String(contentsOf: context.bottle.url.appending(path: "commands"), encoding: .utf8)
        XCTAssertEqual(
            commands,
            "wineboot.exe -u |mscoree,mshtml=\nwinecfg.exe -v win10|mscoree,mshtml=\n"
        )
    }

    private struct TestBottle {
        let root: URL
        let bottle: Bottle
        let wine: URL
    }

    private func makeBottle() throws -> TestBottle {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let originalRoot = WhiskyWineInstaller.testingApplicationFolder
        WhiskyWineInstaller.testingApplicationFolder = root
        addTeardownBlock { WhiskyWineInstaller.testingApplicationFolder = originalRoot }

        let wine = root.appending(path: "Libraries/Wine/bin/wine64")
        let version = root.appending(path: "Libraries/WhiskyWineVersion.plist")
        let bottleURL = root.appending(path: "Bottles/test")
        try FileManager.default.createDirectory(at: wine.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: bottleURL, withIntermediateDirectories: true)
        try PropertyListEncoder().encode(WhiskyWineVersion()).write(to: version)
        return TestBottle(root: root, bottle: Bottle(bottleUrl: bottleURL), wine: wine)
    }

    private func writeCommand(_ command: String, to url: URL) throws {
        try Data(command.utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }
}
