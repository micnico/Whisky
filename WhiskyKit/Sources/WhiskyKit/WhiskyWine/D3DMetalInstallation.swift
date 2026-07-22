//
//  D3DMetalInstallation.swift
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

import CryptoKit
import Foundation

public struct D3DMetalInstallation: Codable, Equatable, Sendable {
    public let rootURL: URL
    public let version: String
    public let contentSHA256: String?

    public init(rootURL: URL, version: String, contentSHA256: String? = nil) {
        self.rootURL = rootURL
        self.version = version
        self.contentSHA256 = contentSHA256
    }

    public var libraryURL: URL { rootURL.appending(path: "redist/lib") }
    public var wineLibraryURL: URL { libraryURL.appending(path: "wine") }
    public var windowsDLLURL: URL { wineLibraryURL.appending(path: "x86_64-windows") }
    public var sharedLibraryURL: URL { libraryURL.appending(path: "external/libd3dshared.dylib") }
    public var frameworkURL: URL {
        libraryURL.appending(path: "external/D3DMetal.framework/Versions/A/D3DMetal")
    }

    public static func detect(at rootURL: URL) throws -> D3DMetalInstallation {
        let installation = D3DMetalInstallation(rootURL: rootURL.standardizedFileURL, version: "")
        let names = ["d3d10.dll", "d3d11.dll", "d3d12.dll", "dxgi.dll"]
        for name in names {
            let file = installation.windowsDLLURL.appending(path: name)
            guard let portableExecutable = try? PEFile(url: file),
                  portableExecutable.architecture == .x64 else {
                throw D3DMetalInstallationError.invalidFile(file)
            }
        }
        for file in [installation.sharedLibraryURL, installation.frameworkURL] {
            guard FileManager.default.fileExists(atPath: file.path) else {
                throw D3DMetalInstallationError.invalidFile(file)
            }
        }

        let infoURL = installation.libraryURL
            .appending(path: "external/D3DMetal.framework/Versions/A/Resources/Info.plist")
        guard let info = NSDictionary(contentsOf: infoURL),
              let version = info["CFBundleShortVersionString"] as? String,
              !version.isEmpty else {
            throw D3DMetalInstallationError.invalidVersion
        }
        var contents = Data()
        for file in names.map({ installation.windowsDLLURL.appending(path: $0) }) +
            [installation.sharedLibraryURL, installation.frameworkURL] {
            contents.append(Data(file.lastPathComponent.utf8))
            contents.append(0)
            contents.append(try Data(contentsOf: file))
        }
        let digest = SHA256.hash(data: contents).map { String(format: "%02x", $0) }.joined()
        return D3DMetalInstallation(
            rootURL: installation.rootURL, version: version, contentSHA256: digest
        )
    }

    func environmentVariables(wineEnv: inout [String: String]) {
        wineEnv["CX_APPLEGPTK_LIBD3DSHARED_PATH"] = sharedLibraryURL.path
        wineEnv["D3DMETAL_FRAMEWORK_PATH"] = frameworkURL.path
        if let current = wineEnv["WINEDLLPATH"], !current.isEmpty {
            wineEnv["WINEDLLPATH"] = "\(wineLibraryURL.path):\(current)"
        } else {
            wineEnv["WINEDLLPATH"] = wineLibraryURL.path
        }
    }
}

public enum D3DMetalInstallationError: LocalizedError, Equatable {
    case invalidFile(URL)
    case invalidVersion

    public var errorDescription: String? {
        switch self {
        case .invalidFile(let file): return "Invalid or missing D3DMetal file: \(file.path)"
        case .invalidVersion: return "The selected D3DMetal framework has no version."
        }
    }
}

public extension WhiskyWineInstaller {
    /// D3DMetal requires the CrossOver Wine ABI; a matching Wine version alone is insufficient.
    static func supportsD3DMetal(id: String) -> Bool {
        let library = libraryFolder(for: id)
        let provenance = library.appending(path: "WhiskyWineProvenance.plist")
        guard isRuntimeInstalled(id: id),
              let values = NSDictionary(contentsOf: provenance),
              values["wineDistribution"] as? String == "crossover" else {
            return false
        }
        return FileManager.default.fileExists(
            atPath: library.appending(path: "Wine/lib/wine/x86_64-unix/ntdll.so").path
        )
    }
}
