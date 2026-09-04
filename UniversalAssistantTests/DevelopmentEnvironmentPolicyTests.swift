import Foundation
import Testing

@Suite("Development environment policy")
struct DevelopmentEnvironmentPolicyTests {
    private var root: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    }

    @Test func developmentInfrastructureIsNotAnApplicationRuntimeDependency() throws {
        let appRoot = root.appendingPathComponent("UniversalAssistant")
        let enumerator = try #require(FileManager.default.enumerator(at: appRoot, includingPropertiesForKeys: nil))
        let forbidden = ["macincloud", "remote-control", "id_rsa", "id_ed25519"]
        for case let file as URL in enumerator where file.pathExtension == "swift" {
            let source = try String(contentsOf: file, encoding: .utf8).lowercased()
            for token in forbidden {
                #expect(!source.contains(token), "Development-only token in runtime source: \(token) at \(file.lastPathComponent)")
            }
            if source.contains("178.105.32.46") {
                #expect(file.lastPathComponent == "PhysicalDiagnosticDelivery.swift")
                #expect(source.contains("isinternaltestflight"))
                #expect(source.contains("sandboxreceipt"))
            }
        }
    }

    @Test func commonSecretBearingFilesAreIgnored() throws {
        let ignore = try String(contentsOf: root.appendingPathComponent(".gitignore"), encoding: .utf8)
        for pattern in [".env", ".env.*", "Secrets.xcconfig", "xcuserdata/"] {
            #expect(ignore.contains(pattern), "Missing secret/local-state ignore rule: \(pattern)")
        }
    }
}
