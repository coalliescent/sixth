import Foundation
import CommonCrypto

enum PandoraAPITests {
    static func runAll() {
        testEncryptDecryptRoundTrip()
        testRequestBodyEncryption()
        testSyncTimeDecryption()
        testPartnerConfig()
        testURLConstruction()
    }

    static func testEncryptDecryptRoundTrip() {
        // Simulate what the API does: encrypt with encrypt key, verify we can decrypt with same key
        let body = "{\"username\":\"test\",\"password\":\"pass123\",\"syncTime\":1234567}"
        guard let encrypted = BlowfishCrypto.encrypt(body, key: PandoraPartner.encryptKey) else {
            TestRunner.assert(false, "API body encrypt")
            return
        }
        guard let decrypted = BlowfishCrypto.decrypt(encrypted, key: PandoraPartner.encryptKey) else {
            TestRunner.assert(false, "API body decrypt")
            return
        }
        TestRunner.assertEqual(decrypted, body, "API body round-trip")
    }

    static func testRequestBodyEncryption() {
        // Verify encrypted output is hex-only and reasonable length
        let body = "{\"test\":true}"
        guard let encrypted = BlowfishCrypto.encrypt(body, key: PandoraPartner.encryptKey) else {
            TestRunner.assert(false, "request body encryption")
            return
        }
        let isHex = encrypted.allSatisfy { "0123456789abcdef".contains($0) }
        TestRunner.assert(isHex, "encrypted body is hex")
        // Encrypted output should be longer than input (hex encoding doubles, plus padding)
        TestRunner.assert(encrypted.count >= body.count, "encrypted body length reasonable")
    }

    static func testSyncTimeDecryption() {
        // Create a fake sync time: 4 random bytes + ASCII time digits + null padding to 8-byte boundary
        // Then encrypt with decrypt key (simulating what Pandora server sends)
        // Then verify our decryptSyncTime can parse it
        let timeValue = "1709000000"
        var payload = Data([0x42, 0x42, 0x42, 0x42]) // 4 prefix bytes
        payload.append(timeValue.data(using: .utf8)!)
        // Pad to 16 bytes (next 8-byte boundary)
        while payload.count % 8 != 0 {
            payload.append(0)
        }

        // Encrypt with the decrypt key (Pandora sends encrypted with the key we use to decrypt)
        let key = PandoraPartner.decryptKey
        guard let keyData = key.data(using: .utf8) else {
            TestRunner.assert(false, "sync time key encoding")
            return
        }

        var outLength = 0
        let bufferSize = payload.count + kCCBlockSizeBlowfish
        var buffer = Data(count: bufferSize)

        let status = buffer.withUnsafeMutableBytes { bufferPtr in
            payload.withUnsafeBytes { dataPtr in
                keyData.withUnsafeBytes { keyPtr in
                    CCCrypt(
                        CCOperation(kCCEncrypt),
                        CCAlgorithm(kCCAlgorithmBlowfish),
                        CCOptions(kCCOptionECBMode),
                        keyPtr.baseAddress, keyData.count,
                        nil,
                        dataPtr.baseAddress, payload.count,
                        bufferPtr.baseAddress, bufferSize,
                        &outLength
                    )
                }
            }
        }

        guard status == kCCSuccess else {
            TestRunner.assert(false, "sync time test encrypt failed (status \(status))")
            return
        }

        let hexEncrypted = buffer.prefix(outLength).hexEncodedString()
        let result = BlowfishCrypto.decryptSyncTime(hexEncrypted, key: key)
        TestRunner.assertEqual(result ?? 0, 1709000000, "sync time decryption")
    }

    static func testPartnerConfig() {
        TestRunner.assertEqual(PandoraPartner.username, "android", "partner username")
        TestRunner.assertEqual(PandoraPartner.deviceModel, "android-generic", "partner device")
        TestRunner.assert(!PandoraPartner.encryptKey.isEmpty, "encrypt key not empty")
        TestRunner.assert(!PandoraPartner.decryptKey.isEmpty, "decrypt key not empty")
        TestRunner.assert(PandoraPartner.baseURL.hasPrefix("https://"), "base URL is HTTPS")
    }

    static func testURLConstruction() {
        var components = URLComponents(string: PandoraPartner.baseURL)!
        components.queryItems = [URLQueryItem(name: "method", value: "auth.partnerLogin")]
        let url = components.url!
        TestRunner.assert(url.absoluteString.contains("method=auth.partnerLogin"), "URL has method param")
        TestRunner.assert(url.absoluteString.contains("tuner.pandora.com"), "URL has pandora host")
    }
}
