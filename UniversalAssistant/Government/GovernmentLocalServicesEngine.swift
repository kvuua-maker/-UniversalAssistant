import Foundation

enum GovernmentServiceKind: String, Codable, Sendable {
    case diiaServices, diiaIntegration, municipalParking, municipalTransport, administrative, utility
}

enum GovernmentAccessDepth: String, Codable, Sendable {
    case officialPublicHandoff, partnerApprovalRequired
}

struct GovernmentServiceCapability: Identifiable, Equatable, Sendable {
    let id: String
    let kind: GovernmentServiceKind
    let title: String
    let officialURL: URL
    let accessDepth: GovernmentAccessDepth
    let requiresConfirmation: Bool
}

enum GovernmentServiceError: Error, Equatable { case unverifiedSource, privateDataUnavailable }

struct GovernmentLocalServicesEngine {
    private let officialHosts: Set<String>

    init(additionalOfficialHosts: Set<String> = []) {
        officialHosts = Set(["diia.gov.ua", "www.diia.gov.ua", "integration.diia.gov.ua",
            "kyivcity.gov.ua", "www.kyivcity.gov.ua", "kyiv.digital", "www.kyiv.digital"]
        ).union(additionalOfficialHosts.map { $0.lowercased() })
    }

    func launchCapabilities() -> [GovernmentServiceCapability] {
        [
            .init(id: "diia-services", kind: .diiaServices, title: "Державні послуги Дія",
                  officialURL: URL(string: "https://diia.gov.ua/services")!,
                  accessDepth: .officialPublicHandoff, requiresConfirmation: true),
            .init(id: "diia-integration", kind: .diiaIntegration, title: "Інтеграція Дії",
                  officialURL: URL(string: "https://integration.diia.gov.ua")!,
                  accessDepth: .partnerApprovalRequired, requiresConfirmation: true),
            .init(id: "kyiv-parking", kind: .municipalParking, title: "Паркування Києва",
                  officialURL: URL(string: "https://kyivcity.gov.ua/dorohy_transport_ta_parkovky/parkuvannia.html")!,
                  accessDepth: .officialPublicHandoff, requiresConfirmation: true),
            .init(id: "kyiv-digital", kind: .municipalTransport, title: "Київ Цифровий",
                  officialURL: URL(string: "https://kyiv.digital")!,
                  accessDepth: .officialPublicHandoff, requiresConfirmation: true)
        ]
    }

    func verifiedHandoff(_ capability: GovernmentServiceCapability, confirmed: Bool) throws -> URL? {
        guard capability.officialURL.scheme == "https",
              let host = capability.officialURL.host?.lowercased(), officialHosts.contains(host) else {
            throw GovernmentServiceError.unverifiedSource
        }
        guard !capability.requiresConfirmation || confirmed else { return nil }
        return capability.officialURL
    }

    func requestPrivateDiiaDocuments() throws -> Never {
        throw GovernmentServiceError.privateDataUnavailable
    }

    func officialBillPayment(for document: EverydayDocument) throws -> DocumentActionPlan {
        let plan = BillsReceiptsDocumentsEngine().payment(for: document)
        guard case let .paymentHandoff(url, requiresConfirmation) = plan else { return plan }
        guard let host = url.host?.lowercased(), officialHosts.contains(host) else {
            throw GovernmentServiceError.unverifiedSource
        }
        return .paymentHandoff(url, requiresConfirmation: requiresConfirmation)
    }
}
