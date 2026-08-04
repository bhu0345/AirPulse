import Foundation

@objc public protocol AirPulseHelperProtocol: NSObjectProtocol {
  func ping(reply: @escaping (String) -> Void)
  func openSMC(reply: @escaping (Bool, String?) -> Void)
  func warmupManual(reply: @escaping (Bool, String?) -> Void)
  func listFans(reply: @escaping ([Data]?, String?) -> Void)
  func listTemperatures(reply: @escaping ([Data]?, String?) -> Void)
  func applyPreset(_ rawPreset: String, reply: @escaping (Bool, String?) -> Void)
  func setLinkedFraction(_ fraction: Double, reply: @escaping (Bool, String?) -> Void)
  func setFanRPM(_ fanIndex: UInt, rpm: Float, reply: @escaping (Bool, String?) -> Void)
  func restoreAuto(reply: @escaping (Bool, String?) -> Void)
  func hardwareInfo(reply: @escaping ([String: String]) -> Void)
}

public enum AirPulseCoding {
  public static let encoder = JSONEncoder()
  public static let decoder = JSONDecoder()

  public static func encode<T: Encodable>(_ value: T) -> Data? {
    try? encoder.encode(value)
  }

  public static func decode<T: Decodable>(_ type: T.Type, from data: Data) -> T? {
    try? decoder.decode(type, from: data)
  }
}
