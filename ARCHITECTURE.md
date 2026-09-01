# Architecture

UniversalAssistant is local-first and iPhone-only for V1 (minimum iOS 18). The SwiftUI shell routes voice or typed input into a deterministic `LocalCommandEngine`, then into capability-specific executors. Personal iPhone data remains local and system-owned where Apple frameworks provide the source of truth. External capabilities use typed provider contracts, bounded asynchronous calls, freshness metadata and truthful fallbacks.

The backend is a separately deployable, stateless-by-default service boundary for accounts, proactive jobs, APNs, remote configuration, business services and provider secrets. Durable database, cache and queue choices remain gated until their first required vertical milestone. MacInCloud and Codex are development infrastructure only.

Commerce Hub is an on-demand module, not another app. Its M4 pipeline is `StructuredCommand → ProductIdentity → bounded provider fan-out → validated normalized offers → commission-independent ranking → premium native cards → exact attributed provider handoff`. Provider secrets and affiliate routing stay server-side where required. Commerce initialization, caches and failures remain isolated from local/system commands; no catalogue is bundled or mirrored to the phone.
