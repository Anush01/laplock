import Foundation
import ApplicationServices

// MARK: - Configuration

func resolveConfig(_ envKey: String, filePath: String, required: Bool = true) -> String? {
    if let val = ProcessInfo.processInfo.environment[envKey], !val.isEmpty {
        return val
    }
    let path = NSString(string: filePath).expandingTildeInPath
    if let val = try? String(contentsOfFile: path, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines), !val.isEmpty {
        return val
    }
    if required {
        fputs("ERROR: \(envKey) not configured. Set \(envKey) env var or write to \(filePath)\n", stderr)
        exit(1)
    }
    return nil
}

let serverURL = resolveConfig("SERVER_URL", filePath: "~/.config/macbook-notify/server_url")!
let topic = resolveConfig("TOPIC", filePath: "~/.config/macbook-notify/topic")!
let authToken: String? = resolveConfig("AUTH_TOKEN", filePath: "~/.config/macbook-notify/token", required: false)

fputs("macbook-notify started — server: \(serverURL), topic: \(topic), auth: \(authToken != nil ? "yes" : "no")\n", stderr)

// Check Accessibility permissions (needed for remote lock via osascript)
if AXIsProcessTrusted() {
    fputs("Accessibility: trusted\n", stderr)
} else {
    fputs("WARNING: Accessibility not granted. Remote lock will fail.\n", stderr)
    fputs("Grant access: System Settings > Privacy & Security > Accessibility > add this binary\n", stderr)
    let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
    _ = AXIsProcessTrustedWithOptions(opts)
}

// MARK: - Send status

func sendStatus(_ status: String) {
    guard let url = URL(string: "\(serverURL)/publish/\(topic)") else { return }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("MacBook: \(status)", forHTTPHeaderField: "Title")

    let tag: String
    switch status {
    case "locked": tag = "lock"
    case "unlocked": tag = "unlock"
    default: tag = "computer"
    }
    request.setValue(tag, forHTTPHeaderField: "Tags")
    if let token = authToken {
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }

    let hostname = Host.current().localizedName ?? "Mac"
    let timestamp = ISO8601DateFormatter().string(from: Date())
    let body = "\(hostname) — \(timestamp)"
    request.httpBody = body.data(using: .utf8)

    URLSession.shared.dataTask(with: request) { _, response, error in
        if let error = error {
            fputs("Server error: \(error.localizedDescription)\n", stderr)
        } else if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
            fputs("Server HTTP \(httpResponse.statusCode) sending \(status)\n", stderr)
        } else {
            fputs("Sent status: \(status)\n", stderr)
        }
    }.resume()
}

// MARK: - Observe lock/unlock

let dnc = DistributedNotificationCenter.default()

dnc.addObserver(forName: NSNotification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { _ in
    sendStatus("locked")
}

dnc.addObserver(forName: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { _ in
    sendStatus("unlocked")
}

// MARK: - Remote lock

func lockScreen() {
    if !AXIsProcessTrusted() {
        fputs("ERROR: Cannot lock — Accessibility not granted. Add this binary in System Settings > Privacy & Security > Accessibility\n", stderr)
        return
    }
    fputs("Executing remote lock...\n", stderr)
    let task = Process()
    let errPipe = Pipe()
    task.standardError = errPipe
    task.launchPath = "/usr/bin/osascript"
    task.arguments = ["-e", "tell application \"System Events\" to keystroke \"q\" using {control down, command down}"]
    task.launch()
    task.waitUntilExit()
    if task.terminationStatus != 0 {
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        let errStr = String(data: errData, encoding: .utf8) ?? "unknown error"
        fputs("Lock failed (exit \(task.terminationStatus)): \(errStr)\n", stderr)
    }
}

// MARK: - Poll for lock commands

var lastProcessedId: String = ""

func pollForCommands() {
    guard let url = URL(string: "\(serverURL)/poll/\(topic)?since=10s") else { return }
    var request = URLRequest(url: url)
    if let token = authToken {
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }
    URLSession.shared.dataTask(with: request) { data, _, error in
        guard let data = data, error == nil,
              let text = String(data: data, encoding: .utf8) else { return }

        let lines = text.split(separator: "\n")
        for line in lines {
            guard let msgData = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: msgData) as? [String: Any],
                  let event = json["event"] as? String, event == "message",
                  let id = json["id"] as? String, id != lastProcessedId,
                  let tags = json["tags"] as? [String], tags.contains("cmd_lock") else {
                continue
            }
            if let title = json["title"] as? String, title.hasPrefix("MacBook:") {
                continue
            }
            lastProcessedId = id
            fputs("Received remote lock command (id: \(id))\n", stderr)
            DispatchQueue.main.async {
                lockScreen()
            }
        }
    }.resume()
}

// MARK: - Startup

sendStatus("started")

Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
    pollForCommands()
}

RunLoop.main.run()
