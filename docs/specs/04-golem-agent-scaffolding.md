# Unit 4 — Golem Agent Scaffolding (Code‑First)

## Goal

Deploy a single Golem component (`app:agents`) containing all four agent types to the local Golem dev server. The Gateway Agent exposes a `ping` endpoint that calls the Admin Agent via typed RPC (`AdminAgentClient::scoped(...)`) and returns `"admin online"`.

## Design

### Single-Component Architecture

All agent types live in one WASM component (`app-agents/`). The `golem-sdk-tools agents` build step generates typed RPC clients (`<AgentName>Client`) for every `#derive.agent` in the component, making type-safe agent-to-agent calls possible using the idiomatic `scoped(...)` pattern.

### Agent Structure

| Agent | Mode | Mount | Constructor Params |
|---|---|---|---|
| `AdminAgent` | Durable (`#derive.agent`) | None (RPC only) | None (singleton) |
| `GatewayAgent` | Ephemeral (`#derive.agent("ephemeral")`) | `/gateway` | None (fresh per request) |
| `StudentAgent` | Durable (`#derive.agent`) | None (RPC only) | None (placeholder) |
| `TeacherAgent` | Durable (`#derive.agent`) | None (RPC only) | None (placeholder) |

- AdminAgent.ping → returns `"admin online"`.
- GatewayAgent.ping → calls `AdminAgentClient::scoped(fn(admin) { admin.ping() })` via typed intra-component RPC, returns the result.
- StudentAgent and TeacherAgent are defined as empty `#derive.agent` structs so their typed RPC client stubs are generated for future use.

### HTTP API

Domain: `agents.localhost:9006` (local Golem server).

| Path | Method | Agent | Behaviour |
|---|---|---|---|
| `/gateway/ping` | GET | GatewayAgent → RPC → AdminAgent | Returns `"admin online"` |

### Typed Intra-Component RPC

Because all agents share a single WASM component, `AdminAgentClient` is available directly in `gateway_agent.mbt` without imports or raw `@rpc.AgentClient` calls. The `scoped(...)` pattern obtains a client handle, invokes the method, and automatically calls `drop()` via `defer` when the callback returns.

## Implementation

### 1. Rename placeholder agent files

```bash
mv agents/app-agents/student-agent.mbt agents/app-agents/student_agent.mbt
mv agents/app-agents/teacher-agent.mbt agents/app-agents/teacher_agent.mbt
```

### 2. Update `app-agents/gateway_agent.mbt`

Replace the raw `@rpc.AgentClient` call with the typed client:

```moonbit
//|
///|
/// Stateless gatekeeper - ephemeral, fresh instance per HTTP request.
/// Checks activation status with AdminAgent via RPC before forwarding.
#derive.agent("ephemeral")
#derive.mount("/gateway")
struct GatewayAgent {}

//|

///|
fn GatewayAgent::new() -> GatewayAgent {
  GatewayAgent::{  }
}

//|

///|
/// Proxies a ping to the Admin Agent via typed RPC.
/// Returns admin online on success, admin unreachable on RPC failure.
#derive.endpoint(get="/ping")
pub fn GatewayAgent::ping(self : Self) -> String {
  try {
    AdminAgentClient::scoped(fn(admin) raise @common.AgentError {
      admin.ping()
    })
  } catch {
    _ => "admin unreachable"
  }
}
```

`AdminAgentClient::scoped(...)` automatically drops the client handle when the callback completes — no manual `drop()` call needed.

### 3. Build & deploy

```bash
cd agents
golem deploy --reset
```

The build pipeline performs:
1. `golem-sdk-tools reexports` — regenerate WASM re‑export wrappers
2. `golem-sdk-tools agents` — scan `#derive.agent` annotations, regenerate `golem_agents.mbt`, `golem_derive.mbt`, `golem_clients.mbt` (generates typed clients for all agents in the component)
3. `moon build --target wasm` — compile the single component
4. `wasm-tools component embed` + `wasm-tools component new` — produce the final WASM component
5. Upload component to the local Golem server, reset all existing agents, create fresh instances

### 4. Verify with curl

```bash
# Gateway Agent ping (proxied via typed RPC to AdminAgent)
curl http://agents.localhost:9006/gateway/ping
# → "admin online"
```

The local Golem server is assumed to already be running (`golem server run --clean` in a separate terminal).

## Dependencies

| Item | Status | Purpose |
|---|---|---|
| `golem` CLI (≥1.5.x) | Installed | Build, deploy, local server |
| `moon` CLI (≥0.9.x) | Installed | MoonBit compiler |
| `wasm-tools` | Installed | WASM component embedding |
| `golemcloud/golem_sdk: 0.5.2` | In `moon.mod.json` | Golem MoonBit SDK |
| `agents/` directory | Restructured | Single `app-agents/` component |

No new packages or dependencies to install.

## Verification Checklist

- [ ] `golem deploy --reset` succeeds with zero errors and exit code 0
- [ ] `golem component list` shows exactly 1 component (`app:agents`)
- [ ] `golem agent list` shows `AdminAgent()` only (GatewayAgent is ephemeral; Student/Teacher have no agents yet)
- [ ] `curl http://agents.localhost:9006/gateway/ping` returns `"admin online"`
- [ ] `curl http://agents.localhost:9006/admin/ping` returns `404` (AdminAgent not exposed via HTTP)
- [ ] `golem.yaml` `httpApi.deployments.local.agents` contains only `GatewayAgent: {}`
- [ ] `golem_clients.mbt` in `app-agents/` contains `AdminAgentClient` with `scoped`, `get`, and typed method stubs
- [ ] `golem_clients.mbt` in `app-agents/` contains `GatewayAgentClient`, `StudentAgentClient`, `TeacherAgentClient`
- [ ] `gateway_agent.mbt` uses `AdminAgentClient::scoped(...)` — no raw `@rpc.AgentClient` calls
- [ ] Documentation updated: `docs/progress-tracker.md` reflects Unit 4 as completed
