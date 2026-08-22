import Foundation
import os.log

enum DiagnosticLevel: String, Sendable {
  case info
  case warning
  case error
}

struct DiagnosticEntry: Identifiable, Equatable, Sendable {
  let id: UUID
  let date: Date
  let level: DiagnosticLevel
  let category: String
  let message: String

  init(
    id: UUID = UUID(),
    date: Date = Date(),
    level: DiagnosticLevel,
    category: String,
    message: String
  ) {
    self.id = id
    self.date = date
    self.level = level
    self.category = category
    self.message = message
  }

  var line: String {
    "\(Self.timeFormatter.string(from: date)) [\(level.rawValue.uppercased())] \(category): \(message)"
  }

  private static let timeFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm:ss"
    return formatter
  }()
}

/// In-memory ring buffer plus Console.app output so Advanced can show detail.
final class DiagnosticLog: ObservableObject, @unchecked Sendable {
  static let shared = DiagnosticLog()
  static let maxEntries = 250

  @Published private(set) var entries: [DiagnosticEntry] = []

  private let lock = NSLock()
  private var storage: [DiagnosticEntry] = []
  private let logger = Logger(subsystem: "com.bingtaohu.AirPulse", category: "AirPulse")

  private init() {}

  func info(_ category: String, _ message: String) {
    append(level: .info, category: category, message: message)
  }

  func warning(_ category: String, _ message: String) {
    append(level: .warning, category: category, message: message)
  }

  func error(_ category: String, _ message: String) {
    append(level: .error, category: category, message: message)
  }

  func clear() {
    lock.lock()
    storage.removeAll()
    lock.unlock()
    publish([])
  }

  var textDump: String {
    lock.lock()
    let lines = storage.map(\.line)
    lock.unlock()
    return lines.joined(separator: "\n")
  }

  private func append(level: DiagnosticLevel, category: String, message: String) {
    let entry = DiagnosticEntry(level: level, category: category, message: message)
    switch level {
    case .info:
      logger.info("\(category, privacy: .public): \(message, privacy: .public)")
    case .warning:
      logger.warning("\(category, privacy: .public): \(message, privacy: .public)")
    case .error:
      logger.error("\(category, privacy: .public): \(message, privacy: .public)")
    }

    lock.lock()
    storage.append(entry)
    if storage.count > Self.maxEntries {
      storage.removeFirst(storage.count - Self.maxEntries)
    }
    let snapshot = storage
    lock.unlock()
    publish(snapshot)
  }

  private func publish(_ snapshot: [DiagnosticEntry]) {
    if Thread.isMainThread {
      entries = snapshot
    } else {
      DispatchQueue.main.async { self.entries = snapshot }
    }
  }
}
