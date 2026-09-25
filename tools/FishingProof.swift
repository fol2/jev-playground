// Registered fishing source and evidence proof. Never captures or sends input.
import CryptoKit
import Foundation

/// The manifest's recordings: a list, as Python iterated it, and never empty (an emptied list would check nothing).
func recordings(_ manifest: JSON) throws -> [JSON] {
    guard let items = manifest.items, !items.isEmpty else { throw GateError("the shared-recording manifest lists no recordings") }
    return items
}

func fishingProof() throws -> String {
    for name in fishingCode.sorted() where name.hasSuffix(".sh") {
        try sh(["sh", "-n", name], timeout: 90, passthrough: true).checked("sh -n " + name)
    }
    let manifest = try JSON.parse(try String(contentsOf: root.appendingPathComponent(fishingDir + "evidence/shared-recordings.json"), encoding: .utf8))
    for item in try recordings(manifest) {
        guard let path = item["path"]?.string, !path.hasPrefix("/"), !path.split(separator: "/").contains(".."),
              path.hasPrefix("data/001_wow_fishing/") else {
            throw GateError("invalid shared recording path")
        }
        let content = try Data(contentsOf: root.appendingPathComponent(path))
        if !same(.int(content.count), item["bytes"]) || .string(sha256Hex(content)) != item["sha256"] {
            throw GateError("recording provenance mismatch: " + path)
        }
    }
    let evidence = root.appendingPathComponent(fishingDir + "evidence")
    guard let walk = FileManager.default.enumerator(at: evidence, includingPropertiesForKeys: nil) else {
        throw GateError("fishing evidence folder unreadable")
    }
    for case let url as URL in walk {
        switch url.pathExtension {
        case "json": _ = try JSON.parse(try String(contentsOf: url, encoding: .utf8))
        case "jsonl":
            for line in try String(contentsOf: url, encoding: .utf8).components(separatedBy: "\n")
            where !line.trimmingCharacters(in: .whitespaces).isEmpty {
                _ = try JSON.parse(line)
            }
        default: break
        }
    }
    // The scripts build and run native checks; build.sh compiles the helper and three tools.
    try sh(["sh", fishingDir + "test_core.sh"], timeout: 300, passthrough: true).checked("test_core.sh")
    try sh(["sh", fishingDir + "build.sh"], timeout: 300, passthrough: true).checked("build.sh")
    try sh(["sh", fishingDir + "setup_camera.sh", "--self-test"], timeout: 90, passthrough: true).checked("setup_camera.sh --self-test")
    try sh(["swiftc", "-parse-as-library", "-typecheck", fishingDir + "background.swift"], timeout: 90, passthrough: true)
        .checked("typecheck background.swift")
    let probe = fishingDir + "probes/background-click/"
    try sh(["swiftc", "-parse-as-library", "-typecheck"]
           + ["Adapter.swift", "NativeWindowServerPreparation.swift", "NativeBackgroundClickTransport.swift", "Probe.swift"].map { probe + $0 },
           timeout: 90, passthrough: true).checked("typecheck the background-click probe")
    try sh(["swiftc", "-parse-as-library", "-typecheck", "data/001_wow_fishing/pilot_20260921/recorder.swift"], timeout: 90, passthrough: true)
        .checked("typecheck the pilot recorder")
    return "Fishing source, retained-image regressions and shared recording checksums passed; zero live effects."
}
