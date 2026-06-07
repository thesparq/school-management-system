///|
/// Deterministic, dependency-tracked cache with TTL.
/// Stores serialized JSON strings — handlers own serialize/deserialize.
/// All time values use UInt64 (Unix seconds).
///
/// Key naming convention: entity[:scope[:subscope]]
/// Keys are scoped per-agent (each agent owns its own CacheSystem).
///
/// Examples:
///   "profile"           — student profile data
///   "subjects"          — student's subjects list
///   "terms:JSS1"        — terms for a specific class level
///   "lessons:subj|term" — lessons for subject+term combination
///   "lesson:{id}"       — individual lesson content
///   "class_groups"      — teacher's class assignments
///   "terms:all"         — global terms list (teacher/admin)
///   "active_session_term_id"  — cached active session term ID
///   "session_terms"     — admin session term list

///|
pub const CACHE_TTL : UInt64 = 600UL

///|
struct CacheEntry {
  value : String
  expires_at : UInt64
}

///|
struct CacheSystem {
  store : Map[String, CacheEntry]
  dep_graph : Map[String, Array[String]]
  // dep_graph[parent_key] = [child_keys] — invalidating parent cascades to children
}

///|
pub fn CacheSystem::new() -> CacheSystem {
  { store: Map([], capacity=0), dep_graph: Map([], capacity=0) }
}

///|
/// Returns Some(value) if entry exists and is unexpired.
/// Returns None on miss or expired entry (evicts stale entries in-place).
pub fn CacheSystem::get(
  self : CacheSystem,
  key : String,
  now : UInt64,
) -> String? {
  match self.store.get(key) {
    None => None
    Some(entry) =>
      if now >= entry.expires_at {
        self.store.remove(key)
        None
      } else {
        Some(entry.value)
      }
  }
}

///|
/// Stores a value with absolute expiry (now + ttl_seconds).
/// Registers key as a dependent of each dep, so invalidating any dep
/// cascades to this entry.
pub fn CacheSystem::set(
  self : CacheSystem,
  key : String,
  value : String,
  ttl_seconds : UInt64,
  deps : Array[String],
  now : UInt64,
) -> Unit {
  let entry = { value, expires_at: now + ttl_seconds }
  self.store.set(key, entry)
  for dep in deps {
    match self.dep_graph.get(dep) {
      Some(dependents) => dependents.push(key)
      None => {
        let arr = [key]
        self.dep_graph.set(dep, arr)
      }
    }
  }
}

///|
/// Removes a key AND all keys that depend on it (recursive cascade).
pub fn CacheSystem::invalidate(self : CacheSystem, key : String) -> Unit {
  self.store.remove(key)
  match self.dep_graph.get(key) {
    None => ()
    Some(dependents) => {
      let to_invalidate = dependents.copy()
      self.dep_graph.remove(key)
      for dep_key in to_invalidate {
        self.invalidate(dep_key)
      }
    }
  }
}

///|
/// Clears all entries and all dependency tracking.
pub fn CacheSystem::invalidate_all(self : CacheSystem) -> Unit {
  self.store.clear()
  self.dep_graph.clear()
}
