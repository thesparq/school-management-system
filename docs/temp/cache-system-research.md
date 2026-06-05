This is a meaty problem. Let me give you the full mental model first, then the MoonBit-specific implementation strategy.

The pattern you need is called a **dependency-tracked cache with TTL** — and the core insight is that you separate three concerns:

1. **The cache store** — a map from key → (value, expiry, dependents)
2. **The dependency graph** — when you write entry A, you declare "A depends on B", so invalidating B cascades to A
3. **The access protocol** — a single `get_or_fetch` function that handles all states: hit, miss, stale, and cascaded-stale

Let me diagram the architecture, then walk through how to implement it in MoonBit without generics.Here's the full design, then the MoonBit implementation.

---

## The core design

**Three data structures you need:**

```
store:       HashMap[String, CacheEntry]
dep_graph:   HashMap[String, Array[String]]   // key → keys that depend on IT
```

A `CacheEntry` holds the serialized value, an expiry timestamp, and nothing else — the dependency graph is separate so you can traverse it during invalidation without touching the entries themselves.

**The key insight for MoonBit without generics:** everything going into the cache is a `String` (JSON-serialized). Your application code serializes before writing and deserializes after reading. The cache itself is untyped by design — it's a string store with TTL and dependency awareness.

---

## MoonBit implementation

```moonbit
// cache/types.mbt

struct CacheEntry {
  value      : String
  expires_at : Int64        // Unix timestamp in seconds
  created_at : Int64
}

struct CacheSystem {
  store     : @hashmap.HashMap[String, CacheEntry]
  dep_graph : @hashmap.HashMap[String, @array.Array[String]]  
  // dep_graph[A] = [B, C] means: when A is invalidated, also invalidate B and C
}
```

```moonbit
// cache/core.mbt

fn CacheSystem::new() -> CacheSystem {
  {
    store:     @hashmap.new(),
    dep_graph: @hashmap.new(),
  }
}

// Write an entry. deps = keys that, when invalidated, should also kill this entry.
// e.g. set(cs, "lesson:eng101:3", json_str, ttl=1800, deps=["class:eng101"])
fn CacheSystem::set(
  self : CacheSystem,
  key  : String,
  value : String,
  ttl_seconds : Int64,
  deps : Array[String],
  now  : Int64
) -> Unit {
  let entry = { value, expires_at: now + ttl_seconds, created_at: now }
  self.store.set(key, entry)
  
  // Register this key as a dependent of each dep
  for dep in deps {
    match self.dep_graph.get(dep) {
      Some(dependents) => dependents.push(key)
      None => {
        let arr = @array.new()
        arr.push(key)
        self.dep_graph.set(dep, arr)
      }
    }
  }
}

// The ONLY cache read function you should call.
// Returns Some(value_string) on hit, None on miss/stale.
// On None, your application fetches the real value then calls set().
fn CacheSystem::get(
  self : CacheSystem,
  key  : String,
  now  : Int64
) -> String? {
  match self.store.get(key) {
    None => None
    Some(entry) => {
      if now >= entry.expires_at {
        // Stale — evict it and return None so caller re-fetches
        self.store.remove(key)
        None
      } else {
        Some(entry.value)
      }
    }
  }
}

// Invalidate a key AND everything that depends on it (recursive cascade)
fn CacheSystem::invalidate(self : CacheSystem, key : String) -> Unit {
  self.store.remove(key)
  match self.dep_graph.get(key) {
    None => ()
    Some(dependents) => {
      // Copy first — avoid mutating while iterating
      let to_invalidate = dependents.copy()
      self.dep_graph.remove(key)
      for dep_key in to_invalidate {
        self.invalidate(dep_key)   // recursive cascade
      }
    }
  }
}

fn CacheSystem::invalidate_all(self : CacheSystem) -> Unit {
  self.store.clear()
  self.dep_graph.clear()
}
```

---

## The get-or-fetch pattern

This is the wrapper you build per-cache-type that hides the serialize/deserialize boundary:

```moonbit
// In your agent code — one function per "type" of cached thing

fn get_or_fetch_class(
  cache : CacheSystem,
  class_id : String,
  now : Int64
) -> ClassRecord {
  let key = "class:" + class_id
  match cache.get(key, now) {
    Some(json_str) => parse_class_json(json_str)   // cache hit
    None => {
      // Cache miss or stale — fetch from SurrealDB
      let record = fetch_class_from_db(class_id)
      let json = class_to_json(record)
      cache.set(key, json, ttl_seconds=600L, deps=[], now)
      record
    }
  }
}

fn get_or_fetch_lesson(
  cache : CacheSystem,
  class_id : String,
  lesson_id : String,
  now : Int64
) -> LessonRecord {
  let key = "lesson:" + class_id + ":" + lesson_id
  match cache.get(key, now) {
    Some(json_str) => parse_lesson_json(json_str)
    None => {
      let record = fetch_lesson_from_db(class_id, lesson_id)
      let json = lesson_to_json(record)
      // This lesson depends on its class — invalidating the class kills this too
      cache.set(key, json, ttl_seconds=1800L, deps=["class:" + class_id], now)
      record
    }
  }
}
```

---

## Golem-specific considerations

Since Golem agents are persistent, durable processes, a few things matter:

**1. Time source.** In Golem you can't call `std::time::now()` in the normal Wasm way. Use `@wasi.clock_time_get(Realtime)` or whatever your MoonBit Golem SDK exposes for wall time. Thread that `now : Int64` value through every cache call — don't embed it inside the `CacheSystem` struct.

**2. The cache lives in agent memory.** It persists across invocations within one agent's lifetime because Golem checkpoints the entire Wasm linear memory. You get durability for free. When the agent is re-created, cache starts empty — which is correct behavior (it'll just re-fetch on first access).

**3. TTL on re-hydration.** If Golem re-creates an agent from a snapshot, your `expires_at` timestamps are absolute (Unix seconds), so stale detection works correctly even after a sleep/restore cycle. This is exactly why you want absolute expiry times, not relative TTLs stored as remaining seconds.

**4. Invalidation on mutation.** Whenever your agent writes a mutation (updating a class record, updating a lesson), call `cache.invalidate("class:" + class_id)` right after. The cascade handles any dependent lesson entries automatically.

---

## Key naming convention

Use a consistent `type:id` or `type:parent_id:id` scheme throughout:

```
"class:eng101"
"lesson:eng101:week3-intro"
"student:42"
"enrollment:42:eng101"      // depends on ["student:42", "class:eng101"]
```

This makes keys human-readable in logs, makes your dependency declarations self-documenting, and avoids collisions between entity types.

---

The beauty of this design is that adding a new cached entity is just two things: write a `get_or_fetch_X` function, and declare what it `deps` on. The cache system handles the rest — TTL, invalidation cascades, and the no-empty-state guarantee (you always either get a value or fetch one).

Let me just walk you through the flow conversationally.

**First request — cache miss:**

User asks for `class:eng101`. The agent calls `cache.get("class:eng101", now)`. The store has nothing, so it returns `None`. Your `get_or_fetch_class` function sees `None`, goes to SurrealDB, fetches the record, serializes it to JSON, then calls `cache.set("class:eng101", json, ttl=600, deps=[], now)`. The entry is stored with `expires_at = now + 600`. User gets their data.

**Second request — cache hit:**

Same user or another user asks for `class:eng101` again. `cache.get` finds the entry, checks `now >= expires_at` — it's not, so it returns `Some(json)`. Deserialize, serve. SurrealDB is never touched.

**Third request — TTL expired:**

600 seconds have passed. `cache.get` finds the entry, checks `now >= expires_at` — true. It deletes the entry from the store and returns `None`. Your `get_or_fetch` function sees `None`, re-fetches from SurrealDB exactly like the first request, stores a fresh entry with a new `expires_at`. User gets their data.

**Independent cache (no dependencies):**

Yes, fully supported. When you call `cache.set`, just pass `deps=[]`. That entry lives and dies purely by its TTL. Most of your caches will probably be like this. The dependency graph only matters when you need cascaded invalidation.

**Dependent cache:**

You store `lesson:eng101:week3` with `deps=["class:eng101"]`. Internally, the system adds `"class:eng101" → ["lesson:eng101:week3"]` to the dependency graph. The lesson entry itself has no special field marking it as dependent — the graph is separate. The lesson entry looks identical to any other entry in the store.

**Your RPC invalidation call:**

Another agent updates `class:eng101` in the database. It sends an RPC to your agent calling `invalidate("class:eng101")`. Your invalidate function does this: remove `class:eng101` from the store. Then look up the dependency graph — it finds `["lesson:eng101:week3"]`. It removes that too, then recurses in case that lesson had its own dependents. The graph entry for `class:eng101` is also cleared.

Now both entries are completely gone from the store. No tombstone, no "invalidated" flag — just gone.

**Next request after invalidation:**

User asks for `class:eng101`. `cache.get` returns `None` — not because TTL expired, but because the key simply doesn't exist. Your `get_or_fetch` doesn't know or care *why* it's missing. It just sees `None` and re-fetches from SurrealDB. Same code path as the very first request.

**The reason you delete outright rather than flag:**

A flag means every `get` call has to check two conditions — is it present AND is it valid. You also have to remember to clear the flag on re-cache. Outright deletion keeps `get` simple: present and not expired means valid, anything else means fetch. There's no third state to manage, which is exactly the "no empty state" guarantee you wanted.

---

## Typical Flow

Good question. Let me just describe the structure clearly without overcomplicating it.

The mental model first: think in layers. Each layer only talks to the layer directly below it. Your endpoint never touches the database client directly — it always goes through the chain.
```
endpoint → handler → cache/db helpers → db client
```
