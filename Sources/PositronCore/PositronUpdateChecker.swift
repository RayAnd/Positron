// SPDX-License-Identifier: MIT
import Foundation

public struct PositronReleaseInfo: Codable, Sendable, Equatable, Identifiable {
    public let tagName: String
    public let versionString: String
    public let title: String
    public let releaseNotes: String
    public let htmlURL: URL
    public let publishedAt: Date?
    public let dmgAssetURL: URL?
    public let zipAssetURL: URL?

    public var id: String { tagName }

    public init(
        tagName: String,
        versionString: String,
        title: String,
        releaseNotes: String,
        htmlURL: URL,
        publishedAt: Date? = nil,
        dmgAssetURL: URL? = nil,
        zipAssetURL: URL? = nil
    ) {
        self.tagName = tagName
        self.versionString = versionString
        self.title = title
        self.releaseNotes = releaseNotes
        self.htmlURL = htmlURL
        self.publishedAt = publishedAt
        self.dmgAssetURL = dmgAssetURL
        self.zipAssetURL = zipAssetURL
    }
}

public enum PositronUpdateCheckResult: Sendable, Equatable {
    case updateAvailable(PositronReleaseInfo)
    case upToDate(currentVersion: String)
    case failed(String)
}

public enum PositronUpdateChecker {
    public static let defaultRepo = "RayAnd/Positron"
    public static let fallbackVersion = "2.1.1"

    public static var currentAppVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
            ?? Bundle.main.infoDictionary?["CFBundleVersion"] as? String
            ?? fallbackVersion
    }

    /// Compares two semver version strings (e.g. "2.2.0" vs "2.1.1", "v2.1.1" vs "2.1.0").
    /// Returns true if and only if "newer" is strictly newer than "current".
    public static func isVersion(_ newer: String, strictlyNewerThan current: String) -> Bool {
        let cleanNewer = cleanVersionString(newer)
        let cleanCurrent = cleanVersionString(current)
        guard cleanNewer != cleanCurrent else { return false }

        let nParts = cleanNewer.split(separator: ".").compactMap { Int($0) }
        let cParts = cleanCurrent.split(separator: ".").compactMap { Int($0) }
        let maxCount = max(nParts.count, cParts.count)

        for i in 0..<maxCount {
            let nVal = i < nParts.count ? nParts[i] : 0
            let cVal = i < cParts.count ? cParts[i] : 0
            if nVal > cVal { return true }
            if nVal < cVal { return false }
        }
        return false
    }

    public static func cleanVersionString(_ raw: String) -> String {
        var str = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if str.lowercased().hasPrefix("v") {
            str.removeFirst()
        }
        if let dashIdx = str.firstIndex(of: "-") {
            str = String(str[..<dashIdx])
        }
        return str
    }

    /// Checks whether an automatic background check should run based on the last check timestamp.
    public static func shouldCheckAutomatically(
        intervalHours: Double = 12.0,
        userDefaults: UserDefaults = .standard
    ) -> Bool {
        let lastKey = "PositronLastUpdateCheckDate"
        guard let last = userDefaults.object(forKey: lastKey) as? Date else {
            return true
        }
        return Date().timeIntervalSince(last) >= (intervalHours * 3600.0)
    }

    public static func recordUpdateCheck(userDefaults: UserDefaults = .standard) {
        userDefaults.set(Date(), forKey: "PositronLastUpdateCheckDate")
    }

    /// Queries the GitHub Releases API for the latest release with a privacy-preserving User-Agent.
    public static func checkForUpdates(
        currentVersion: String = currentAppVersion,
        repo: String = defaultRepo,
        timeout: TimeInterval = 6.0,
        session: URLSession = .shared
    ) async -> PositronUpdateCheckResult {
        guard let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest") else {
            return .failed("Invalid release endpoint URL.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        // Privacy-preserving User-Agent: includes only app version and Apple Silicon architecture
        request.setValue("Positron/\(currentVersion) (Macintosh; Apple Silicon)", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .failed("Invalid network response.")
            }
            guard http.statusCode == 200 else {
                return .failed("GitHub API returned status \(http.statusCode).")
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tagName = json["tag_name"] as? String,
                  let htmlURLString = json["html_url"] as? String,
                  let htmlURL = URL(string: htmlURLString) else {
                return .failed("Could not parse GitHub release metadata.")
            }

            let name = (json["name"] as? String) ?? tagName
            let body = (json["body"] as? String) ?? ""
            let publishedString = json["published_at"] as? String
            let publishedAt = publishedString.flatMap { ISO8601DateFormatter().date(from: $0) }

            var dmgURL: URL? = nil
            var zipURL: URL? = nil
            if let assets = json["assets"] as? [[String: Any]] {
                for asset in assets {
                    guard let assetName = asset["name"] as? String,
                          let downloadURLStr = asset["browser_download_url"] as? String,
                          let downloadURL = URL(string: downloadURLStr) else { continue }
                    if assetName.hasSuffix(".dmg") && dmgURL == nil {
                        dmgURL = downloadURL
                    } else if assetName.hasSuffix(".zip") && zipURL == nil {
                        zipURL = downloadURL
                    }
                }
            }

            let versionString = cleanVersionString(tagName)
            let release = PositronReleaseInfo(
                tagName: tagName,
                versionString: versionString,
                title: name,
                releaseNotes: body,
                htmlURL: htmlURL,
                publishedAt: publishedAt,
                dmgAssetURL: dmgURL,
                zipAssetURL: zipURL
            )

            recordUpdateCheck()

            if isVersion(versionString, strictlyNewerThan: currentVersion) {
                return .updateAvailable(release)
            } else {
                return .upToDate(currentVersion: currentVersion)
            }
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}
