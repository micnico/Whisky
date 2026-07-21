//
//  WhiskyWineInstaller.swift
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
import SemanticVersion

public class WhiskyWineInstaller {
    /// The Whisky application folder
    public static let applicationFolder = FileManager.default.urls(
        for: .applicationSupportDirectory, in: .userDomainMask
        )[0].appending(path: Bundle.whiskyBundleIdentifier)

    nonisolated(unsafe) static var testingApplicationFolder: URL?

    private static var runtimeRoot: URL {
        testingApplicationFolder ?? applicationFolder
    }

    /// The folder of the active runtime's library files.
    public static var libraryFolder: URL {
        libraryFolder(for: activeRuntimeID())
    }

    /// The folder of an installed runtime's library files.
    public static func libraryFolder(for id: String) -> URL {
        id == "legacy"
            ? runtimeRoot.appending(path: "Libraries")
            : runtimeRoot.appending(path: "Runtimes").appending(path: id).appending(path: "Libraries")
    }

    /// URL to the installed `wine` `bin` directory
    public static var binFolder: URL { libraryFolder.appending(path: "Wine").appending(path: "bin") }

    /// URL to an installed runtime's `wine` `bin` directory.
    public static func binFolder(for id: String) -> URL {
        libraryFolder(for: id).appending(path: "Wine").appending(path: "bin")
    }

    public static let legacyArchiveURL = staticURL("https://data.getwhisky.app/Wine/Libraries.tar.gz")
    private static let releaseManifestURL = staticURL("https://data.getwhisky.app/Wine/WhiskyWineVersion.plist")

    private static func staticURL(_ value: String) -> URL {
        guard let url = URL(string: value) else {
            preconditionFailure("Invalid static URL: \(value)")
        }
        return url
    }

    public static func isWhiskyWineInstalled() -> Bool {
        return whiskyWineVersion() != nil
    }

    /// Install the legacy bootstrap archive. New releases should use `install(release:from:)`.
    public static func install(from: URL) throws {
        if !FileManager.default.fileExists(atPath: runtimeRoot.path) {
            try FileManager.default.createDirectory(at: runtimeRoot, withIntermediateDirectories: true)
        }

        let stagingFolder = runtimeRoot.appending(path: ".staging-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: stagingFolder) }
        try FileManager.default.createDirectory(at: stagingFolder, withIntermediateDirectories: true)
        try Tar.untar(tarBall: from, toURL: stagingFolder)

        let stagedLibraries = stagingFolder.appending(path: "Libraries")
        let legacyLibraries = runtimeRoot.appending(path: "Libraries")
        guard FileManager.default.fileExists(atPath: stagedLibraries.path) else {
            throw WhiskyWineReleaseError.invalidArchive
        }

        if FileManager.default.fileExists(atPath: legacyLibraries.path) {
            _ = try FileManager.default.replaceItemAt(
                legacyLibraries,
                withItemAt: stagedLibraries,
                backupItemName: "Libraries.backup",
                options: []
            )
        } else {
            try FileManager.default.moveItem(at: stagedLibraries, to: legacyLibraries)
        }
        try activateRuntime(id: "legacy")
        try FileManager.default.removeItem(at: from)
    }

    /// Install a release into its own directory and make it the active runtime.
    /// The existing legacy runtime remains available as a rollback target.
    public static func install(release: WhiskyWineRelease, from archive: URL) throws {
        guard isValidRuntimeID(release.id) else {
            throw WhiskyWineReleaseError.invalidRuntimeID(release.id)
        }
        try verifyArchive(at: archive, sha256: release.sha256)

        let runtimesFolder = runtimeRoot.appending(path: "Runtimes")
        let runtimeFolder = runtimesFolder.appending(path: release.id)
        try FileManager.default.createDirectory(at: runtimesFolder, withIntermediateDirectories: true)

        if FileManager.default.fileExists(atPath: runtimeFolder.path) {
            guard containsReleaseRuntime(at: runtimeFolder.appending(path: "Libraries")),
                  archiveReceiptMatches(release.sha256, at: runtimeFolder) else {
                throw WhiskyWineReleaseError.invalidArchive
            }
        } else {
            let stagingFolder = runtimesFolder.appending(path: ".staging-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: stagingFolder) }

            try FileManager.default.createDirectory(at: stagingFolder, withIntermediateDirectories: true)
            try Tar.untar(tarBall: archive, toURL: stagingFolder)

            guard containsReleaseRuntime(at: stagingFolder.appending(path: "Libraries")) else {
                throw WhiskyWineReleaseError.invalidArchive
            }
            try writeArchiveReceipt(release.sha256, at: stagingFolder)
            try FileManager.default.moveItem(at: stagingFolder, to: runtimeFolder)
        }

        try activateRuntime(id: release.id)
    }

    public static func activateRuntime(id: String) throws {
        guard id == "legacy" || isValidRuntimeID(id) else {
            throw WhiskyWineReleaseError.invalidRuntimeID(id)
        }

        guard isRuntimeInstalled(id: id) else {
            throw WhiskyWineReleaseError.runtimeNotInstalled(id)
        }

        let previous = activeRuntimeID()
        let state = RuntimeState(active: id, previous: previous == id ? nil : previous)
        let data = try JSONEncoder().encode(state)
        try data.write(to: runtimeStateURL, options: .atomic)
    }

    @discardableResult
    public static func rollbackRuntime() throws -> String {
        let state = loadRuntimeState()
        guard let previous = state.previous else { throw WhiskyWineReleaseError.runtimeNotInstalled("previous") }
        try activateRuntime(id: previous)
        return previous
    }

    public static func activeRuntimeID() -> String {
        loadRuntimeState().active
    }

    /// Resolve stale Bottle metadata to the active runtime without rewriting the Bottle.
    public static func resolvedRuntimeID(_ id: String) -> String {
        isRuntimeInstalled(id: id) ? id : activeRuntimeID()
    }

    public static func isRuntimeInstalled(id: String) -> Bool {
        guard id == "legacy" || isValidRuntimeID(id) else { return false }
        let libraries = libraryFolder(for: id)
        return id == "legacy"
            ? FileManager.default.fileExists(atPath: libraries.path)
            : containsReleaseRuntime(at: libraries)
    }

    /// Whether the runtime ships both required DXVK architectures.
    public static func supportsDXVK(id: String) -> Bool {
        let library = libraryFolder(for: id).appending(path: "DXVK")
        let required = ["x64/d3d11.dll", "x64/dxgi.dll", "x32/d3d11.dll", "x32/dxgi.dll"]
        return isRuntimeInstalled(id: id) && required.allSatisfy {
            FileManager.default.fileExists(atPath: library.appending(path: $0).path)
        }
    }

    /// Runtime identifiers that can be selected by a Bottle, with legacy first for rollback.
    public static func installedRuntimeIDs() -> [String] {
        var ids = isRuntimeInstalled(id: "legacy") ? ["legacy"] : []
        let runtimes = runtimeRoot.appending(path: "Runtimes")
        let installed = (try? FileManager.default.contentsOfDirectory(
            at: runtimes, includingPropertiesForKeys: nil, options: []
        ))?.map(\.lastPathComponent).filter { isRuntimeInstalled(id: $0) }.sorted() ?? []
        ids.append(contentsOf: installed)
        return ids
    }

    private static var runtimeStateURL: URL { runtimeRoot.appending(path: "RuntimeState.json") }

    private static func containsReleaseRuntime(at libraries: URL) -> Bool {
        let wine = libraries.appending(path: "Wine").appending(path: "bin").appending(path: "wine64")
        let version = libraries.appending(path: "WhiskyWineVersion").appendingPathExtension("plist")
        guard FileManager.default.fileExists(atPath: libraries.path),
              (try? libraries.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink != true,
              isSelfContained(libraries) else {
            return false
        }
        guard FileManager.default.fileExists(atPath: wine.path),
              FileManager.default.fileExists(atPath: version.path) else {
            return false
        }

        let hashes = libraries.appending(path: "WhiskyWineBinaries.sha256")
        guard FileManager.default.fileExists(atPath: hashes.path) else { return true }
        let graphicsFiles = [
            "WhiskyWineProvenance.plist",
            "Wine/lib/libfreetype.6.dylib", "Wine/lib/libgnutls.30.dylib", "Wine/lib/libSDL2-2.0.0.dylib",
            "DXVK/x64/d3d11.dll", "DXVK/x64/dxgi.dll", "DXVK/x32/d3d11.dll", "DXVK/x32/dxgi.dll",
            "Vulkan/MoltenVK_icd.json", "Vulkan/libMoltenVK.dylib", "Vulkan/libvulkan.1.dylib"
        ]
        return graphicsFiles.allSatisfy { FileManager.default.fileExists(atPath: libraries.appending(path: $0).path) }
            && hasValidRuntimeHashes(at: libraries)
    }

    private static func isSelfContained(_ directory: URL) -> Bool {
        let root = directory.standardizedFileURL.path
        guard let enumerator = FileManager.default.enumerator(
            at: directory, includingPropertiesForKeys: [.isSymbolicLinkKey]
        ) else { return false }

        while let entry = enumerator.nextObject() as? URL {
            guard let values = try? entry.resourceValues(forKeys: [.isSymbolicLinkKey]),
                  values.isSymbolicLink != true || entry.resolvingSymlinksInPath().standardizedFileURL.path
                    .hasPrefix(root + "/") else {
                return false
            }
        }
        return true
    }

    private struct RuntimeState: Codable {
        var active: String = "legacy"
        var previous: String?
    }

    private static func loadRuntimeState() -> RuntimeState {
        guard let data = try? Data(contentsOf: runtimeStateURL),
              let state = try? JSONDecoder().decode(RuntimeState.self, from: data),
              state.active == "legacy" || isValidRuntimeID(state.active) else {
            return RuntimeState()
        }
        return state
    }

    /// Remove every installed runtime. This is for an explicit user uninstall, never an upgrade.
    public static func uninstallAllRuntimes() {
        do {
            try FileManager.default.removeItem(at: runtimeRoot)
        } catch {
            print("Failed to uninstall WhiskyWine: \(error)")
        }
    }

    public static func shouldUpdateWhiskyWine() async -> (Bool, SemanticVersion) {
        let localVersion = whiskyWineVersion()
        let remoteVersion = await latestRelease()?.version

        if let localVersion = localVersion, let remoteVersion = remoteVersion {
            if localVersion < remoteVersion {
                return (true, remoteVersion)
            }
        }

        return (false, SemanticVersion(0, 0, 0))
    }

    /// Fetch a verified runtime release. Older manifests without a checksum return nil.
    public static func latestRelease() async -> WhiskyWineRelease? {
        guard let info = await remoteReleaseInfo(),
              let archiveURL = info.archiveURL,
              isSecureArchiveURL(archiveURL),
              let sha256 = info.sha256 else {
            return nil
        }
        return WhiskyWineRelease(
            id: info.id ?? String(info.version),
            version: info.version,
            archiveURL: archiveURL,
            sha256: sha256
        )
    }

    static func isSecureArchiveURL(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https" && url.host != nil
    }

    public static func whiskyWineVersion() -> SemanticVersion? {
        whiskyWineVersion(for: activeRuntimeID())
    }

    public static func whiskyWineVersion(for id: String) -> SemanticVersion? {
        do {
            let versionPlist = libraryFolder(for: id)
                .appending(path: "WhiskyWineVersion")
                .appendingPathExtension("plist")

            let decoder = PropertyListDecoder()
            let data = try Data(contentsOf: versionPlist)
            let info = try decoder.decode(WhiskyWineVersion.self, from: data)
            return info.version
        } catch {
            print(error)
            return nil
        }
    }

    private static func remoteReleaseInfo() async -> WhiskyWineVersion? {
        do {
            let (data, _) = try await URLSession(configuration: .ephemeral).data(from: releaseManifestURL)
            return try PropertyListDecoder().decode(WhiskyWineVersion.self, from: data)
        } catch {
            print(error)
            return nil
        }
    }
}

private extension WhiskyWineInstaller {
    static func archiveReceiptMatches(_ sha256: String, at runtime: URL) -> Bool {
        let receipt = runtime.appending(path: "Archive.sha256")
        guard let value = try? String(contentsOf: receipt, encoding: .utf8) else { return false }
        return value.trimmingCharacters(in: .whitespacesAndNewlines) == sha256.lowercased()
    }

    static func writeArchiveReceipt(_ sha256: String, at runtime: URL) throws {
        try Data((sha256.lowercased() + "\n").utf8).write(
            to: runtime.appending(path: "Archive.sha256"), options: .atomic
        )
    }

    static func hasValidRuntimeHashes(at libraries: URL) -> Bool {
        let manifest = libraries.appending(path: "WhiskyWineBinaries.sha256")
        guard let text = try? String(contentsOf: manifest, encoding: .utf8) else { return false }
        var expected: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            let fields = line.split(maxSplits: 1, whereSeparator: \.isWhitespace)
            guard fields.count == 2 else { return false }
            let hash = String(fields[0]).lowercased()
            let path = String(fields[1])
            let components = path.split(separator: "/", omittingEmptySubsequences: false)
            guard hash.count == 64, hash.allSatisfy(\.isHexDigit), path.hasPrefix("Libraries/"),
                  !components.contains(".") && !components.contains(".."), expected[path] == nil else {
                return false
            }
            expected[path] = hash
        }

        let root = libraries.deletingLastPathComponent().standardizedFileURL
        guard let enumerator = FileManager.default.enumerator(
            at: libraries, includingPropertiesForKeys: [.isRegularFileKey]
        ) else { return false }
        var actual: [String: String] = [:]
        while let file = enumerator.nextObject() as? URL {
            guard (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
            let standardizedPath = file.standardizedFileURL.path
            guard standardizedPath.hasPrefix(root.path + "/") else { return false }
            let path = String(standardizedPath.dropFirst(root.path.count + 1))
            guard path != "Libraries/WhiskyWineBinaries.sha256", let hash = try? fileSHA256(of: file) else {
                if path == "Libraries/WhiskyWineBinaries.sha256" { continue }
                return false
            }
            actual[path] = hash
        }
        return !expected.isEmpty && actual == expected
    }
}

struct WhiskyWineVersion: Codable {
    var version: SemanticVersion = SemanticVersion(1, 0, 0)
    var id: String?
    var archiveURL: URL?
    var sha256: String?

    private enum CodingKeys: String, CodingKey {
        case version, id, archiveURL, sha256
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(SemanticVersion.self, forKey: .version) ?? SemanticVersion(1, 0, 0)
        id = try container.decodeIfPresent(String.self, forKey: .id)
        sha256 = try container.decodeIfPresent(String.self, forKey: .sha256)
        if let string = try? container.decode(String.self, forKey: .archiveURL) {
            archiveURL = URL(string: string)
        } else {
            archiveURL = try container.decodeIfPresent(URL.self, forKey: .archiveURL)
        }
    }
}
