//
//  Wine.swift
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
import os.log

public class Wine {
    /// Path to the `wine64` binary
    public static var wineBinary: URL { WhiskyWineInstaller.binFolder.appending(path: "wine64") }
    public static func wineBinary(for bottle: Bottle) -> URL {
        WhiskyWineInstaller.binFolder(for: runtimeID(for: bottle)).appending(path: "wine64")
    }
    static func runtimeID(for bottle: Bottle?) -> String {
        if let bottle {
            return WhiskyWineInstaller.resolvedRuntimeID(bottle.settings.runtimeID)
        }
        return WhiskyWineInstaller.activeRuntimeID()
    }
    private static func wineserverBinary(for bottle: Bottle?) -> URL {
        WhiskyWineInstaller.binFolder(for: runtimeID(for: bottle)).appending(path: "wineserver")
    }

    /// Run a process on a executable file given by the `executableURL`
    private static func runProcess(
        name: String? = nil, args: [String], environment: [String: String], executableURL: URL, directory: URL? = nil,
        fileHandle: FileHandle?
    ) throws -> AsyncStream<ProcessOutput> {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = args
        process.currentDirectoryURL = directory ?? executableURL.deletingLastPathComponent()
        process.environment = environment
        process.qualityOfService = .userInitiated
        return try process.runStream(
            name: name ?? args.joined(separator: " "), fileHandle: fileHandle
        )
    }

    /// Run a `wine` process with the given arguments and environment variables returning a stream of output
    static func runWineProcess(
        name: String? = nil, args: [String], environment: [String: String] = [:],
        fileHandle: FileHandle?, bottle: Bottle? = nil
    ) throws -> AsyncStream<ProcessOutput> {
        return try runProcess(
            name: name, args: args, environment: environment,
            executableURL: bottle.map { wineBinary(for: $0) } ?? wineBinary,
            fileHandle: fileHandle
        )
    }

    /// Run a `wineserver` process with the given arguments and environment variables returning a stream of output
    static func runWineserverProcess(
        name: String? = nil, args: [String], environment: [String: String] = [:],
        fileHandle: FileHandle?, bottle: Bottle? = nil
    ) throws -> AsyncStream<ProcessOutput> {
        return try runProcess(
            name: name, args: args, environment: environment, executableURL: wineserverBinary(for: bottle),
            fileHandle: fileHandle
        )
    }

    /// Run a `wine` process with the given arguments and environment variables returning a stream of output
    public static func runWineProcess(
        name: String? = nil, args: [String], bottle: Bottle, environment: [String: String] = [:]
    ) throws -> AsyncStream<ProcessOutput> {
        let fileHandle = try makeFileHandle()
        fileHandle.writeApplicaitonInfo()
        fileHandle.writeInfo(for: bottle)
        return try runWineProcess(name: name, args: args,
                                  environment: constructWineEnvironment(for: bottle, environment: environment),
                                  fileHandle: fileHandle, bottle: bottle)
    }

    /// Run a `wineserver` process with the given arguments and environment variables returning a stream of output
    public static func runWineserverProcess(
        name: String? = nil, args: [String], bottle: Bottle, environment: [String: String] = [:]
    ) throws -> AsyncStream<ProcessOutput> {
        let fileHandle = try makeFileHandle()
        fileHandle.writeApplicaitonInfo()
        fileHandle.writeInfo(for: bottle)
        let wineServerEnvironment = constructWineServerEnvironment(for: bottle, environment: environment)
        return try runWineserverProcess(name: name, args: args,
                                        environment: wineServerEnvironment,
                                        fileHandle: fileHandle, bottle: bottle)
    }

    /// Execute a `wine start /unix {url}` command returning the output result
    public static func runProgram(
        at url: URL, args: [String] = [], bottle: Bottle, environment: [String: String] = [:]
    ) async throws {
        try prepareGraphicsBackend(for: bottle)
        for await _ in try Self.runWineProcess(
            name: url.lastPathComponent,
            args: ["start", "/unix", url.path(percentEncoded: false)] + args,
            bottle: bottle, environment: environment
        ) { }
    }

    public static func generateRunCommand(
        at url: URL, bottle: Bottle, args: String, environment: [String: String]
    ) -> String {
        var wineCmd = "\(wineBinary(for: bottle).esc) start /unix \(url.esc) \(args)"
        let env = constructWineEnvironment(for: bottle, environment: environment)
        for environment in env {
            wineCmd = "\(environment.key)=\"\(environment.value)\" " + wineCmd
        }
        return wineCmd
    }

    public static func generateTerminalEnvironmentCommand(bottle: Bottle) -> String {
        var cmd = """
        export PATH=\"\(WhiskyWineInstaller.binFolder(for: runtimeID(for: bottle)).path):$PATH\"
        export WINE=\"wine64\"
        alias wine=\"wine64\"
        alias winecfg=\"wine64 winecfg.exe\"
        alias msiexec=\"wine64 msiexec\"
        alias regedit=\"wine64 regedit\"
        alias regsvr32=\"wine64 regsvr32\"
        alias wineboot=\"wine64 wineboot.exe\"
        alias wineconsole=\"wine64 wineconsole\"
        alias winedbg=\"wine64 winedbg\"
        alias winefile=\"wine64 winefile\"
        alias winepath=\"wine64 winepath\"
        """
        let env = constructWineEnvironment(for: bottle, environment: constructWineEnvironment(for: bottle))
        for environment in env {
            cmd += "\nexport \(environment.key)=\"\(environment.value)\""
        }
        return cmd
    }

    @discardableResult
    /// Run a `wine` command with the given arguments and return the output result
    public static func runWine(
        _ args: [String], bottle: Bottle?, environment: [String: String] = [:]
    ) async throws -> String {
        var result: [String] = []
        var didTerminate = false
        let fileHandle = try makeFileHandle()
        fileHandle.writeApplicaitonInfo()
        var environment = environment
        if let bottle = bottle {
            fileHandle.writeInfo(for: bottle)
            environment = constructWineEnvironment(for: bottle, environment: environment)
        }
        for await output in try runWineProcess(
            args: args, environment: environment, fileHandle: fileHandle, bottle: bottle
        ) {
            switch output {
            case .started:
                break
            case .terminated(let process):
                didTerminate = true
                guard process.terminationStatus == 0 else {
                    throw WineProcessError.terminated(process.terminationStatus)
                }
            case .message(let message), .error(let message):
                result.append(message)
            }
        }
        guard didTerminate else { throw WineProcessError.commandDidNotTerminate }
        return result.joined()
    }

    public static func wineVersion() async throws -> String {
        var output = try await runWine(["--version"], bottle: nil)
        output.replace("wine-", with: "")

        // Deal with WineCX version names
        if let index = output.firstIndex(where: { $0.isWhitespace }) {
            return String(output.prefix(upTo: index))
        }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @discardableResult
    public static func runBatchFile(url: URL, bottle: Bottle) async throws -> String {
        return try await runWine(["cmd", "/c", url.path(percentEncoded: false)], bottle: bottle)
    }

    public static func killBottle(bottle: Bottle) throws {
        let stream = try runWineserverProcess(args: ["-k"], bottle: bottle)
        Task.detached(priority: .userInitiated) {
            for await _ in stream { }
        }
    }

    /// Construct an environment merging the bottle values with the given values
    private static func constructWineEnvironment(
        for bottle: Bottle, environment: [String: String] = [:]
    ) -> [String: String] {
        var result: [String: String] = [
            "WINEPREFIX": bottle.url.path,
            "WINEDEBUG": "fixme-all",
            "GST_DEBUG": "1"
        ]
        bottle.settings.environmentVariables(wineEnv: &result)
        if bottle.settings.usesDXVK && !WhiskyWineInstaller.supportsDXVK(id: runtimeID(for: bottle)) {
            result.removeValue(forKey: "WINEDLLOVERRIDES")
            result.removeValue(forKey: "DXVK_ASYNC")
            result.removeValue(forKey: "DXVK_HUD")
        }
        result.merge(environment, uniquingKeysWith: { $1 })
        configureRuntimeLibraryEnvironment(for: bottle, wineEnv: &result)
        configureVulkanEnvironment(for: bottle, wineEnv: &result)
        return result
    }

    private static func configureRuntimeLibraryEnvironment(for bottle: Bottle, wineEnv: inout [String: String]) {
        let wineLibraryFolder = WhiskyWineInstaller.libraryFolder(for: runtimeID(for: bottle))
            .appending(path: "Wine/lib")
        guard FileManager.default.fileExists(atPath: wineLibraryFolder.path) else { return }

        if let fallback = wineEnv["DYLD_FALLBACK_LIBRARY_PATH"], !fallback.isEmpty {
            wineEnv["DYLD_FALLBACK_LIBRARY_PATH"] = "\(wineLibraryFolder.path):\(fallback)"
        } else {
            wineEnv["DYLD_FALLBACK_LIBRARY_PATH"] = wineLibraryFolder.path
        }
    }

    private static func configureVulkanEnvironment(for bottle: Bottle, wineEnv: inout [String: String]) {
        let vulkanFolder = WhiskyWineInstaller.libraryFolder(for: runtimeID(for: bottle)).appending(path: "Vulkan")
        let icd = vulkanFolder.appending(path: "MoltenVK_icd.json")
        guard FileManager.default.fileExists(atPath: icd.path) else { return }

        wineEnv["VK_DRIVER_FILES"] = icd.path
        wineEnv["VK_ICD_FILENAMES"] = icd.path
        if let fallback = wineEnv["DYLD_FALLBACK_LIBRARY_PATH"], !fallback.isEmpty {
            wineEnv["DYLD_FALLBACK_LIBRARY_PATH"] = "\(vulkanFolder.path):\(fallback)"
        } else {
            wineEnv["DYLD_FALLBACK_LIBRARY_PATH"] = vulkanFolder.path
        }
    }

    /// Construct an environment merging the bottle values with the given values
    private static func constructWineServerEnvironment(
        for bottle: Bottle, environment: [String: String] = [:]
    ) -> [String: String] {
        var result: [String: String] = [
            "WINEPREFIX": bottle.url.path,
            "WINEDEBUG": "fixme-all",
            "GST_DEBUG": "1"
        ]
        result.merge(environment, uniquingKeysWith: { $1 })
        configureRuntimeLibraryEnvironment(for: bottle, wineEnv: &result)
        return result
    }
}

enum WineInterfaceError: Error {
    case invalidResponce
}

public enum WineProcessError: Error, Equatable {
    case terminated(Int32)
    case commandDidNotTerminate
}

enum RegistryType: String {
    case binary = "REG_BINARY"
    case dword = "REG_DWORD"
    case qword = "REG_QWORD"
    case string = "REG_SZ"
}

extension Wine {
    private enum RegistryKey: String {
        case currentVersion = #"HKLM\Software\Microsoft\Windows NT\CurrentVersion"#
        case macDriver = #"HKCU\Software\Wine\Mac Driver"#
        case desktop = #"HKCU\Control Panel\Desktop"#
    }

    private static func addRegistryKey(
        bottle: Bottle, key: String, name: String, data: String, type: RegistryType
    ) async throws {
        try await runWine(
            ["reg", "add", key, "-v", name, "-t", type.rawValue, "-d", data, "-f"],
            bottle: bottle
        )
    }

    private static func queryRegistryKey(
        bottle: Bottle, key: String, name: String, type: RegistryType
    ) async throws -> String? {
        let output = try await runWine(["reg", "query", key, "-v", name], bottle: bottle)
        let lines = output.split(omittingEmptySubsequences: true, whereSeparator: \.isNewline)

        guard let line = lines.first(where: { $0.contains(type.rawValue) }) else { return nil }
        let array = line.split(omittingEmptySubsequences: true, whereSeparator: \.isWhitespace)
        guard let value = array.last else { return nil }
        return String(value)
    }

    public static func changeBuildVersion(bottle: Bottle, version: Int) async throws {
        try await addRegistryKey(bottle: bottle, key: RegistryKey.currentVersion.rawValue,
                                name: "CurrentBuild", data: "\(version)", type: .string)
        try await addRegistryKey(bottle: bottle, key: RegistryKey.currentVersion.rawValue,
                                name: "CurrentBuildNumber", data: "\(version)", type: .string)
    }

    public static func winVersion(bottle: Bottle) async throws -> WinVersion {
        let output = try await Wine.runWine(["winecfg.exe", "-v"], bottle: bottle)
        let lines = output.split(whereSeparator: \.isNewline)

        if let lastLine = lines.last {
            let winString = String(lastLine)

            if let version = WinVersion(rawValue: winString) {
                return version
            }
        }

        throw WineInterfaceError.invalidResponce
    }

    public static func buildVersion(bottle: Bottle) async throws -> String? {
        return try await Wine.queryRegistryKey(
            bottle: bottle, key: RegistryKey.currentVersion.rawValue,
            name: "CurrentBuild", type: .string
        )
    }

    public static func retinaMode(bottle: Bottle) async throws -> Bool {
        let values: Set<String> = ["y", "n"]
        guard let output = try await Wine.queryRegistryKey(
            bottle: bottle, key: RegistryKey.macDriver.rawValue, name: "RetinaMode", type: .string
        ), values.contains(output) else {
            try await changeRetinaMode(bottle: bottle, retinaMode: false)
            return false
        }
        return output == "y"
    }

    public static func changeRetinaMode(bottle: Bottle, retinaMode: Bool) async throws {
        try await Wine.addRegistryKey(
            bottle: bottle, key: RegistryKey.macDriver.rawValue, name: "RetinaMode", data: retinaMode ? "y" : "n",
            type: .string
        )
    }

    public static func dpiResolution(bottle: Bottle) async throws -> Int? {
        guard let output = try await Wine.queryRegistryKey(bottle: bottle, key: RegistryKey.desktop.rawValue,
                                                     name: "LogPixels", type: .dword
        ) else { return nil }

        let noPrefix = output.replacingOccurrences(of: "0x", with: "")
        let int = Int(noPrefix, radix: 16)
        guard let int = int else { return nil }
        return int
    }

    public static func changeDpiResolution(bottle: Bottle, dpi: Int) async throws {
        try await Wine.addRegistryKey(
            bottle: bottle, key: RegistryKey.desktop.rawValue, name: "LogPixels", data: String(dpi),
            type: .dword
        )
    }

    @discardableResult
    public static func control(bottle: Bottle) async throws -> String {
        return try await Wine.runWine(["control"], bottle: bottle)
    }

    @discardableResult
    public static func regedit(bottle: Bottle) async throws -> String {
        return try await Wine.runWine(["regedit"], bottle: bottle)
    }

}
