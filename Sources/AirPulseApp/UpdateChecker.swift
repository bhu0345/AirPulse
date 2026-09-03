import AppKit
import Combine
import Foundation

/// Checks GitHub Releases and installs a newer DMG in place, then relaunches.
@MainActor
final class UpdateChecker: ObservableObject {
  enum State: Equatable {
    case idle
    case checking
    case upToDate(current: String)
    case ahead(current: String, latest: String)
    case available(latest: String, dmgURL: URL, notesURL: URL)
    case downloading(latest: String)
    case installing(latest: String)
    case restarting(latest: String)
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
    return trimmed.isEmpty ? "1.0.4" : trimmed
  }

  func check() {
    state = .checking
    Task { await performCheck() }
  }

  func installUpdate() {
    guard case .available(let latest, let dmgURL, _) = state else { return }
    state = .downloading(latest: latest)
    Task { await performInstall(latest: latest, dmgURL: dmgURL) }
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

  private func performInstall(latest: String, dmgURL: URL) async {
    do {
      let dmg = try await downloadDMG(from: dmgURL, latest: latest)
      state = .installing(latest: latest)
      let staged = try extractApp(from: dmg)
      let dest = Self.installDestination()
      try scheduleReplace(staged: staged, destination: dest)
      state = .restarting(latest: latest)
      NSApp.terminate(nil)
    } catch {
      NSWorkspace.shared.open(dmgURL)
      state = .failed(error.localizedDescription)
    }
  }

  private func downloadDMG(from url: URL, latest: String) async throws -> URL {
    var request = URLRequest(url: url)
    request.setValue(
      "AirPulse/\(Self.currentVersion) (https://github.com/bhu0345/AirPulse)",
      forHTTPHeaderField: "User-Agent"
    )
    request.timeoutInterval = 120

    let (tempURL, response) = try await URLSession.shared.download(for: request)
    if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
      throw UpdateError.message("HTTP \(http.statusCode)")
    }
    let size = (try? FileManager.default.attributesOfItem(atPath: tempURL.path)[.size] as? NSNumber)?
      .intValue ?? 0
    if size < 100_000 {
      throw UpdateError.message("Download was too small to be an installer")
    }

    let work = try makeWorkDirectory()
    let dmg = work.appendingPathComponent("AirPulse-\(latest).dmg")
    if FileManager.default.fileExists(atPath: dmg.path) {
      try FileManager.default.removeItem(at: dmg)
    }
    try FileManager.default.moveItem(at: tempURL, to: dmg)
    _ = try? run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", dmg.path])
    return dmg
  }

  private func extractApp(from dmg: URL) throws -> URL {
    let work = dmg.deletingLastPathComponent()
    let mount = work.appendingPathComponent("mnt")
    try FileManager.default.createDirectory(at: mount, withIntermediateDirectories: true)

    do {
      _ = try run(
        "/usr/bin/hdiutil",
        ["attach", "-nobrowse", "-readonly", "-mountpoint", mount.path, dmg.path]
      )
    } catch {
      throw UpdateError.message("Could not open installer")
    }

    defer {
      _ = try? run("/usr/bin/hdiutil", ["detach", mount.path, "-quiet", "-force"])
    }

    let mountedApp = mount.appendingPathComponent("AirPulse.app")
    guard FileManager.default.fileExists(atPath: mountedApp.path) else {
      throw UpdateError.message("Installer did not contain AirPulse.app")
    }

    let staged = work.appendingPathComponent("AirPulse.app")
    if FileManager.default.fileExists(atPath: staged.path) {
      try FileManager.default.removeItem(at: staged)
    }
    _ = try run("/usr/bin/ditto", [mountedApp.path, staged.path])
    return staged
  }

  private func scheduleReplace(staged: URL, destination: URL) throws {
    let work = staged.deletingLastPathComponent()
    let script = work.appendingPathComponent("apply.sh")
    let body = """
    #!/bin/bash
    set -euo pipefail
    PID="$1"
    SRC="$2"
    DEST="$3"
    WORK="$4"
    i=0
    while kill -0 "$PID" 2>/dev/null; do
      sleep 0.2
      i=$((i + 1))
      if [ "$i" -gt 75 ]; then
        break
      fi
    done
    sleep 0.4
    OLD="${DEST}.old"
    rm -rf "$OLD"
    if [ -d "$DEST" ]; then
      mv "$DEST" "$OLD"
    fi
    if /usr/bin/ditto "$SRC" "$DEST"; then
      rm -rf "$OLD"
      /usr/bin/xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true
      /usr/bin/open "$DEST"
    else
      if [ -d "$OLD" ]; then
        mv "$OLD" "$DEST"
      fi
      exit 1
    fi
    rm -rf "$WORK"
    """
    try body.write(to: script, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)

    let pid = String(ProcessInfo.processInfo.processIdentifier)
    let launcher = Process()
    launcher.executableURL = URL(fileURLWithPath: "/bin/bash")
    launcher.arguments = [
      "-c",
      "nohup /bin/bash \"$1\" \"$2\" \"$3\" \"$4\" \"$5\" >/dev/null 2>&1 &",
      "airpulse-update",
      script.path,
      pid,
      staged.path,
      destination.path,
      work.path,
    ]
    launcher.standardInput = FileHandle.nullDevice
    launcher.standardOutput = FileHandle.nullDevice
    launcher.standardError = FileHandle.nullDevice
    try launcher.run()
    launcher.waitUntilExit()
    if launcher.terminationStatus != 0 {
      throw UpdateError.message("Could not start installer")
    }
  }

  static func installDestination() -> URL {
    let applications = URL(fileURLWithPath: "/Applications/AirPulse.app")
    if FileManager.default.fileExists(atPath: applications.path) {
      return applications
    }
    return Bundle.main.bundleURL
  }

  private func makeWorkDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("AirPulseUpdate-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  @discardableResult
  private func run(_ launchPath: String, _ arguments: [String]) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: launchPath)
    process.arguments = arguments
    let out = Pipe()
    let err = Pipe()
    process.standardOutput = out
    process.standardError = err
    try process.run()
    process.waitUntilExit()
    let stdout = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    if process.terminationStatus == 0 {
      return stdout
    }
    let stderr = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    throw UpdateError.message(stderr.isEmpty ? stdout : stderr)
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

private enum UpdateError: LocalizedError {
  case message(String)

  var errorDescription: String? {
    switch self {
    case .message(let text):
      let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
      return trimmed.isEmpty ? "Update failed" : trimmed
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
