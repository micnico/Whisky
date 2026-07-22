//
//  Wine+BottleInitialization.swift
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

public extension Wine {
    @discardableResult
    static func cfg(bottle: Bottle) async throws -> String {
        try await runWine(["winecfg.exe"], bottle: bottle)
    }

    @discardableResult
    static func initializeBottle(_ bottle: Bottle) async throws -> String {
        try await runWine(
            ["wineboot.exe", "-u"], bottle: bottle,
            environment: ["WINEDLLOVERRIDES": "mscoree,mshtml="]
        )
    }

    @discardableResult
    static func changeWinVersion(bottle: Bottle, win: WinVersion) async throws -> String {
        try await runWine(
            ["winecfg.exe", "-v", win.rawValue], bottle: bottle,
            environment: ["WINEDLLOVERRIDES": "mscoree,mshtml="]
        )
    }
}
