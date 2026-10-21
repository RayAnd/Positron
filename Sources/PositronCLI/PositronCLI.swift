// SPDX-License-Identifier: MIT
import Foundation
import PositronCore

@main
struct PositronCLI {
    static func main() {
        let args = Array(CommandLine.arguments.dropFirst())
        let command = args.first ?? "status"

        switch command {
        case "status", "runners":
            let runners = RunnerDiscovery.discoverAll()
            print("=== Positron Universal Runner Discovery ===")
            print("Discovered \(runners.count) Wine/CrossOver runner(s) on this Mac:\n")
            for r in runners {
                let translators = r.supportedTranslators.map(\.rawValue).joined(separator: ", ")
                let backends = r.availableGraphicsBackends.map(\.rawValue).joined(separator: ", ")
                print("• \(r.displayName) [id: \(r.id)]")
                print("  Kind:        \(r.kind.rawValue)")
                print("  Path:        \(r.rootURL.path(percentEncoded: false))")
                print("  Translators: \(translators)")
                print("  Graphics:    \(backends)")
                for ntdll in r.ntdllInspections {
                    print(String(
                        format: "  ntdll (%@): machine=%@ LdrLoadDll=0x%x LdrGetDllHandle=0x%x NtProtect=0x%x paddingCave=%uB ready=%@",
                        ntdll.archDirectory,
                        ntdll.machineHex,
                        ntdll.ldrLoadDllRVA,
                        ntdll.ldrGetDllHandleRVA,
                        ntdll.ntProtectVirtualMemoryRVA,
                        ntdll.paddingCaveSize,
                        ntdll.isReadyForDynamicBridge ? "YES" : "NO"
                    ))
                }
                print("")
            }

        case "doctor":
            let fm = FileManager.default
            let steamApp = URL(filePath: "/Applications/Steam.app")
            let steamPresent = fm.fileExists(atPath: steamApp.path(percentEncoded: false))
            let runners = RunnerDiscovery.discoverAll()
            let readyCount = runners.filter { $0.ntdllInspections.allSatisfy(\.isReadyForDynamicBridge) }.count
            print("=== Positron Doctor ===")
            print("• Steam.app installed:   \(steamPresent ? "YES (/Applications/Steam.app)" : "NO")")
            print("• Discovered runners:    \(runners.count) (\(readyCount) ready for dynamic PE bridge)")
            print("• FEX-capable runners:   \(runners.filter(\.supportsFEX).count)")
            print("• Rosetta runners:       \(runners.filter(\.supportsRosetta).count)")
            print("• Built-in game quirks:  \(GameQuirksDatabase.knownQuirks.count) title profile(s)")

        case "sync-tools":
            let destPath = args.dropFirst().first ?? FileManager.default.homeDirectoryForCurrentUser
                .appending(path: "Library/Application Support/Positron/compatibilitytools.d")
                .path(percentEncoded: false)
            let destURL = URL(filePath: destPath)
            let runners = RunnerDiscovery.discoverAll()
            do {
                let tools = try SteamIntegration.registerCompatibilityTools(for: runners, in: destURL)
                print("Registered \(tools.count) Positron compatibility tool(s) in \(destPath):")
                for t in tools {
                    print("  • \(t.toolName) -> \"\(t.displayName)\"")
                }
            } catch {
                fputs("Failed to register compatibility tools: \(error.localizedDescription)\n", stderr)
                exit(1)
            }

        case "profile":
            let appID = args.dropFirst().first.flatMap { UInt32($0) } ?? 1091500
            let translator: CPUTranslator = args.contains("--fex") ? .fex : .rosetta
            let profile = GameQuirksDatabase.defaultProfile(forAppID: appID, preferredTranslator: translator)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let data = try? encoder.encode(profile), let json = String(data: data, encoding: .utf8) {
                print(json)
            }

        default:
            print("Usage: positron [status | runners | doctor | sync-tools [dir] | profile <appid> [--fex]]")
        }
    }
}