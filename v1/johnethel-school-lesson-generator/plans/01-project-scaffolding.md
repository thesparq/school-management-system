# Step 1: Project Scaffolding

## Branch

```
moonbit-migration/01-project-scaffolding
```

## Goal

Set up the new directory layout, Golem v1.5 manifest, MoonBit module, and standalone PdfAgent Rust component — without modifying any existing code.

---

## Task 1: Branch & Rename

```shell
git checkout -b moonbit-migration/01-project-scaffolding
mv golem.yaml golem-old.yaml
```

## Task 2: Create Directories

```shell
mkdir -p components-moonbit/content-agent
mkdir -p components-rust/pdf-agent/src
mkdir -p components-rust/pdf-agent/files
```

## Task 3: New `golem.yaml` (v1.5 Format)

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

environments:
  local:
    default: true
    server: local
    componentPresets: debug
  cloud:
    server: cloud
    componentPresets: release
```

## Task 4: Init MoonBit Module

```shell
cd components-moonbit/content-agent
moon new --name content-agent .
moon add golemcloud/golem_sdk
moon install
cd ../..
```

## Task 5: Update Workspace `Cargo.toml`

```toml
[workspace]
resolver = "2"
members = ["components-rust/pdf-agent"]

[profile.release]
opt-level = "s"
lto = true
```

## Task 6: PdfAgent `Cargo.toml`

```toml
[package]
name = "pdf-agent"
version = "0.0.1"
edition = "2021"

[lib]
crate-type = ["cdylib"]

[dependencies]
golem-rust = { version = "1.5", features = ["export_golem_agentic"] }
typst = "0.14.2"
typst-pdf = "0.14.2"
typst-as-lib = "0.15.0"
derive_typst_intoval = "0.6.0"
serde = { version = "1", features = ["derive"] }
serde_json = "1"
wstd = { version = "=0.5.4", features = ["default", "json"] }
```

## Task 7: PdfAgent `src/lib.rs`

Self-contained file merging old pdf_agent.rs + common-lib types. Contains:
- PdfAgent trait + PdfImpl implementation
- SurrealDB `fetch_lessons` + `db_request` (inlined, no BAML dep)
- Local `CompleteLessonContent` type defs (String-based fields, not BAML enums)

```rust
mod pdf_engine;

use golem_rust::{agent_definition, agent_implementation, Schema};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use wstd::http::body::IntoBody;
use wstd::http::{Client, HeaderValue, Method, Request};

use pdf_engine::pdf_engine;

// ============================================================
// Data Types
// ============================================================

#[derive(Debug, Clone, Serialize, Deserialize, Schema)]
pub struct AgentError {
    pub message: String,
    pub code: String,
}

#[derive(Schema, Clone)]
pub struct PdfFile {
    pub content_type: String,
    pub data: Vec<u8>,
}

impl From<String> for AgentError {
    fn from(err: String) -> Self {
        AgentError { message: err, code: "ERROR".to_string() }
    }
}

// ============================================================
// Agent Definition
// ============================================================

#[agent_definition]
pub trait PdfAgent {
    fn new(name: String) -> Self;
    async fn pdf_generator(&mut self, subject: String, class: String, mode: String) -> PdfFile;
}

pub struct PdfImpl {
    _name: String,
}

#[agent_implementation]
impl PdfAgent for PdfImpl {
    fn new(name: String) -> Self {
        Self { _name: name }
    }

    async fn pdf_generator(&mut self, subject: String, class: String, mode: String) -> PdfFile {
        let records = match fetch_lessons(&subject, &class).await {
            Ok(records) => records,
            Err(err) => {
                println!("Error: {}", err.message);
                return PdfFile {
                    content_type: "text/plain".to_string(),
                    data: err.message.into_bytes(),
                };
            }
        };

        match pdf_engine(records, &subject, &class, &mode) {
            Ok(pdf) => PdfFile {
                content_type: "application/pdf".to_string(),
                data: pdf,
            },
            Err(err) => {
                println!("Error: {}", err.message);
                PdfFile {
                    content_type: "text/plain".to_string(),
                    data: err.message.into_bytes(),
                }
            }
        }
    }
}

// ============================================================
// SurrealDB fetch_lessons
// ============================================================

#[derive(Debug, Clone, Serialize, Deserialize, Schema)]
pub struct CompleteLessonContent {
    pub topic_title: String,
    pub subject: String,
    pub class_level: String,
    pub age_range: String,
    pub term: String,
    pub week: i32,
    pub duration_mins: i32,
    pub introduction: String,
    pub conclusion: String,
    pub key_points: Vec<String>,
    pub prior_knowledge: Vec<String>,
    pub materials: Vec<String>,
    pub formative_assessment: String,
    pub summative_assessment: String,
    pub success_criteria: Vec<String>,
    pub remediation: String,
    pub extension_activities: Vec<String>,
    pub primary_sources: Vec<String>,
    pub textbook_references: Vec<String>,
    pub teacher_tips: String,
    pub content_sections: Vec<ContentSectionJson>,
    pub lesson_steps: Vec<LessonStepJson>,
    pub objectives: Vec<ObjectiveJson>,
    pub mcq_questions: Vec<McqJson>,
    pub theoretical_questions: Vec<TheoryJson>,
}

#[derive(Debug, Clone, Serialize, Deserialize, Schema)]
pub struct McqJson {
    pub question: String,
    pub option_a: String,
    pub option_b: String,
    pub option_c: String,
    #[serde(alias = "correctAnswer")]
    pub correct_answer: String,
    pub explanation: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, Schema)]
pub struct TheoryJson {
    pub question: String,
    pub parts: Vec<String>,
    #[serde(alias = "modelAnswer")]
    pub model_answer: String,
    #[serde(alias = "markingScheme")]
    pub marking_scheme: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, Schema)]
pub struct ContentSectionJson {
    pub section_number: Option<i32>,
    pub header: String,
    pub body: String,
    pub sub_points: Option<Vec<SubPointJson>>,
}

#[derive(Debug, Clone, Serialize, Deserialize, Schema)]
pub struct SubPointJson {
    pub sub_number: String,
    pub text: Value,
}

#[derive(Debug, Clone, Serialize, Deserialize, Schema)]
pub struct LessonStepJson {
    pub step_number: i32,
    pub phase: String,
    pub duration_mins: i32,
    pub teacher_actions: String,
    pub pupil_activities: String,
    pub teaching_strategy: String,
    pub assessment: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, Schema)]
pub struct ObjectiveJson {
    pub objective: String,
    pub taxonomy_level: String,
}

pub async fn fetch_lessons(
    subject: &str,
    class: &str,
) -> Result<Vec<CompleteLessonContent>, AgentError> {
    let query = format!(
        "USE NS main DB `johnethel-school-generated-lessons`; \
         SELECT * FROM lesson_content \
         WHERE \"{}\" in class_level AND \"{}\" in subject \
         ORDER BY term ASC, week ASC;",
        class, subject
    );
    let response = db_request(query).await?;

    let records = if let Some(select_result) = response.get(1) {
        if let Some(status) = select_result.get("status") {
            if status != "OK" {
                return Err(AgentError {
                    message: format!("Query failed with status: {:?}", status),
                    code: "QUERY_FAILED".to_string(),
                });
            }
        }
        match select_result.get("result") {
            Some(Value::Array(arr)) => {
                serde_json::from_value(Value::Array(arr.clone())).map_err(|e| AgentError {
                    message: format!("Failed to deserialize records: {:?}", e),
                    code: "DESERIALIZE_ERROR".to_string(),
                })?
            }
            Some(Value::Null) => Vec::new(),
            Some(other) => {
                return Err(AgentError {
                    message: format!("Unexpected result type: {:?}", other),
                    code: "UNEXPECTED_RESULT".to_string(),
                });
            }
            None => {
                return Err(AgentError {
                    message: "No 'result' field in response".to_string(),
                    code: "MISSING_RESULT".to_string(),
                });
            }
        }
    } else {
        return Err(AgentError {
            message: format!("Expected at least 2 results, got {}", response.len()),
            code: "INSUFFICIENT_RESULTS".to_string(),
        });
    };
    println!("✓ Fetched {} records from db", records.len());
    Ok(records)
}

async fn db_request(query: String) -> Result<Vec<Value>, AgentError> {
    let url = std::env::var("SURREAL_DB_URL").map_err(|_| AgentError {
        message: "Unable to fetch env for surreal url".to_string(),
        code: "SURREAL_DB_ENV_ERROR".to_string(),
    })?;

    let request = Request::post(url.as_str())
        .header("Accept", HeaderValue::from_str("application/json").map_err(|e| e.to_string())?)
        .header("Authorization", HeaderValue::from_str("Basic cm9vdDpzZWNyZXQ=").map_err(|e| e.to_string())?)
        .body(query.into_body())
        .map_err(|e| AgentError {
            message: e.to_string(),
            code: "REQUEST_BUILD_ERROR".to_string(),
        })?;

    let response = Client::new().send(request).await.map_err(|e| AgentError {
        message: format!("HTTP request failed: {:?}", e),
        code: "CONNECTION_ERROR".to_string(),
    })?;

    let status = response.status();
    if !status.is_success() {
        return Err(AgentError {
            message: format!("Query failed with status: {}", status),
            code: "QUERY_ERROR".to_string(),
        });
    }

    let mut body = response.into_body();
    let response_json: Vec<Value> = body.json().await.map_err(|e| AgentError {
        message: format!("Failed to parse JSON: {:?}", e),
        code: "PARSE_ERROR".to_string(),
    })?;
    Ok(response_json)
}
```

## Task 8: Copy & Adapt `pdf_engine.rs`

Copy from `common-rust/common-lib/src/utils/pdf_engine.rs` to `components-rust/pdf-agent/src/pdf_engine.rs`.

Changes from original:
- Replace `use baml_client::models::{...}` with `use crate::{CompleteLessonContent, AgentError}`
- `class_level` and `term` are now `String` fields (no enum conversion needed)
- Sub-point text is always `String` (no `ContentSubPointText` enum)

## Task 9: Copy Template/Font/Watermark Files

```shell
cp components-rust/generator-functions/files/template.typ \
   components-rust/pdf-agent/files/template.typ
cp components-rust/generator-functions/files/times.ttf \
   components-rust/pdf-agent/files/times.ttf
cp components-rust/generator-functions/files/watermark.png \
   components-rust/pdf-agent/files/watermark.png
```

## Task 10: Verify Builds

```shell
# Rust PdfAgent
rustup target add wasm32-wasip2
cargo build --target wasm32-wasip2 -p pdf-agent

# MoonBit stub
cd components-moonbit/content-agent && moon build --target wasm && cd ../..

# Golem build
golem -A golem.yaml build --yes
```

---

## Verification Checklist

- [ ] `git branch` shows `moonbit-migration/01-project-scaffolding`
- [ ] `golem-old.yaml` exists
- [ ] `golem.yaml` exists (new v1.5 format)
- [ ] `components-moonbit/content-agent/` initialized with MoonBit module
- [ ] `components-rust/pdf-agent/` has Cargo.toml, src/, files/
- [ ] `cargo build --target wasm32-wasip2 -p pdf-agent` succeeds
- [ ] `moon build --target wasm` succeeds
- [ ] `golem -A golem.yaml build --yes` succeeds

---

## Rollback

```shell
git checkout -- golem.yaml Cargo.toml
rm -rf components-moonbit components-rust/pdf-agent
git checkout main
```

---

## Files Created/Modified

| File | Action |
|------|--------|
| `golem.yaml` | CREATE |
| `golem-old.yaml` | RENAME (from old golem.yaml) |
| `Cargo.toml` | MODIFY (workspace members) |
| `components-rust/pdf-agent/Cargo.toml` | CREATE |
| `components-rust/pdf-agent/src/lib.rs` | CREATE |
| `components-rust/pdf-agent/src/pdf_engine.rs` | CREATE (adapted) |
| `components-rust/pdf-agent/files/template.typ` | COPY |
| `components-rust/pdf-agent/files/times.ttf` | COPY |
| `components-rust/pdf-agent/files/watermark.png` | COPY |
| `components-moonbit/content-agent/*` | CREATE (via moon new) |
| `plans/01-project-scaffolding.md` | CREATE |
