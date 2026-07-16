//
//  Tar.swift
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

public class Tar {
    static let tarBinary: URL = URL(fileURLWithPath: "/usr/bin/tar")

    public static func tar(folder: URL, toURL: URL) throws {
        let process = Process()
        let pipe = Pipe()

        process.executableURL = tarBinary
        process.arguments = ["-zcf", "\(toURL.path)", "\(folder.path)"]
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()

        if let output = try pipe.fileHandleForReading.readToEnd() {
            let outputString = String(data: output, encoding: .utf8) ?? String()
            process.waitUntilExit()
            let status = process.terminationStatus
            if status != 0 {
                throw outputString
            }
        }
    }

    public static func untar(tarBall: URL, toURL: URL) throws {
        try validateArchivePaths(tarBall: tarBall)

        let process = Process()
        let pipe = Pipe()

        process.executableURL = tarBinary
        process.arguments = ["-xzf", "\(tarBall.path)", "-C", "\(toURL.path)"]
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()

        if let output = try pipe.fileHandleForReading.readToEnd() {
            let outputString = String(data: output, encoding: .utf8) ?? String()
            process.waitUntilExit()
            let status = process.terminationStatus
            if status != 0 {
                throw outputString
            }
        }
    }

    static func isSafeArchivePath(_ path: String) -> Bool {
        !path.isEmpty && !path.hasPrefix("/") &&
            !path.split(separator: "/").contains { $0 == "." || $0 == ".." }
    }

    private static func validateArchivePaths(tarBall: URL) throws {
        let process = Process()
        let pipe = Pipe()

        process.executableURL = tarBinary
        process.arguments = ["-tzf", tarBall.path]
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()

        guard let output = try pipe.fileHandleForReading.readToEnd() else { return }
        process.waitUntilExit()
        let entries = (String(data: output, encoding: .utf8) ?? String())
            .split(separator: "\n")
            .map(String.init)
        guard process.terminationStatus == 0, entries.allSatisfy({ isSafeArchivePath($0) }) else {
            throw "Archive contains unsafe paths."
        }
    }
}

extension String: @retroactive Error {}
