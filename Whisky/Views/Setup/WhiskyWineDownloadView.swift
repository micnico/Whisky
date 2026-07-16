//
//  WhiskyWineDownloadView.swift
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

import SwiftUI
import WhiskyKit

struct WhiskyWineDownloadView: View {
    @State private var fractionProgress: Double = 0
    @State private var completedBytes: Int64 = 0
    @State private var totalBytes: Int64 = 0
    @State private var downloadSpeed: Double = 0
    @State private var downloadTask: URLSessionDownloadTask?
    @State private var observation: NSKeyValueObservation?
    @State private var startTime: Date?
    @State private var errorMessage: String?
    @Binding var tarLocation: URL
    @Binding var release: WhiskyWineRelease?
    @Binding var path: [SetupStage]
    var body: some View {
        VStack {
            VStack {
                Text("setup.whiskywine.download")
                    .font(.title)
                    .fontWeight(.bold)
                Text("setup.whiskywine.download.subtitle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                    Button("setup.retry", action: startDownload)
                } else {
                    VStack {
                        if totalBytes > 0 {
                            ProgressView(value: fractionProgress, total: 1)
                        } else {
                            ProgressView()
                        }
                        HStack {
                            HStack {
                                progressText
                                Spacer()
                            }
                            .font(.subheadline)
                            .monospacedDigit()
                        }
                    }
                    .padding(.horizontal)
                }
                Spacer()
            }
            Spacer()
        }
        .frame(width: 400, height: 200)
        .onAppear(perform: startDownload)
    }

    func formatBytes(bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.zeroPadsFractionDigits = true
        return formatter.string(fromByteCount: bytes)
    }

    func shouldShowEstimate() -> Bool {
        let elapsedTime = Date().timeIntervalSince(startTime ?? Date())
        return Int(elapsedTime.rounded()) > 5 && completedBytes != 0
    }

    func formatRemainingTime(remainingBytes: Int64) -> String {
        let remainingTimeInSeconds = Double(remainingBytes) / downloadSpeed

        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .full
        if shouldShowEstimate() {
            return formatter.string(from: TimeInterval(remainingTimeInSeconds)) ?? ""
        } else {
            return ""
        }
    }

    var progressText: Text {
        let progress = totalBytes > 0
            ? Text(String(format: String(localized: "setup.whiskywine.progress"),
                        formatBytes(bytes: completedBytes), formatBytes(bytes: totalBytes)))
            : Text(formatBytes(bytes: completedBytes))
        return progress + Text(" ") + (shouldShowEstimate()
            ? Text(String(format: String(localized: "setup.whiskywine.eta"),
                        formatRemainingTime(remainingBytes: totalBytes - completedBytes)))
            : Text(""))
    }

    func startDownload() {
        downloadTask?.cancel()
        errorMessage = nil
        fractionProgress = 0
        completedBytes = 0
        totalBytes = 0
        downloadSpeed = 0
        Task {
            release = await WhiskyWineInstaller.latestRelease()
            let url = release?.archiveURL ?? WhiskyWineInstaller.legacyArchiveURL
            let task = URLSession(configuration: .ephemeral).downloadTask(with: url) { url, _, error in
                Task { @MainActor in
                    guard let url else {
                        errorMessage = error?.localizedDescription ?? String(localized: "alert.message")
                        return
                    }
                    tarLocation = url
                    proceed()
                }
            }
            downloadTask = task
            observation = task.observe(\.countOfBytesReceived) { task, _ in
                Task { @MainActor in
                    let currentTime = Date()
                    let elapsedTime = currentTime.timeIntervalSince(startTime ?? currentTime)
                    if completedBytes > 0 {
                        downloadSpeed = Double(completedBytes) / elapsedTime
                    }
                    totalBytes = max(task.countOfBytesExpectedToReceive, 0)
                    completedBytes = task.countOfBytesReceived
                    fractionProgress = totalBytes > 0 ? Double(completedBytes) / Double(totalBytes) : 0
                }
            }
            startTime = Date()
            task.resume()
        }
    }

    func proceed() {
        path.append(.whiskyWineInstall)
    }
}
