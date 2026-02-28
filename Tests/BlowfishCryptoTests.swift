import Foundation

enum BlowfishCryptoTests {
    static func runAll() {
        testRoundTrip()
        testHexEncoding()
        testPaddingHandling()
        testDecryptWithPandoraKey()
        testEncryptProducesHex()
        testEmptyStringHandling()
    }

    static func testRoundTrip() {
        let key = "testkey!"
        let original = "Hello, Pandora!"
        guard let encrypted = BlowfishCrypto.encrypt(original, key: key) else {
            TestRunner.assert(false, "round-trip encrypt")
            return
        }
        guard let decrypted = BlowfishCrypto.decrypt(encrypted, key: key) else {
            TestRunner.assert(false, "round-trip decrypt")
            return
        }
        TestRunner.assertEqual(decrypted, original, "round-trip encrypt/decrypt")
    }

    static func testHexEncoding() {
        let data = Data([0xDE, 0xAD, 0xBE, 0xEF])
        TestRunner.assertEqual(data.hexEncodedString(), "deadbeef", "hex encoding")

        let parsed = Data(hexString: "deadbeef")
        TestRunner.assertEqual(parsed, data, "hex decoding")
    }

    static func testPaddingHandling() {
        // Test strings of various lengths to verify null-byte padding works
        let key = "padtest1"
        for len in [1, 7, 8, 9, 15, 16] {
            let original = String(repeating: "A", count: len)
            guard let encrypted = BlowfishCrypto.encrypt(original, key: key),
                  let decrypted = BlowfishCrypto.decrypt(encrypted, key: key) else {
                TestRunner.assert(false, "padding len=\(len)")
                continue
            }
            TestRunner.assertEqual(decrypted, original, "padding len=\(len)")
        }
    }

    static func testDecryptWithPandoraKey() {
        // Encrypt with Pandora encrypt key, decrypt with decrypt key won't match (different keys)
        // But encrypt then decrypt with same key should work
        let key = PandoraPartner.encryptKey
        let original = "{\"test\":true}"
        guard let encrypted = BlowfishCrypto.encrypt(original, key: key),
              let decrypted = BlowfishCrypto.decrypt(encrypted, key: key) else {
            TestRunner.assert(false, "pandora key encrypt/decrypt")
            return
        }
        TestRunner.assertEqual(decrypted, original, "pandora key round-trip")
    }

    static func testEncryptProducesHex() {
        let key = "testkey!"
        guard let encrypted = BlowfishCrypto.encrypt("test", key: key) else {
            TestRunner.assert(false, "encrypt produces hex")
            return
        }
        // Should be all hex characters
        let isHex = encrypted.allSatisfy { "0123456789abcdef".contains($0) }
        TestRunner.assert(isHex, "encrypt output is hex")
        // Should be even length (hex pairs)
        TestRunner.assert(encrypted.count % 2 == 0, "encrypt output even length")
    }

    static func testEmptyStringHandling() {
        let key = "testkey!"
        // Empty data should still encrypt (8 null bytes of padding)
        let encrypted = BlowfishCrypto.encrypt("", key: key)
        TestRunner.assert(encrypted != nil, "empty string encrypts")
    }
}
