# Step 3: BAML Client + Agents + HTTP Proxy

**Branch**: `moonbit-migration/03-agents`

**Goal**: Complete the MoonBit component with working agents — BAML content generation, parallel child dispatch via promises, and an HTTP proxy for PDF downloads.

---

## Task 1: `baml_client.mbt` — BAML HTTP Client

Ports from `common-rust/common-lib/src/utils/mod.rs`:
- `generate_lesson_with_baml` (line 237)
- `convert_from_topic_record_to_baml_format` (line 251)
- `generate_nigerian_lesson` (line 289)

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

### Functions

```moonbit
pub fn call_baml_generate_lesson(request: GenerateNigerianLessonRequest) -> Result[CompleteLessonContent, AgentError]
```

Uses WASI HTTP POST (same pattern as `surreal_client.mbt:db_request`).

### Class/Term conversion (port from Rust)

```moonbit
fn class_to_baml_level(class: String) -> ClassLevel
// "Year 1" → Primary1, etc.

fn term_to_baml_term(term: String) -> Term
// "1st Term" | "Noel Term" → First, etc.

fn convert_topic_to_request(topic: TopicRecord) -> GenerateNigerianLessonRequest
```

---

## Task 2: `child_agent.mbt` — ChildContentAgent

```moonbit
#derive.agent
struct ChildContentAgent { id: String }

fn ChildContentAgent::new(id: String) -> ChildContentAgent { { id } }

pub fn ChildContentAgent::generate(
  self: Self, table: String, row_id: String,
  promise_id: @api.PromiseId, retry_count: Int,
) {
  @time.sleep(Duration::from_millis(4000))         // rate limit
  if retry_count > 0 {
    @time.sleep(Duration::from_millis(1000 * (1 << (retry_count - 1))))
  }
  let topics = fetch_topics(table)?
  let topic = topics.find_first(fn(t) { t.id == Some(row_id) })?
  match call_baml_generate_lesson(convert_topic_to_request(topic)) {
    Ok(content) => { create_row(content, row_id)?; complete_ok(promise_id, row_id) }
    Err(e) => { complete_fail(promise_id, e.message) }
  }
}
```

---

## Task 3: `master_agent.mbt` — MasterContentAgent

Replaces `agent.mbt` stub.

### Flow

```
generate_all(table):
├── fetch_topics(table), populate queue
├── try_dispatch() — spawn ≤3 children
├── loop (while in_flight > 0 or queue not empty):
│   ├── await first promise → "ok:{id}" or "fail:{msg}"
│   ├── ok → try_dispatch()
│   ├── fail, retry < 5 → push back, try_dispatch()
│   └── fail, retry ≥ 5 → log, try_dispatch()
└── return summary
```

---

## Task 4: HttpProxyAgent

```moonbit
#derive.agent
#derive.mount("/generate-pdf-api/{subject}/{class}/{mode}")
#derive.mount_auth(false)
struct PdfHttpProxy { subject: String, class: String, mode: String }

fn PdfHttpProxy::new(s: String, c: String, m: String) -> PdfHttpProxy { { subject: s, class: c, mode: m } }

#derive.endpoint(get = "/")
pub fn PdfHttpProxy::generate(self: Self) -> PdfFile {
  PdfAgentClient::scoped("proxy-" + self.subject, fn(c) {
    c.pdf_generator(self.subject, self.class, self.mode)
  })
}
```

---

## Task 5: Complete `surreal_client.mbt` stubs + JSON parsing

Add `parse_topic_records`, `parse_lesson_content`, and complete `fetch_topics`, `fetch_lessons`, `create_row`.

---

## Task 6: golem.yaml — register new agents + httpApi

---

## Task 7: Build + test

```shell
golem build --yes
```
