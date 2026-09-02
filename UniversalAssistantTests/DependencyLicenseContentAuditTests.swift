import Foundation
import Testing

@Suite("Dependency, license and content audit")
struct DependencyLicenseContentAuditTests {
    private var root: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    }

    @Test func productionTargetsHaveNoUninventoriedExternalPackages() throws {
        let package = try String(contentsOf: root.appendingPathComponent("Backend/Package.swift"), encoding: .utf8)
        let project = try String(contentsOf: root.appendingPathComponent("UniversalAssistant.xcodeproj/project.pbxproj"), encoding: .utf8)
        let inventory = try String(contentsOf: root.appendingPathComponent("DEPENDENCIES.md"), encoding: .utf8)

        #expect(!package.contains(".package("))
        #expect(!project.contains("XCRemoteSwiftPackageReference"))
        #expect(!project.contains("XCSwiftPackageProductDependency"))
        #expect(inventory.contains("no third-party runtime packages"))
        #expect(inventory.contains("Version/source"))
        #expect(inventory.contains("Privacy implications"))
    }

    @Test func repositoryBundlesNoUnlicensedMediaCatalog() throws {
        let product = root.appendingPathComponent("UniversalAssistant")
        let mediaExtensions = Set(["png", "jpg", "jpeg", "gif", "webp", "mp3", "wav", "mp4"])
        let files = FileManager.default.enumerator(at: product, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL } ?? []
        #expect(files.filter { mediaExtensions.contains($0.pathExtension.lowercased()) }.isEmpty)

        let inventory = try String(contentsOf: root.appendingPathComponent("DEPENDENCIES.md"), encoding: .utf8)
        for policy in ["reproducible exact version", "license compatibility", "privacy manifests", "provenance"] {
            #expect(inventory.contains(policy))
        }
    }
}
