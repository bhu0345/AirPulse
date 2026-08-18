import AppKit
import Combine
import Foundation

/// Checks GitHub Releases and, if a newer DMG exists, downloads it so the user
/// can replace the app in Applications.
@MainActor
final class UpdateChecker: ObservableObject {
  enum State: Equatable {
    case idle
    case checking
    case upToDate(current: String)
    case ahead(current: String, latest: String)
    case available(latest: String, dmgURL: URL, notesURL: URL)
    case downloading(latest: String)
    case installed(latest: String)
    case failed(String)
  }

  static let repoAPI =
    URL(string: "https://api.github.com/repos/bhu0345/AirPulse/releases/latest")!
  static let releasesPage =
    URL(string: "https://github.com/bhu0345/AirPulse/releases")!

  @Published var state: State = .idle

  static var currentVersion: String {
    let bundle = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    let trimmed = bundle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return trimmed.isEmpty ? "1.0.1" : trimmed
  }

  func check() {
    state = .checking
    Task { await performCheck() }
  }

  func downloadUpdate() {
    guard case .available(let latest, let dmgURL, _) = state else { return }
    state = .downloading(latest: latest)
    Task { await performDownload(latest: latest, dmgURL: dmgURL) }
  }

  func openReleaseNotes() {
    let url: URL
    switch state {
    case .available(_, _, let notesURL):
      url = notesURL
    default:
      url = Self.releasesPage
    }
    NSWorkspace.shared.open(url)
  }

  private func performCheck() async {
    var request = URLRequest(url: Self.repoAPI)
    request.setValue(
      "AirPulse/\(Self.currentVersion) (https://github.com/bhu0345/AirPulse)",
      forHTTPHeaderField: "User-Agent"
    )
    request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
    request.timeoutInterval = 15

    do {
      let (data, response) = try await URLSession.shared.data(for: request)
      if let http = response as? HTTPURLResponse, http.statusCode != 200 {
        state = .failed("HTTP \(http.statusCode)")
        return
      }
      let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
      let latest = release.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
      let current = Self.currentVersion
      if Self.isVersion(latest, newerThan: current) {
        let notes = URL(string: release.htmlURL) ?? Self.releasesPage
        let dmg = release.assets.first { $0.name.lowercased().hasSuffix(".dmg") }
          .flatMap { URL(string: $0.browserDownloadURL) }
        if let dmg {
          state = .available(latest: latest, dmgURL: dmg, notesURL: notes)
        } else {
          state = .available(latest: latest, dmgURL: notes, notesURL: notes)
        }
      } else if Self.isVersion(current, newerThan: latest) {
        state = .ahead(current: current, latest: latest)
      } else {
        state = .upToDate(current: current)
      }
    } catch {
      state = .failed(error.localizedDescription)
    }
  }

  private func performDownload(latest: String, dmgURL: URL) async {
    var request = URLRequest(url: dmgURL)
    request.setValue(
      "AirPulse/\(Self.currentVersion) (https://github.com/bhu0345/AirPulse)",
      forHTTPHeaderField: "User-Agent"
    )
    request.timeoutInterval = 120

    do {
      let (tempURL, response) = try await URLSession.shared.download(for: request)
      if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
        NSWorkspace.shared.open(dmgURL)
        state = .available(latest: latest, dmgURL: dmgURL, notesURL: Self.releasesPage)
        return
      }

      let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        ?? FileManager.default.temporaryDirectory
      let dest = downloads.appendingPathComponent("AirPulse-\(latest).dmg")
      if FileManager.default.fileExists(atPath: dest.path) {
        try FileManager.default.removeItem(at: dest)
      }
      try FileManager.default.moveItem(at: tempURL, to: dest)
      NSWorkspace.shared.open(dest)
      state = .installed(latest: latest)
    } catch {
      NSWorkspace.shared.open(dmgURL)
      state = .failed(error.localizedDescription)
    }
  }

  static func isVersion(_ lhs: String, newerThan rhs: String) -> Bool {
    let a = numericParts(lhs)
    let b = numericParts(rhs)
    let n = max(a.count, b.count)
    for i in 0..<n {
      let x = i < a.count ? a[i] : 0
      let y = i < b.count ? b[i] : 0
      if x != y { return x > y }
    }
    return false
  }

  private static func numericParts(_ version: String) -> [Int] {
    version.split(separator: ".").compactMap { part in
      Int(part.prefix(while: { $0.isNumber }))
    }
  }
}

private struct GitHubRelease: Decodable {
  let tagName: String
  let htmlURL: String
  let assets: [Asset]

  struct Asset: Decodable {
    let name: String
    let browserDownloadURL: String

    enum CodingKeys: String, CodingKey {
      case name
      case browserDownloadURL = "browser_download_url"
    }
  }

  enum CodingKeys: String, CodingKey {
    case tagName = "tag_name"
    case htmlURL = "html_url"
    case assets
  }
}
