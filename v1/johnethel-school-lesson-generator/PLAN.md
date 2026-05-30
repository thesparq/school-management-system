# MoonBit Migration Plan — lesson-generator

## Strategy

- **Branch**: `moonbit-migration` (no changes to `main`)
- **No deletions** until full verification — old Rust code stays alongside
- **Hybrid architecture**: ContentAgent → MoonBit, PdfAgent → stays in Rust (Typst dependency)
- **New directories** alongside existing ones: `components-moonbit/`, `components-rust/pdf-agent/`
- **BAML stays** — MoonBit calls BAML's HTTP API directly (no generated Rust client in MoonBit)

---

## Phase 0: Project Setup

### 0.1 Branch & Rename

```shell
git checkout -b moonbit-migration
mv golem.yaml golem-old.yaml
```

### 0.2 New `golem.yaml` (v1.5 format)

```yaml
manifestVersion: "1.5.0-dev.3"
app: lesson-generator

components:
  lesson-generator:content-agent:
    dir: components-moonbit/content-agent
    componentWasm: target/wasm32-wasip2/debug/content_agent.wasm
    outputWasm: golem-temp/content-agent.wasm
    build:
      - command: moon build --target wasm
    env:
      SURREAL_DB_URL: "{{ SURREAL_DB_URL }}"
      BAML_BASE_URL: "{{ BAML_BASE_URL }}"

  lesson-generator:pdf-agent:
    dir: components-rust/pdf-agent
    componentWasm: target/wasm32-wasip2/debug/pdf_agent.wasm
    outputWasm: golem-temp/pdf-agent.wasm
    build:
      - command: cargo build --target wasm32-wasip2
    env:
      SURREAL_DB_URL: "{{ SURREAL_DB_URL }}"
    files:
      - sourcePath: ./components-rust/pdf-agent/files/template.typ
        targetPath: /templates/template.typ
      - sourcePath: ./components-rust/pdf-agent/files/times.ttf
        targetPath: /fonts/times-new-roman.ttf
      - sourcePath: ./components-rust/pdf-agent/files/watermark.png
        targetPath: /templates/images/watermark.png

agents:
  MasterContentAgent: {}
  PdfAgent: {}

httpApi:
  deployments:
    local:
      - domain: lesson-generator.localhost:9006
        agents:
          PdfAgent: {}

environments:
  local:
    default: true
    server: local
    componentPresets: debug
  cloud:
    server: cloud
    componentPresets: release
```

### 0.3 Create Directories

```
components-moonbit/
└── content-agent/
    ├── moon.pkg.json
    ├── master_content_agent.mbt
    ├── child_content_agent.mbt
    ├── types.mbt
    ├── surreal_client.mbt
    ├── baml_client.mbt
    └── files/                        # (empty, no initial files needed for content agent)

components-rust/pdf-agent/            # NEW — extracted from old generator-functions
├── Cargo.toml
├── src/
│   ├── lib.rs
│   └── pdf_engine.rs                 # moved from common-rust/common-lib/src/utils/
└── files/
    ├── template.typ                  # from old golem.yaml file section
    ├── times.ttf
    └── watermark.png
```

### 0.4 Initialize MoonBit Module

```shell
cd components-moonbit/content-agent
moon new --name content-agent .
moon add golemcloud/golem_sdk
moon install
```

### 0.5 Update workspace Cargo.toml

Remove old generator-functions from workspace, add new pdf-agent:

```toml
[workspace]
resolver = "2"
members = ["components-rust/pdf-agent"]
```

---

## Phase 1: Data Types (MoonBit — `types.mbt`)

Manually define BAML data models as MoonBit structs with `#derive.golem_schema`.

Source: `baml_src/lesson.baml` class definitions map 1:1 to MoonBit.

### Required types:

```moonbit
#derive.golem_schema
pub(all) enum ClassLevel { Primary1, Primary2, Primary3, Primary4, Primary5, Jss1, Jss2, Jss3 }

#derive.golem_schema
pub(all) enum Term { First, Second, Third }

#derive.golem_schema
pub(all) struct TopicRecord {
  id: String?
  agegroup: String
  class: String
  subject: String
  term: String
  topic: String
  week: Int
  context: String?
}

#derive.golem_schema
pub(all) struct CompleteLessonContent {
  topic_title: String
  subject: String
  class_level: ClassLevel
  age_range: String
  term: Term
  week: Int
  duration_mins: Int
  objectives: Array[LessonObjective]
  introduction: String
  content_sections: Array[ContentSection]
  conclusion: String
  key_points: Array[String]
  mcq_questions: Array[MultipleChoiceQuestion]
  theoretical_questions: Array[TheoreticalQuestion]
  prior_knowledge: Array[String]
  materials: Array[String]
  lesson_steps: Array[LessonStep]
  formative_assessment: String
  summative_assessment: String
  success_criteria: Array[String]
  remediation: String
  extension_activities: Array[String]
  primary_sources: Array[String]
  textbook_references: Array[String]
  teacher_tips: String
}

// ... all sub-types: LessonObjective, ContentSection, LessonStep,
//     MultipleChoiceQuestion, TheoreticalQuestion, ContentSubPoint, etc.

#derive.golem_schema
pub(all) struct AgentError {
  message: String
  code: String
}
```

### Request type for BAML API:

```moonbit
#derive.golem_schema
pub(all) struct GenerateNigerianLessonRequest {
  age_group: String
  class_level: ClassLevel
  subject: String
  term: Term
  topic: String
  week: Int
  context: String?
}
```

### Response type for PDF:

```moonbit
#derive.golem_schema
pub(all) struct PdfFile {
  content_type: String
  data: FixedArray[Byte]
}
```

---

## Phase 2: SurrealDB Client (MoonBit — `surreal_client.mbt`)

Port from `common-rust/common-lib/src/utils/mod.rs`.

### Functions

| Function | Signature | Description |
|----------|-----------|-------------|
| `db_request` | `(query: String) -> Result[Array[JsonValue], AgentError]` | Raw SurrealDB REST call |
| `fetch_topics` | `(table: String) -> Result[Array[TopicRecord], AgentError]` | Fetch topic rows |
| `fetch_lessons` | `(subject: String, class: String) -> Result[Array[CompleteLessonContent], AgentError]` | Fetch generated lessons for PDF |
| `create_row` | `(content: CompleteLessonContent, source_id: String) -> Result[String, AgentError]` | Write lesson to DB |
| `content_exists` | `(source_id: String) -> Bool` | Check if row already processed |

### How SurrealDB calls work in MoonBit

Use WASI HTTP (`golem-make-http-request-moonbit` skill pattern):

```moonbit
import {
  "golemcloud/golem_sdk/http" @http,
  "golemcloud/golem_sdk/interface/wasi/http/types" @types,
  "moonbitlang/core/encoding/utf8" @utf8,
}
```

The SurrealQL queries stay identical to the Rust version. Only the HTTP transport changes:

```
POST {SURREAL_DB_URL}/sql
Authorization: Basic cm9vdDpzZWNyZXQ=
Body: SurrealQL query string
```

---

## Phase 3: BAML Client (MoonBit — `baml_client.mbt`)

Replace the generated Rust OpenAPI client with direct HTTP calls to the BAML server.

### Endpoint

```
POST {BAML_BASE_URL}/call/GenerateNigerianLesson
Content-Type: application/json

{
  "age_group": "7-8 years",
  "class_level": "PRIMARY_3",
  "subject": "Basic Science",
  "term": "FIRST",
  "topic": "Parts of a Plant",
  "week": 5,
  "context": null
}
```

### Function

```moonbit
pub fn call_baml_generate_lesson(request: GenerateNigerianLessonRequest) -> Result[CompleteLessonContent, AgentError] {
  // 1. Build WASI HTTP POST request
  // 2. Serialize request body to JSON
  // 3. Send via @http.handle
  // 4. Poll FutureIncomingResponse
  // 5. Parse response JSON into CompleteLessonContent
  // 6. Handle errors
}
```

### Class level mapping (same as Rust version)

```moonbit
fn class_to_baml_level(class: String) -> ClassLevel {
  match class {
    "Year 1" => Primary1
    "Year 2" => Primary2
    "Year 3" => Primary3
    "Year 4" => Primary4
    "Year 5" => Primary5
    "Jss 1" => Jss1
    "Jss 2" => Jss2
    "Jss 3" => Jss3
    _ => abort("Invalid class: \{class}")
  }
}

fn term_to_baml_term(term: String) -> Term {
  match term {
    "1st Term" | "Noel Term" => First
    "2nd Term" | "Calvary Term" => Second
    "3rd Term" | "Summer Term" => Third
    _ => abort("Invalid term: \{term}")
  }
}
```

---

## Phase 4: Master Content Agent (MoonBit — `master_content_agent.mbt`)

### Architecture

```
MasterContentAgent.generate_all(table)
├── fetch_topics(table)
├── populate queue: [(row_id, retry_count)]
├── dispatch_initial_batch() — fire off up to 3 children
├── loop (while in_flight > 0):
│   ├── await_any_promise() ← blocks until a child fulfills
│   ├── if Ok(content):
│   │   ├── create_row(content, row_id)  ← Master writes to DB
│   │   └── dispatch_next()              ← spawn child for next row in queue
│   ├── if Err(error):
│   │   ├── if retry_count < MAX_RETRIES:
│   │   │   └── push back to queue, dispatch_next()
│   │   └── else:
│   │       └── record permanent failure, dispatch_next()
│   └── continue
└── return summary
```

### Constants

```moonbit
let CONCURRENCY_LIMIT = 3
let MAX_RETRIES = 5
```

### Agent definition

```moonbit
#derive.agent
pub(all) struct MasterContentAgent {
  name: String
}

fn MasterContentAgent::new(name: String) -> MasterContentAgent {
  { name }
}
```

### Core method

```moonbit
pub fn MasterContentAgent::generate_all(self: Self, table: String) -> Result[String, AgentError] {
  let topics = fetch_topics(table)?
  let mut queue: @linked_list.LinkedList[(String, Int)] = topics.iter()
    .map(fn(t) { (t.id!, 0) }).collect()
  let mut in_flight: Map[String, Promise] = {}
  let mut permanent_fails: Map[String, String] = {}

  // Dispatch initial batch
  try_dispatch(queue, in_flight, table)

  // Await-promise loop
  while in_flight.size() > 0 {
    let (row_id, promise) = await_first_promise(in_flight)
    in_flight.remove(row_id)

    match promise.result() {
      Ok(content) => {
        create_row(content, row_id)?
        try_dispatch(queue, in_flight, table)
      }
      Err(e) => {
        let retry = retry_count_for(row_id)
        if retry < MAX_RETRIES {
          queue.push_back((row_id, retry + 1))
          try_dispatch(queue, in_flight, table)
        } else {
          permanent_fails[row_id] = e.message
          try_dispatch(queue, in_flight, table)
        }
      }
    }
  }

  if permanent_fails.is_empty() {
    Ok("All \{topics.length()} rows complete")
  } else {
    Err(AgentError { message: "\{permanent_fails.size()} rows failed", code: "PARTIAL_FAILURE" })
  }
}
```

### Dispatch logic

```moonbit
fn try_dispatch(
  queue: @linked_list.LinkedList[(String, Int)],
  in_flight: Map[String, Promise],
  table: String,
) {
  while in_flight.size() < CONCURRENCY_LIMIT and not queue.is_empty() {
    let (row_id, retry_count) = queue.pop_front()
    if already_in_db(row_id) { continue }  // already done, skip
    let promise = @promise.create::[CompleteLessonContent]()
    in_flight[row_id] = promise
    ChildContentAgentClient::scoped(child_id(row_id), fn(c) {
      c.trigger_generate(table, row_id, promise.id(), retry_count)
    })
  }
}
```

### Promise awaiting

```moonbit
fn await_first_promise(in_flight: Map[String, Promise]) -> (String, Promise) {
  // Iterate in_flight, find one that's fulfillable or just pick first
  // Golem's native promise multiplexing: await_any or sequential fallback
  for (row_id, promise) in in_flight {
    let result = promise.await_value()
    // await_value returns when the promise is fulfilled/failed
    // This suspends the agent — no CPU burn
    return (row_id, result)
  }
  abort("no in-flight promises")
}
```

**Note**: If Golem's MoonBit SDK doesn't expose `await_any`, the fallback is sequential awaiting of each promise. Since children are already dispatched in parallel via `trigger_`, the sequential await doesn't lose parallelism — children process concurrently, and the Master picks them up as they finish.

---

## Phase 5: Child Content Agent (MoonBit — `child_content_agent.mbt`)

### Purpose

Process ONE topic row. Pure computation unit — no DB writes, just BAML call + promise fulfillment.

### Agent definition

```moonbit
#derive.agent
pub(all) struct ChildContentAgent {
  id: String
}

fn ChildContentAgent::new(id: String) -> ChildContentAgent { { id } }
```

### Generate method

```moonbit
pub fn ChildContentAgent::generate(
  self: Self,
  table: String,
  row_id: String,
  promise_id: String,
  retry_count: Int,
) {
  // 1. Base rate-limit delay (every call)
  @time.sleep(Duration::from_millis(4000))

  // 2. Exponential backoff for retries
  if retry_count > 0 {
    let delay_ms = 1000 * (1 << (retry_count - 1))  // 1s, 2s, 4s, 8s, 16s
    @time.sleep(Duration::from_millis(delay_ms))
  }

  // 3. Fetch topic + call BAML (with @api.with_retry_policy for HTTP errors)
  let topic = fetch_single_topic(table, row_id)
  let content = @api.with_retry_policy(baml_retry_policy(), fn() {
    @time.sleep(Duration::from_millis(4000))  // extra rate-limit on retry
    call_baml_generate_lesson(topic)
  })

  // 4. Fulfill or fail the promise
  match content {
    Ok(lesson) => { @promise.fulfill(promise_id, lesson) }
    Err(e) => { @promise.fail(promise_id, e.message) }
  }
}
```

### Retry policy for BAML calls

```moonbit
fn baml_retry_policy() -> @api.RetryPolicy {
  @api.RetryPolicy::{
    max_attempts: 3,
    min_delay: 1000,         // 1s
    max_delay: 30000,        // 30s
    multiplier: 3.0,
    max_jitter_factor: Some(0.1),
  }
}
```

---

## Phase 6: Rust PdfAgent — Extract to Standalone Component

### 6.1 New minimal Cargo.toml

```toml
[package]
name = "pdf-agent"
version = "0.0.1"
edition = "2021"

[lib]
crate-type = ["cdylib"]

[dependencies]
golem-rust = "1.5"
typst = "0.14.2"
typst-pdf = "0.14.2"
typst-as-lib = "0.15.0"
derive_typst_intoval = "0.6.0"
serde = { version = "1", features = ["derive"] }
serde_json = "1"
wstd = { version = "=0.5.4", features = ["default", "json"] }
```

### 6.2 Files to extract from old components-rust/generator-functions

- `src/agents_implementations/pdf_agent.rs` → `src/lib.rs` (strip ContentAgent parts)
- From `common-rust/common-lib/src/utils/pdf_engine.rs` → `src/pdf_engine.rs`
- `fetch_lessons` function from `common-rust/common-lib/src/utils/mod.rs` (only the DB query part)
- Template, font, watermark → `files/` directory

### 6.3 Changes from old code

- Update `golem-rust` version to match CLI 1.5.1
- Change wasm target from `wasm32-wasip1` to `wasm32-wasip2`
- Remove BAML and ContentAgent dependencies
- Strip to only PdfAgent + pdf_engine

### 6.4 File provisioning

```yaml
# In new golem.yaml component section
files:
  - sourcePath: ./components-rust/pdf-agent/files/template.typ
    targetPath: /templates/template.typ
  - sourcePath: ./components-rust/pdf-agent/files/times.ttf
    targetPath: /fonts/times-new-roman.ttf
  - sourcePath: ./components-rust/pdf-agent/files/watermark.png
    targetPath: /templates/images/watermark.png
```

### 6.5 Updated agent definition

```rust
#[agent_definition]
pub trait PdfAgent {
    fn new(name: String) -> Self;
    async fn pdf_generator(&mut self, subject: String, class: String, mode: String) -> PdfFile;
}
```

---

## Phase 7: Build, Deploy & Verify

### 7.1 Build

```shell
# MoonBit component
cd components-moonbit/content-agent && moon build --target wasm

# Rust PDF component
cd components-rust/pdf-agent && cargo build --target wasm32-wasip2

# Both via Golem
golem -A golem.yaml build --yes
```

### 7.2 Deploy locally

```shell
# Terminal 1: start server
golem server run

# Terminal 2: deploy
golem -A golem.yaml deploy --yes --reset
```

### 7.3 Test ContentAgent

```shell
golem agent invoke \
  'MasterContentAgent("master-1")' \
  generate_all '["topics_primary_3"]'
```

### 7.4 Test PdfAgent

```shell
# Via HTTP
curl http://lesson-generator.localhost:9006/generate-pdf-api/Basic%20Science/PRIMARY_3/teacher \
  -o lesson.pdf

# Via CLI
golem agent invoke \
  'PdfAgent("pdf-gen-1")' \
  pdf_generator '["Basic Science", "PRIMARY_3", "teacher"]'
```

### 7.5 Verify against old system

- Run same table through both old (Rust on `main`) and new (MoonBit on `moonbit-migration`)
- Compare generated lessons in SurrealDB for equivalent content structure
- Compare PDF output for identical layout

---

## Phase 8: Cleanup (after full verification)

Only when both agents are verified and working in production:

```shell
git rm -r common-rust/
git rm -r components-rust/generator-functions/   # old multi-agent component
git rm Cargo.toml Cargo.lock                      # workspace root (if no Rust left)
git rm .wit/                                      # not needed for MoonBit
git rm golem-old.yaml                             # old config
```

---

## File Map: Before → After

```
BEFORE:                                    AFTER:
golem.yaml                                 golem-old.yaml                     (preserved, untouched)
Cargo.toml (workspace)                     golem.yaml                         (new v1.5, hybrid MoonBit+Rust)
common-rust/                               Cargo.toml                         (workspace, updated members)
├── common-lib/                            components-moonbit/
├── utils/                                    └── content-agent/
│   ├── mod.rs                                    ├── moon.pkg.json
│   └── pdf_engine.rs                             ├── master_content_agent.mbt   (NEW)
components-rust/                                  ├── child_content_agent.mbt    (NEW)
├── generator-functions/                          ├── types.mbt                  (NEW)
│   ├── ContentAgent                              ├── surreal_client.mbt         (NEW)
│   ├── PdfAgent                                  └── baml_client.mbt            (NEW)
│   └── BAML calls                             components-rust/
baml_src/                                    ├── generator-functions/          (kept for reference)
baml_client/                                 └── pdf-agent/                    (NEW, extracted)
.wit/                                             ├── Cargo.toml
mydatabase/                                       ├── src/lib.rs
                                                  ├── src/pdf_engine.rs
                                                  └── files/ (template, font, watermark)
                                              baml_src/                         (unchanged)
                                              baml_client/                      (unchanged)
                                              .wit/                             (unchanged)
                                              mydatabase/                       (unchanged)
                                              PLAN.md                           (THIS FILE)
```

---

## Risk Register

| Risk | Impact | Mitigation |
|------|--------|-----------|
| Promise API not exposed in MoonBit SDK | Blocks content agent architecture | Fallback: sequential await, or callback pattern with Master tracking state |
| WASI HTTP resource lifecycle bugs | SurrealDB/BAML calls fail | Follow `golem-make-http-request-moonbit` patterns exactly; correct `drop()` ordering |
| MoonBit JSON parsing differs from Rust serde | Data corruption | Add integration test: call BAML from test, verify CompleteLessonContent deserializes |
| Rust `golem-rust` SDK incompatible with Golem CLI 1.5.1 | PdfAgent won't build | Try latest golem-rust crate; if fails, isolate PdfAgent under old config temporarily |
| `@time.sleep` not durable in MoonBit | Rate limiting lost on crash | Verify in docs; if not, use `wasi:clocks/monotonic-clock` or `@api` durability primitives |
| BAML rate limiting with 3 parallel children | IP ban / 429 errors | Each child has 4s base delay + exponential backoff on retry = max 0.75 req/s sustained |
| Promise `await_any` unavailable | Sequential await reduces responsiveness | Sequential await is still fine — children run in parallel, await is instant for completed ones |
| MoonBit `@linked_list.LinkedList` availability | Queue data structure | May need custom queue using `Array` + index pointer or `@list.List` |
