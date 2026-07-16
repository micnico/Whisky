//
//  Wine+RuntimeMigration.swift
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
    /// Copy a Bottle before moving it to a new runtime, then boot the new runtime once.
    /// The backup remains beside the Bottle after a successful migration for manual rollback.
    @discardableResult
    static func migrateBottle(_ bottle: Bottle, to runtimeID: String) async throws -> URL {
        guard WhiskyWineInstaller.isRuntimeInstalled(id: runtimeID) else {
            throw WineRuntimeMigrationError.runtimeNotInstalled(runtimeID)
        }
        let previousRuntimeID = bottle.settings.runtimeID
        guard previousRuntimeID != runtimeID else {
            throw WineRuntimeMigrationError.sameRuntime
        }

        let backup = bottle.url.deletingLastPathComponent().appending(
            path: ".\(bottle.url.lastPathComponent).runtime-backup-\(UUID().uuidString)"
        )
        try await stopBottle(bottle)
        try FileManager.default.copyItem(at: bottle.url, to: backup)
        bottle.settings.runtimeID = runtimeID

        do {
            guard try await wineboot(bottle) == 0 else {
                throw WineRuntimeMigrationError.smokeTestFailed
            }
        } catch {
            do {
                _ = try FileManager.default.replaceItemAt(bottle.url, withItemAt: backup)
                bottle.settings.runtimeID = previousRuntimeID
            } catch {
                throw WineRuntimeMigrationError.restoreFailed
            }
            throw WineRuntimeMigrationError.smokeTestFailed
        }
        return backup
    }

    private static func stopBottle(_ bottle: Bottle) async throws {
        guard try await processStatus(try runWineserverProcess(args: ["-k"], bottle: bottle)) == 0 else {
            throw WineRuntimeMigrationError.stopFailed
        }
    }

    private static func wineboot(_ bottle: Bottle) async throws -> Int32 {
        try await processStatus(try runWineProcess(args: ["wineboot", "-u"], fileHandle: nil, bottle: bottle))
    }

    private static func processStatus(_ stream: AsyncStream<ProcessOutput>) async throws -> Int32 {
        for await output in stream {
            if case .terminated(let process) = output {
                return process.terminationStatus
            }
        }
        throw WineRuntimeMigrationError.commandDidNotTerminate
    }
}

public enum WineRuntimeMigrationError: Error {
    case runtimeNotInstalled(String)
    case sameRuntime
    case stopFailed
    case smokeTestFailed
    case restoreFailed
    case commandDidNotTerminate
}
