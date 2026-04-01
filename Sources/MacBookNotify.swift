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

let ntfyToken: String? = {
    if let token = ProcessInfo.processInfo.environment["NTFY_TOKEN"], !token.isEmpty {
        return token
    }
    let tokenPath = NSString(string: "~/.config/macbook-notify/token").expandingTildeInPath
    if let token = try? String(contentsOfFile: tokenPath, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty {
        return token
    }
    return nil
}()

fputs("macbook-notify started with topic: \(topic), auth: \(ntfyToken != nil ? "yes" : "no")\n", stderr)

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
    if let token = ntfyToken {
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }

    let hostname = Host.current().localizedName ?? "Mac"
    let timestamp = ISO8601DateFormatter().string(from: Date())
    let body = "\(hostname) — \(timestamp)"
    request.httpBody = body.data(using: .utf8)

    URLSession.shared.dataTask(with: request) { _, response, error in
        if let error = error {
            fputs("ntfy error: \(error.localizedDescription)\n", stderr)
        } else if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            fputs("ntfy HTTP \(httpResponse.statusCode) sending \(status)\n", stderr)
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
    fputs("Executing remote lock...\n", stderr)
    let task = Process()
    task.launchPath = "/usr/bin/osascript"
    task.arguments = ["-e", "tell application \"System Events\" to keystroke \"q\" using {control down, command down}"]
    task.launch()
}

// MARK: - Poll ntfy for lock commands

var lastProcessedId: String = ""

func pollForCommands() {
    guard let url = URL(string: "https://ntfy.sh/\(topic)/json?poll=1&since=10s") else { return }
    var request = URLRequest(url: url)
    if let token = ntfyToken {
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
            // Skip messages from the daemon itself
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
