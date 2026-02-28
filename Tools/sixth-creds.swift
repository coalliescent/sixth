import Foundation

let credDir = NSString(string: "~/.config/sixth").expandingTildeInPath
let credFile = "\(credDir)/test-credentials.json"

func store(username: String, password: String) {
    let fm = FileManager.default
    if !fm.fileExists(atPath: credDir) {
        do {
            try fm.createDirectory(atPath: credDir, withIntermediateDirectories: true)
        } catch {
            fputs("Error creating directory: \(error)\n", stderr)
            exit(1)
        }
    }

    let payload: [String: String] = ["username": username, "password": password]
    do {
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        let url = URL(fileURLWithPath: credFile)
        try data.write(to: url)
        // Set file permissions to 0600 (owner read/write only)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: credFile)
        print("Credentials saved to \(credFile)")
    } catch {
        fputs("Error saving credentials: \(error)\n", stderr)
        exit(1)
    }
}

func load() {
    let url = URL(fileURLWithPath: credFile)
    guard FileManager.default.fileExists(atPath: credFile) else {
        fputs("No credentials found at \(credFile)\n", stderr)
        fputs("Run: sixth-creds store <username> <password>\n", stderr)
        exit(1)
    }
    do {
        let data = try Data(contentsOf: url)
        // Validate it's proper JSON before printing
        _ = try JSONSerialization.jsonObject(with: data)
        print(String(data: data, encoding: .utf8)!)
    } catch {
        fputs("Error reading credentials: \(error)\n", stderr)
        exit(1)
    }
}

func delete() {
    let fm = FileManager.default
    guard fm.fileExists(atPath: credFile) else {
        print("No credentials file to delete.")
        return
    }
    do {
        try fm.removeItem(atPath: credFile)
        print("Deleted \(credFile)")
    } catch {
        fputs("Error deleting credentials: \(error)\n", stderr)
        exit(1)
    }
}

func usage() -> Never {
    fputs("""
    Usage:
      sixth-creds store <username> <password>
      sixth-creds load
      sixth-creds delete

    """, stderr)
    exit(1)
}

// MARK: - Main

let args = CommandLine.arguments.dropFirst() // drop executable name
guard let command = args.first else { usage() }

switch command {
case "store":
    let rest = Array(args.dropFirst())
    guard rest.count == 2 else {
        fputs("Error: store requires <username> <password>\n", stderr)
        usage()
    }
    store(username: rest[0], password: rest[1])
case "load":
    load()
case "delete":
    delete()
default:
    fputs("Unknown command: \(command)\n", stderr)
    usage()
}
