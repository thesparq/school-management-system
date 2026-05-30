# Step 2: MoonBit Foundation

**Branch**: `moonbit-migration/02-moonbit-foundation`

## Completed

### Part A: Fixed MoonBit scaffolding
Deleted the broken manual setup and regenerated via:
```shell
golem new --template moonbit --component-name lesson-generator:content-agent --yes .
```
This created:
- `moon.pkg` — proper WASM exports, agent imports, HTTP/RPC/stdlib imports
- `moon.mod.json` — preferred-target wasm, bin-deps for golem_sdk_tools
- `golem.yaml` — updated with `templates: moonbit` + pdf-agent + env vars

### Part B: `types.mbt` — All data models
- `ClassLevel` enum (Primary1–Jss3)
- `Term` enum (First, Second, Third)
- `TopicRecord` struct
- `CompleteLessonContent` struct + all sub-types
- `GenerateNigerianLessonRequest` struct
- `PdfFile` struct (content_type: String, data: Bytes)
- `AgentError` struct

### Part C: `surreal_client.mbt` — SurrealDB HTTP client
- `db_request(query)` — raw SurrealQL via WASI HTTP POST
- `fetch_topics(table)` — stub
- `fetch_lessons(subject, class)` — stub
- `create_row(content, source_id)` — stub
- `content_exists(source_id)` — stub

### `agent.mbt` — MasterContentAgent stub
- `generate_all(table)` — returns "stub: {table}"

## Pending (deferred to later step)

- **Part D**: `baml_client.mbt` — full BAML HTTP client with request serialization and response parsing
- **Part E**: HttpProxyAgent — MoonBit agent with `#derive.mount` + `#derive.endpoint` that proxies to Rust PdfAgent via RPC
- **Part F**: Rust PdfAgent RPC updates

## Build Status

```
golem build --yes  →  Finished building [OK]
```

Both MoonBit content-agent and Rust pdf-agent compile successfully.

## Files Created/Modified

| File | Action |
|------|--------|
| `moon.pkg` | UPDATED (imports + exports) |
| `moon.mod.json` | UPDATED (bin-deps) |
| `golem.yaml` | UPDATED (templates: moonbit + pdf-agent) |
| `agent.mbt` | CREATE |
| `types.mbt` | CREATE |
| `surreal_client.mbt` | CREATE |
| `plans/02-moonbit-foundation.md` | CREATE |
