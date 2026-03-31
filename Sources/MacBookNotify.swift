import Foundation

// MARK: - Configuration

func resolveTopic() -> String {
    if let topic = ProcessInfo.processInfo.environment["NTFY_TOPIC"], !topic.isEmpty {
        return topic
    }
    let configPath = NSString(string: "~/.config/macbook-notify/topic").expandingTildeInPath
    if let topic = try? String(contentsOfFile: configPath, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines), !topic.isEmpty {
        return topic
    }
    fputs("ERROR: No ntfy topic configured. Set NTFY_TOPIC env var or write topic to ~/.config/macbook-notify/topic\n", stderr)
    exit(1)
}

let topic = resolveTopic()
fputs("macbook-notify started with topic: \(topic)\n", stderr)

// MARK: - Send status to ntfy.sh

func sendStatus(_ status: String) {
    guard let url = URL(string: "https://ntfy.sh/\(topic)") else { return }
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

    let hostname = Host.current().localizedName ?? "Mac"
    let timestamp = ISO8601DateFormatter().string(from: Date())
    let body = "\(hostname) — \(timestamp)"
    request.httpBody = body.data(using: .utf8)

    URLSession.shared.dataTask(with: request) { _, _, error in
        if let error = error {
            fputs("ntfy error: \(error.localizedDescription)\n", stderr)
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

// MARK: - Startup

sendStatus("started")
RunLoop.main.run()
