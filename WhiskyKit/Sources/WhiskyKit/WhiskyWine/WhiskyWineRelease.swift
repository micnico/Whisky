//
//  WhiskyWineRelease.swift
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
//

import Foundation
import CryptoKit
import SemanticVersion

public struct WhiskyWineRelease: Codable, Equatable, Sendable {
    public let id: String
    public let version: SemanticVersion
    public let archiveURL: URL
    public let sha256: String

    public init(id: String, version: SemanticVersion, archiveURL: URL, sha256: String) {
        self.id = id
        self.version = version
        self.archiveURL = archiveURL
        self.sha256 = sha256
    }
}

public enum WhiskyWineReleaseError: LocalizedError {
    case invalidRuntimeID(String)
    case invalidChecksum
    case checksumMismatch
    case invalidArchive
    case runtimeNotInstalled(String)

    public var errorDescription: String? {
        switch self {
        case .invalidRuntimeID(let id): return "Invalid runtime identifier: \(id)"
        case .invalidChecksum: return "Runtime checksum must be a SHA-256 value."
        case .checksumMismatch: return "Runtime archive checksum does not match the release manifest."
        case .invalidArchive: return "Runtime archive does not contain a Libraries directory."
        case .runtimeNotInstalled(let id): return "Runtime \(id) is not installed."
        }
    }
}

extension WhiskyWineInstaller {
    public static let acceptedWine11RuntimeID = "wine-11.0-dxvk-moltenvk-x86_64"
    public static let acceptedWine11RuntimeSHA256 =
        "ccec9f0717135b8405674b0a8e5408d3f9b2b8283f48d0c0c07319045e3d9c9e"

    /// Install the exact Wine 11 engineering candidate recorded in the runtime acceptance evidence.
    /// This local import path does not publish the archive or replace an existing Bottle's runtime binding.
    public static func installAcceptedWine11Runtime(from archive: URL) throws {
        let release = WhiskyWineRelease(
            id: acceptedWine11RuntimeID,
            version: SemanticVersion(11, 0, 0),
            archiveURL: archive,
            sha256: acceptedWine11RuntimeSHA256
        )
        try install(release: release, from: archive)
    }

    static func isValidRuntimeID(_ id: String) -> Bool {
        !id.isEmpty && id.allSatisfy { $0.isLetter || $0.isNumber || ".-_".contains($0) }
    }

    public static func verifyArchive(at archive: URL, sha256: String) throws {
        let expected = sha256.lowercased()
        guard expected.count == 64, expected.allSatisfy({ $0.isHexDigit }) else {
            throw WhiskyWineReleaseError.invalidChecksum
        }

        guard try fileSHA256(of: archive) == expected else { throw WhiskyWineReleaseError.checksumMismatch }
    }

    static func fileSHA256(of file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }

        var digest = SHA256()
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
            digest.update(data: data)
        }

        return digest.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
