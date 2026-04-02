import Foundation

// Simple test runner

@main
struct TestRunner {
    static var totalTests = 0
    static var passedTests = 0
    static var failedTests: [(String, String)] = []

    static func assert(_ condition: Bool, _ name: String, file: String = #file, line: Int = #line) {
        totalTests += 1
        if condition {
            passedTests += 1
            print("  ✓ \(name)")
        } else {
            failedTests.append((name, "\(file):\(line)"))
            print("  ✗ \(name) (\(file):\(line))")
        }
    }

    static func assertEqual<T: Equatable>(_ a: T, _ b: T, _ name: String, file: String = #file, line: Int = #line) {
        totalTests += 1
        if a == b {
            passedTests += 1
            print("  ✓ \(name)")
        } else {
            failedTests.append((name, "\(file):\(line)"))
            print("  ✗ \(name) — expected \(b), got \(a) (\(file):\(line))")
        }
    }

    static func main() {
        print("Running Sixth tests...\n")

        print("BlowfishCrypto Tests:")
        BlowfishCryptoTests.runAll()

        print("\nModels Tests:")
        ModelsTests.runAll()

        print("\nPandoraAPI Tests:")
        PandoraAPITests.runAll()

        print("\nTrackHistory Tests:")
        TrackHistoryTests.runAll()

        print("\nLyricsProvider Tests:")
        LyricsProviderTests.runAll()

        print("\nIntegration Tests:")
        IntegrationTests.runAll()

        print("\n---")
        print("\(passedTests)/\(totalTests) tests passed")
        if !failedTests.isEmpty {
            print("FAILURES:")
            for (name, loc) in failedTests {
                print("  - \(name) at \(loc)")
            }
            exit(1)
        } else {
            print("All tests passed!")
        }
    }
}
