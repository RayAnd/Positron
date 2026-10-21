// SPDX-License-Identifier: MIT
import Foundation

public enum RunnerKind: String, Codable, Sendable, CaseIterable {
    case crossOverStable = "crossover-stable"
    case crossOverPreview = "crossover-preview"
    case whiskyWine = "whisky-wine"
    case customWine = "custom-wine"
}

public enum CPUTranslator: String, Codable, Sendable, CaseIterable {
    case rosetta = "rosetta"
    case fex = "fex"

    public var unixDirectoryName: String {
        switch self {
        case .rosetta: return "x86_64-unix"
        case .fex: return "aarch64-unix"
        }
}

    public var guestPrefixArchitecture: String {
        switch self {
        case .rosetta: return "x86_64"
        case .fex: return "arm64"
        }
    }
}

public enum GraphicsBackend: String, Codable, Sendable, CaseIterable {
    case d3dMetal = "d3dmetal"
    case dxmt = "dxmt"
    case dxvk = "dxvk"
    case wineD3D = "wined3d"
}

public struct NtdllInspection: Codable, Sendable, Equatable {
    public let archDirectory: String
    public let machineHex: String
    public let isPE32Plus: Bool
    public let imageBase: UInt64
    public let ldrLoadDllRVA: UInt32
    public let ldrGetDllHandleRVA: UInt32
    public let ntProtectVirtualMemoryRVA: UInt32
    public let hasPaddingCave: Bool
    public let paddingCaveSize: UInt32

    public var isReadyForDynamicBridge: Bool {
        ldrLoadDllRVA != 0 && ldrGetDllHandleRVA != 0 && ntProtectVirtualMemoryRVA != 0
    }
}

public struct DiscoveredRunner: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let displayName: String
    public let kind: RunnerKind
    public let bundleVersion: String
    public let shortVersion: String
    public let rootURL: URL
    public let supportedTranslators: [CPUTranslator]
    public let availableGraphicsBackends: [GraphicsBackend]
    public let ntdllInspections: [NtdllInspection]

    public var supportsFEX: Bool {
        supportedTranslators.contains(.fex)
    }

    public var supportsRosetta: Bool {
        supportedTranslators.contains(.rosetta)
    }
}

public enum UniversalPEAnalyzer {
    /// Dynamically parses a PE32 or PE32+ ntdll.dll without any hardcoded SHA-256 allowlist.
    public static func inspectNtdll(at url: URL, archDirectory: String) -> NtdllInspection? {
        guard let data = try? Data(contentsOf: url), data.count >= 0x100 else { return nil }
        return inspectNtdll(bytes: [UInt8](data), archDirectory: archDirectory)
    }

    public static func inspectNtdll(bytes: [UInt8], archDirectory: String) -> NtdllInspection? {
        guard bytes.count >= 0x100 else { return nil }
        func u16(_ off: Int) -> UInt16 {
            guard off >= 0, off + 2 <= bytes.count else { return 0 }
            return UInt16(bytes[off]) | (UInt16(bytes[off + 1]) << 8)
        }
        func u32(_ off: Int) -> UInt32 {
            guard off >= 0, off + 4 <= bytes.count else { return 0 }
            return UInt32(bytes[off]) |
                (UInt32(bytes[off + 1]) << 8) |
                (UInt32(bytes[off + 2]) << 16) |
                (UInt32(bytes[off + 3]) << 24)
        }
        func u64(_ off: Int) -> UInt64 {
            return UInt64(u32(off)) | (UInt64(u32(off + 4)) << 32)
        }

        guard u16(0) == 0x5A4D else { return nil }
        let lfanew = Int(u32(0x3C))
        guard lfanew + 24 <= bytes.count, u32(lfanew) == 0x0000_4550 else { return nil }

        let machine = u16(lfanew + 4)
        let numSects = Int(u16(lfanew + 6))
        let optSize = Int(u16(lfanew + 20))
        let optOff = lfanew + 24
        guard optOff + optSize <= bytes.count, optSize >= 96 else { return nil }

        let magic = u16(optOff)
        let isPE32Plus = (magic == 0x020B)
        guard isPE32Plus || magic == 0x010B else { return nil }

        let imageBase = isPE32Plus ? u64(optOff + 24) : UInt64(u32(optOff + 28))
        let sectTable = optOff + optSize
        guard sectTable + numSects * 40 <= bytes.count else { return nil }

        func rvaToOff(_ rva: UInt32) -> Int? {
            for i in 0..<numSects {
                let entry = sectTable + i * 40
                let vSize = u32(entry + 8)
                let vAddr = u32(entry + 12)
                let rSize = u32(entry + 16)
                let rOff = u32(entry + 20)
                let span = max(vSize, rSize)
                if rSize > 0, rva >= vAddr, rva < vAddr + span {
                    let delta = rva - vAddr
                    if delta < rSize, Int(rOff + delta) < bytes.count {
                        return Int(rOff + delta)
                    }
                }
            }
            return nil
        }

        var ldrLoadDll: UInt32 = 0
        var ldrGetDllHandle: UInt32 = 0
        var ntProtect: UInt32 = 0

        let dataDirOff = optOff + (isPE32Plus ? 112 : 96)
        if dataDirOff + 8 <= optOff + optSize {
            let expRVA = u32(dataDirOff)
            let expSize = u32(dataDirOff + 4)
            if expRVA > 0, expSize >= 40, let expOff = rvaToOff(expRVA), expOff + 40 <= bytes.count {
                let nFuncs = Int(u32(expOff + 20))
                let nNames = min(Int(u32(expOff + 24)), 8192)
                let funcsRVA = u32(expOff + 28)
                let namesRVA = u32(expOff + 32)
                let ordsRVA = u32(expOff + 36)

                if let funcsOff = rvaToOff(funcsRVA),
                   let namesOff = rvaToOff(namesRVA),
                   let ordsOff = rvaToOff(ordsRVA) {
                    for i in 0..<nNames {
                        guard namesOff + (i + 1) * 4 <= bytes.count,
                              ordsOff + (i + 1) * 2 <= bytes.count else { break }
                        let nameRVA = u32(namesOff + i * 4)
                        let ord = Int(u16(ordsOff + i * 2))
                        guard ord < nFuncs, funcsOff + (ord + 1) * 4 <= bytes.count,
                              let strOff = rvaToOff(nameRVA) else { continue }
                        let fnRVA = u32(funcsOff + ord * 4)
                        var end = strOff
                        while end < bytes.count, bytes[end] != 0, end - strOff < 128 { end += 1 }
                        guard end < bytes.count else { continue }
                        let sym = String(decoding: bytes[strOff..<end], as: UTF8.self)
                        if sym == "LdrLoadDll" { ldrLoadDll = fnRVA }
                        else if sym == "LdrGetDllHandle" { ldrGetDllHandle = fnRVA }
                        else if sym == "NtProtectVirtualMemory" { ntProtect = fnRVA }
                    }
                }
            }
        }

        var caveSize: UInt32 = 0
        for i in 0..<numSects {
            let entry = sectTable + i * 40
            let rSize = Int(u32(entry + 16))
            let rOff = Int(u32(entry + 20))
            let flags = u32(entry + 36)
            if (flags & 0x2000_0000) != 0, rSize > 64, rOff + rSize <= bytes.count {
                let pad = bytes[rOff + rSize - 1]
                if pad == 0x00 || pad == 0xCC {
                    var run = 0
                    while run < rSize, bytes[rOff + rSize - 1 - run] == pad {
                        run += 1
                    }
                    if run > 32 {
                        caveSize = UInt32(run - 32)
                        break
                    }
                }
            }
        }

        return NtdllInspection(
            archDirectory: archDirectory,
            machineHex: String(format: "0x%04x", machine),
            isPE32Plus: isPE32Plus,
            imageBase: imageBase,
            ldrLoadDllRVA: ldrLoadDll,
            ldrGetDllHandleRVA: ldrGetDllHandle,
            ntProtectVirtualMemoryRVA: ntProtect,
            hasPaddingCave: caveSize >= 512,
            paddingCaveSize: caveSize
        )
    }
}

public enum RunnerDiscovery {
    public static func discoverAll(
        searchRoots: [URL] = [
            URL(filePath: "/Applications"),
            FileManager.default.homeDirectoryForCurrentUser.appending(path: "Applications")
        ],
        whiskyWineRoot: URL? = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/com.isaacmarovitz.Whisky/Libraries/Wine")
    ) -> [DiscoveredRunner] {
        let fm = FileManager.default
        var results: [DiscoveredRunner] = []
        var seenPaths: Set<String> = []

        for root in searchRoots {
            guard let items = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else {
                continue
            }
            for item in items where item.pathExtension == "app" {
                let name = item.deletingPathExtension().lastPathComponent
                guard name.localizedCaseInsensitiveContains("CrossOver") else { continue }
                let cxRoot = item.appending(path: "Contents/SharedSupport/CrossOver")
                let canonical = cxRoot.standardizedFileURL.path(percentEncoded: false)
                guard !seenPaths.contains(canonical),
                      fm.fileExists(atPath: cxRoot.appending(path: "lib/wine").path(percentEncoded: false))
                else { continue }
                seenPaths.insert(canonical)

                if let runner = inspectCrossOverBundle(appURL: item, cxRoot: cxRoot) {
                    results.append(runner)
                }
            }
        }

        if let whiskyRoot = whiskyWineRoot,
           fm.fileExists(atPath: whiskyRoot.appending(path: "lib/wine").path(percentEncoded: false)) {
            let canonical = whiskyRoot.standardizedFileURL.path(percentEncoded: false)
            if !seenPaths.contains(canonical),
               let whiskyRunner = inspectCustomWineRoot(
                   rootURL: whiskyRoot,
                   id: "whisky-wine",
                   displayName: "WhiskyWine",
                   kind: .whiskyWine,
                   bundleVersion: "whisky",
                   shortVersion: "Whisky"
               ) {
                results.append(whiskyRunner)
            }
        }

        return results.sorted { $0.id < $1.id }
    }

    public static func inspectCrossOverBundle(appURL: URL, cxRoot: URL) -> DiscoveredRunner? {
        let plistURL = appURL.appending(path: "Contents/Info.plist")
        var bundleVer = "unknown"
        var shortVer = "unknown"
        if let data = try? Data(contentsOf: plistURL),
           let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
            bundleVer = (dict["CFBundleVersion"] as? String) ?? "unknown"
            shortVer = (dict["CFBundleShortVersionString"] as? String) ?? bundleVer
        }

        let isPreview = appURL.lastPathComponent.localizedCaseInsensitiveContains("Preview")
        let kind: RunnerKind = isPreview ? .crossOverPreview : .crossOverStable
        let slug = isPreview ? "crossover-preview-\(bundleVer)" : "crossover-\(bundleVer)"
        let title = isPreview ? "CrossOver Preview \(shortVer) (\(bundleVer))" : "CrossOver \(shortVer) (\(bundleVer))"

        return inspectCustomWineRoot(
            rootURL: cxRoot,
            id: slug,
            displayName: title,
            kind: kind,
            bundleVersion: bundleVer,
            shortVersion: shortVer
        )
    }

    public static func inspectCustomWineRoot(
        rootURL: URL,
        id: String,
        displayName: String,
        kind: RunnerKind,
        bundleVersion: String,
        shortVersion: String
    ) -> DiscoveredRunner? {
        let fm = FileManager.default
        let wineLib = rootURL.appending(path: "lib/wine")
        guard fm.fileExists(atPath: wineLib.path(percentEncoded: false)) else { return nil }

        var translators: [CPUTranslator] = []
        let armLoader = wineLib.appending(path: "aarch64-unix/wine.app/Contents/MacOS/wine")
        let armPlainLoader = wineLib.appending(path: "aarch64-unix/wine")
        if fm.isExecutableFile(atPath: armLoader.path(percentEncoded: false)) ||
           fm.isExecutableFile(atPath: armPlainLoader.path(percentEncoded: false)) {
            translators.append(.fex)
        }

        let x86Loader = wineLib.appending(path: "x86_64-unix/wine")
        let binWine64 = rootURL.appending(path: "bin/wine64")
        let binWine = rootURL.appending(path: "bin/wine")
        if fm.isExecutableFile(atPath: x86Loader.path(percentEncoded: false)) ||
           fm.isExecutableFile(atPath: binWine64.path(percentEncoded: false)) ||
           fm.isExecutableFile(atPath: binWine.path(percentEncoded: false)) {
            translators.append(.rosetta)
        }

        var backends: [GraphicsBackend] = [.wineD3D]
        if fm.fileExists(atPath: rootURL.appending(path: "lib64/apple_gptk").path(percentEncoded: false)) {
            backends.insert(.d3dMetal, at: 0)
        }
        if fm.fileExists(atPath: wineLib.appending(path: "x86_64-windows/d3d11.dll").path(percentEncoded: false)) {
            backends.append(.dxmt)
            backends.append(.dxvk)
        }

        var inspections: [NtdllInspection] = []
        for archDir in ["x86_64-windows", "i386-windows", "aarch64-windows"] {
            let ntdllURL = wineLib.appending(path: "\(archDir)/ntdll.dll")
            if let info = UniversalPEAnalyzer.inspectNtdll(at: ntdllURL, archDirectory: archDir) {
                inspections.append(info)
            }
        }

        return DiscoveredRunner(
            id: id,
            displayName: displayName,
            kind: kind,
            bundleVersion: bundleVersion,
            shortVersion: shortVersion,
            rootURL: rootURL,
            supportedTranslators: translators,
            availableGraphicsBackends: backends,
            ntdllInspections: inspections
        )
    }
}