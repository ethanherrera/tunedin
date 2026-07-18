import CryptoKit
import Foundation
import Security

enum NativeAuthNonce {
  private static let characters = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")

  static func random(length: Int = 32) throws -> String {
    precondition(length > 0)
    var bytes = [UInt8](repeating: 0, count: length)
    let status = bytes.withUnsafeMutableBytes { buffer in
      SecRandomCopyBytes(kSecRandomDefault, buffer.count, buffer.baseAddress!)
    }
    guard status == errSecSuccess else {
      throw NativeSocialSignInError.nonceGenerationFailed
    }
    return String(bytes.map { characters[Int($0) % characters.count] })
  }

  static func hashed(_ nonce: String) -> String {
    SHA256.hash(data: Data(nonce.utf8)).map { String(format: "%02x", $0) }.joined()
  }
}
