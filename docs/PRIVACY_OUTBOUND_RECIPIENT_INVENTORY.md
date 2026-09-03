# Production outbound recipient inventory

Generated from concrete production URL construction points; dynamic configured endpoints remain provider-specific and fail validation unless HTTPS.

| Recipient/domain | Purpose evidence | Data-class ceiling before provider-specific minimization |
|---|---|---|
| ai-factory.silpo.ua | UniversalAssistant/Commerce/UkrainianRetailerRegistry.swift | provider-operation-specific; AUTH_SECRET only as transport header and NEVER_AI |
| api.novaposhta.ua | UniversalAssistant/Delivery/ParcelProviderAdapters.swift | provider-operation-specific; AUTH_SECRET only as transport header and NEVER_AI |
| bolt.eu | UniversalAssistant/Services/RideProviderRegistry.swift | provider-operation-specific; AUTH_SECRET only as transport header and NEVER_AI |
| core.telegram.org | UniversalAssistant/Integrations/LaunchMarketAppMatrix.swift | provider-operation-specific; AUTH_SECRET only as transport header and NEVER_AI |
| dcz.gov.ua | UniversalAssistant/Jobs/JobsDiscoveryEngine.swift | provider-operation-specific; AUTH_SECRET only as transport header and NEVER_AI |
| developer.apple.com | UniversalAssistant/Integrations/LaunchMarketAppMatrix.swift | provider-operation-specific; AUTH_SECRET only as transport header and NEVER_AI |
| developer.uber.com | UniversalAssistant/Services/RideProviderRegistry.swift | provider-operation-specific; AUTH_SECRET only as transport header and NEVER_AI |
| developers.google.com | UniversalAssistant/Integrations/LaunchMarketAppMatrix.swift | provider-operation-specific; AUTH_SECRET only as transport header and NEVER_AI |
| developers.viber.com | UniversalAssistant/Integrations/LaunchMarketAppMatrix.swift | provider-operation-specific; AUTH_SECRET only as transport header and NEVER_AI |
| diia.gov.ua | UniversalAssistant/Government/GovernmentLocalServicesEngine.swift | provider-operation-specific; AUTH_SECRET only as transport header and NEVER_AI |
| djinni.co | UniversalAssistant/Jobs/JobsDiscoveryEngine.swift | provider-operation-specific; AUTH_SECRET only as transport header and NEVER_AI |
| fora.ua | UniversalAssistant/Commerce/UkrainianRetailerRegistry.swift | provider-operation-specific; AUTH_SECRET only as transport header and NEVER_AI |
| fozzyshop.ua | UniversalAssistant/Commerce/UkrainianRetailerRegistry.swift | provider-operation-specific; AUTH_SECRET only as transport header and NEVER_AI |
| gmail.googleapis.com | UniversalAssistant/Email/GmailEmailProvider.swift | provider-operation-specific; AUTH_SECRET only as transport header and NEVER_AI |
| happymonday.ua | UniversalAssistant/Jobs/JobsDiscoveryEngine.swift | provider-operation-specific; AUTH_SECRET only as transport header and NEVER_AI |
| integration.diia.gov.ua | UniversalAssistant/Government/GovernmentLocalServicesEngine.swift | provider-operation-specific; AUTH_SECRET only as transport header and NEVER_AI |
| itunes.apple.com | UniversalAssistant/Integrations/ApplePodcastProvider.swift | provider-operation-specific; AUTH_SECRET only as transport header and NEVER_AI |
| jobs.dou.ua | UniversalAssistant/Jobs/JobsDiscoveryEngine.swift | provider-operation-specific; AUTH_SECRET only as transport header and NEVER_AI |
| jobs.ua | UniversalAssistant/Jobs/JobsDiscoveryEngine.swift | provider-operation-specific; AUTH_SECRET only as transport header and NEVER_AI |
| kyiv.digital | UniversalAssistant/Government/GovernmentLocalServicesEngine.swift | provider-operation-specific; AUTH_SECRET only as transport header and NEVER_AI |
| kyivcity.gov.ua | UniversalAssistant/Government/GovernmentLocalServicesEngine.swift | provider-operation-specific; AUTH_SECRET only as transport header and NEVER_AI |
| m.uber.com | UniversalAssistant/Services/RideProviderRegistry.swift | provider-operation-specific; AUTH_SECRET only as transport header and NEVER_AI |
| maps.apple.com | UniversalAssistant/Actions/UkraineEmergencyPlanner.swift, UniversalAssistant/Delivery/ParcelDeliveryEngine.swift, UniversalAssistant/Navigation/NavigationHandoff.swift | provider-operation-specific; AUTH_SECRET only as transport header and NEVER_AI |
| mcp.silpo.ua | Backend/Sources/UniversalAssistantServer/SilpoMCPClient.swift, UniversalAssistant/Commerce/UkrainianRetailerRegistry.swift | provider-operation-specific; AUTH_SECRET only as transport header and NEVER_AI |
| mwl.meest.com | UniversalAssistant/Delivery/ParcelProviderAdapters.swift | provider-operation-specific; AUTH_SECRET only as transport header and NEVER_AI |
| robota.ua | UniversalAssistant/Jobs/JobsDiscoveryEngine.swift | provider-operation-specific; AUTH_SECRET only as transport header and NEVER_AI |
| uklon.com.ua | UniversalAssistant/Services/RideProviderRegistry.swift | provider-operation-specific; AUTH_SECRET only as transport header and NEVER_AI |
| wa.me | UniversalAssistant/Integrations/MessagingIntegration.swift | provider-operation-specific; AUTH_SECRET only as transport header and NEVER_AI |
| waze.com | UniversalAssistant/Navigation/NavigationHandoff.swift | provider-operation-specific; AUTH_SECRET only as transport header and NEVER_AI |
| www.atbmarket.com | UniversalAssistant/Commerce/UkrainianRetailerRegistry.swift | provider-operation-specific; AUTH_SECRET only as transport header and NEVER_AI |
| www.google.com | UniversalAssistant/Integrations/ControlledWebSearchHandoff.swift, UniversalAssistant/Integrations/UniversalDeviceCommandRouter.swift, UniversalAssistant/Navigation/NavigationHandoff.swift | provider-operation-specific; AUTH_SECRET only as transport header and NEVER_AI |
| www.ukrposhta.ua | UniversalAssistant/Delivery/ParcelProviderAdapters.swift | provider-operation-specific; AUTH_SECRET only as transport header and NEVER_AI |
| www.work.ua | UniversalAssistant/Jobs/JobsDiscoveryEngine.swift | provider-operation-specific; AUTH_SECRET only as transport header and NEVER_AI |

No third-party analytics/crash/marketing SDK dependency was found in production sources. Apple frameworks remain permission/capability scoped.
