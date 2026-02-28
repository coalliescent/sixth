import Foundation
import CommonCrypto

enum BlowfishCrypto {
    // MARK: - Encrypt

    /// Encrypt data with Blowfish ECB, null-byte padding, return hex string
    static func encrypt(_ plaintext: String, key: String) -> String? {
        guard let data = plaintext.data(using: .utf8),
              let keyData = key.data(using: .utf8) else { return nil }

        // Pad to 8-byte boundary with null bytes
        let padded = padNullBytes(data)

        var outLength = 0
        let bufferSize = padded.count + kCCBlockSizeBlowfish
        var buffer = Data(count: bufferSize)

        let status = buffer.withUnsafeMutableBytes { bufferPtr in
            padded.withUnsafeBytes { dataPtr in
                keyData.withUnsafeBytes { keyPtr in
                    CCCrypt(
                        CCOperation(kCCEncrypt),
                        CCAlgorithm(kCCAlgorithmBlowfish),
                        CCOptions(kCCOptionECBMode),
                        keyPtr.baseAddress, keyData.count,
                        nil, // no IV for ECB
                        dataPtr.baseAddress, padded.count,
                        bufferPtr.baseAddress, bufferSize,
                        &outLength
                    )
                }
            }
        }

        guard status == kCCSuccess else { return nil }
        return buffer.prefix(outLength).hexEncodedString()
    }

    // MARK: - Decrypt

    /// Decrypt hex-encoded Blowfish ECB data
    static func decrypt(_ hexString: String, key: String) -> String? {
        guard let data = Data(hexString: hexString),
              let keyData = key.data(using: .utf8) else { return nil }

        var outLength = 0
        let bufferSize = data.count + kCCBlockSizeBlowfish
        var buffer = Data(count: bufferSize)

        let status = buffer.withUnsafeMutableBytes { bufferPtr in
            data.withUnsafeBytes { dataPtr in
                keyData.withUnsafeBytes { keyPtr in
                    CCCrypt(
                        CCOperation(kCCDecrypt),
                        CCAlgorithm(kCCAlgorithmBlowfish),
                        CCOptions(kCCOptionECBMode),
                        keyPtr.baseAddress, keyData.count,
                        nil,
                        dataPtr.baseAddress, data.count,
                        bufferPtr.baseAddress, bufferSize,
                        &outLength
                    )
                }
            }
        }

        guard status == kCCSuccess else { return nil }

        // Remove null-byte padding
        let resultData = buffer.prefix(outLength)
        let trimmed = resultData.prefix(while: { $0 != 0 })
        return String(data: Data(trimmed), encoding: .utf8)
    }

    // MARK: - Sync Time

    /// Decrypt sync time from partner login response.
    /// After decryption, skip first 4 bytes, parse remaining as integer.
    static func decryptSyncTime(_ encrypted: String, key: String) -> Int? {
        guard let data = Data(hexString: encrypted),
              let keyData = key.data(using: .utf8) else { return nil }

        var outLength = 0
        let bufferSize = data.count + kCCBlockSizeBlowfish
        var buffer = Data(count: bufferSize)

        let status = buffer.withUnsafeMutableBytes { bufferPtr in
            data.withUnsafeBytes { dataPtr in
                keyData.withUnsafeBytes { keyPtr in
                    CCCrypt(
                        CCOperation(kCCDecrypt),
                        CCAlgorithm(kCCAlgorithmBlowfish),
                        CCOptions(kCCOptionECBMode),
                        keyPtr.baseAddress, keyData.count,
                        nil,
                        dataPtr.baseAddress, data.count,
                        bufferPtr.baseAddress, bufferSize,
                        &outLength
                    )
                }
            }
        }

        guard status == kCCSuccess else { return nil }

        let resultData = buffer.prefix(outLength)
        guard resultData.count > 4 else { return nil }

        // Skip first 4 bytes, take rest as ASCII digits (trim null bytes)
        let timeBytes = resultData.dropFirst(4)
        let trimmed = timeBytes.prefix(while: { $0 >= 0x30 && $0 <= 0x39 }) // ASCII '0'-'9'
        guard let timeStr = String(data: Data(trimmed), encoding: .utf8) else { return nil }
        return Int(timeStr)
    }

    // MARK: - Helpers

    /// Pad data to 8-byte boundary with null bytes
    private static func padNullBytes(_ data: Data) -> Data {
        let remainder = data.count % 8
        if remainder == 0 { return data }
        var padded = data
        padded.append(contentsOf: [UInt8](repeating: 0, count: 8 - remainder))
        return padded
    }
}

// MARK: - Data Extensions

extension Data {
    /// Convert data to lowercase hex string
    func hexEncodedString() -> String {
        return map { String(format: "%02x", $0) }.joined()
    }

    /// Initialize from hex string
    init?(hexString: String) {
        let hex = hexString.lowercased()
        guard hex.count % 2 == 0 else { return nil }
        var data = Data(capacity: hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let nextIndex = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<nextIndex], radix: 16) else { return nil }
            data.append(byte)
            index = nextIndex
        }
        self = data
    }
}
