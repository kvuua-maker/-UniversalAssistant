# M4 Official Сільпо MCP Read Adapter Boundary

- Backend-only `SilpoMCPClient` pins the exact official `https://mcp.silpo.ua/mcp` endpoint and accepts a runtime guest OAuth token per call; it retains no token state.
- The client supports Streamable HTTP JSON and `text/event-stream`, bounded 1–30 second request timeout, JSON-RPC errors, 401 and 429 typed states.
- `tools/list` is mandatory before `tools/call`. Calls are limited to a reviewed read-only allowlist matching the official 2026-09-01 documentation.
- Cart mutation names fail before network access. Write actions require a separate consequential-action/readback block.
- Dynamic `inputSchema` is preserved as typed recursive JSON. No provider payload field or product availability is invented before live schema discovery.
- Transport is injectable and tests verify exact endpoint/auth headers without committing credentials or logging response bodies on auth failures.

Verification: Backend Swift Testing passed 5 tests in 1 suite on 2026-09-01; the latest iOS suite remains 91 tests in 22 suites. Live OAuth, `tools/list` schema capture and response normalization require owner guest login/OTP and provider access, recorded as a device/provider gate rather than a completed live integration.
