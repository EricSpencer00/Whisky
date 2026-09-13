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

    /// The folder of all the library files
    public static let libraryFolder = applicationFolder.appending(path: "Libraries")

    /// URL to the installed `wine` `bin` directory
    public static let binFolder: URL = libraryFolder.appending(path: "Wine").appending(path: "bin")

    /// Folder containing the bundled universal `libMoltenVK.dylib` and `icd.d/MoltenVK_icd.json`.
    public static let moltenvkFolder: URL = libraryFolder.appending(path: "MoltenVK")

    /// Absolute path to the bundled MoltenVK ICD manifest — used as `VK_ICD_FILENAMES` at bottle launch.
    public static let moltenvkIcdPath: URL = moltenvkFolder
        .appending(path: "icd.d").appending(path: "MoltenVK_icd.json")

    /// Folder containing the DXVK DLL set: `x64/{d3d8,d3d9,d3d10core,d3d11,dxgi}.dll` and `x32/…`.
    public static let dxvkFolder: URL = libraryFolder.appending(path: "DXVK")

    public static func isWhiskyWineInstalled() -> Bool {
        return whiskyWineVersion() != nil
    }

    public static func install(from: URL) {
        let fileManager = FileManager.default
        let supportFolder = applicationFolder.deletingLastPathComponent()
        let stagingFolder = supportFolder.appending(path: ".WhiskyWine.staging-\(UUID().uuidString)")
        let backupFolder = supportFolder.appending(path: ".WhiskyWine.backup-\(UUID().uuidString)")
        var movedExistingInstallation = false

        do {
            try fileManager.createDirectory(at: stagingFolder, withIntermediateDirectories: true)
            try Tar.untar(tarBall: from, toURL: stagingFolder)
            try validateBundle(at: stagingFolder)

            if fileManager.fileExists(atPath: applicationFolder.path) {
                try fileManager.moveItem(at: applicationFolder, to: backupFolder)
                movedExistingInstallation = true
            }

            do {
                try fileManager.moveItem(at: stagingFolder, to: applicationFolder)
            } catch {
                if movedExistingInstallation {
                    try? fileManager.moveItem(at: backupFolder, to: applicationFolder)
                }
                throw error
            }

            if movedExistingInstallation {
                try? fileManager.removeItem(at: backupFolder)
            }
            try? fileManager.removeItem(at: from)
        } catch {
            try? fileManager.removeItem(at: stagingFolder)
            print("Failed to install WhiskyWine: \(error)")
        }
    }

    private static func validateBundle(at root: URL) throws {
        let requiredFiles = [
            root.appending(path: "Libraries/WhiskyWineVersion.plist"),
            root.appending(path: "Libraries/Wine/bin/wine64"),
            root.appending(path: "Libraries/Wine/bin/wineserver"),
            root.appending(path: "Libraries/Wine/lib/wine/x86_64-unix/winemetal.so"),
            root.appending(path: "Libraries/MoltenVK/libMoltenVK.dylib"),
            root.appending(path: "Libraries/MoltenVK/icd.d/MoltenVK_icd.json")
        ]

        for file in requiredFiles {
            guard FileManager.default.fileExists(atPath: file.path(percentEncoded: false)) else {
                throw "Wine bundle is missing \(file.path(percentEncoded: false))"
            }
        }

        let wine64 = root.appending(path: "Libraries/Wine/bin/wine64")
        guard FileManager.default.isExecutableFile(atPath: wine64.path(percentEncoded: false)) else {
            throw "Wine bundle contains a non-executable wine64"
        }
    }

    public static func uninstall() {
        do {
            try FileManager.default.removeItem(at: libraryFolder)
        } catch {
            print("Failed to uninstall WhiskyWine: \(error)")
        }
    }

    /// Base URL where the WhiskyWine tarball and version plist are hosted.
    /// Override at runtime by setting `WHISKY_WINE_BASE_URL` in the launch
    /// environment — useful for testing against a mirror or a fork's release
    /// assets (e.g. this fork's FOSS-built tarball at
    /// `https://github.com/EricSpencer00/Whisky/releases/.../Libraries.tar.gz`).
    public static var wineBaseURL: String {
        if let override = ProcessInfo.processInfo.environment["WHISKY_WINE_BASE_URL"],
           !override.isEmpty {
            return override
        }
        return "https://github.com/EricSpencer00/Whisky/releases/download/wine-v26.3.0-foss-phase2"
    }

    public static func shouldUpdateWhiskyWine() async -> (Bool, SemanticVersion) {
        let versionPlistURL = "\(wineBaseURL)/WhiskyWineVersion.plist"
        let localVersion = whiskyWineVersion()

        var remoteVersion: SemanticVersion?

        if let remoteUrl = URL(string: versionPlistURL) {
            remoteVersion = await withCheckedContinuation { continuation in
                URLSession(configuration: .ephemeral).dataTask(with: URLRequest(url: remoteUrl)) { data, _, error in
                    do {
                        if error == nil, let data = data {
                            let decoder = PropertyListDecoder()
                            let remoteInfo = try decoder.decode(WhiskyWineVersion.self, from: data)
                            let remoteVersion = remoteInfo.version

                            continuation.resume(returning: remoteVersion)
                            return
                        }
                        if let error = error {
                            print(error)
                        }
                    } catch {
                        print(error)
                    }

                    continuation.resume(returning: nil)
                }.resume()
            }
        }

        if let localVersion = localVersion, let remoteVersion = remoteVersion {
            if localVersion < remoteVersion {
                return (true, remoteVersion)
            }
        }

        return (false, SemanticVersion(0, 0, 0))
    }

    public static func whiskyWineVersion() -> SemanticVersion? {
        do {
            let versionPlist = libraryFolder
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
}

struct WhiskyWineVersion: Codable {
    var version: SemanticVersion = SemanticVersion(1, 0, 0)
}
