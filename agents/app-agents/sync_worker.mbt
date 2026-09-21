// The Sync Worker handles synchronizing identity and access 
// from Golem to Matrix (Chat) and OpenCloud (Drive).

pub struct SyncWorker {
  id: String
}

pub fn SyncWorker::new(id: String) -> SyncWorker {
  SyncWorker::{ id }
}

/// Invites a generated Matrix ID to a specific Matrix room.
pub fn SyncWorker::invite_user_to_matrix_room(
  self: SyncWorker,
  user_id: String,
  matrix_room_id: String
) -> Unit {
  let domain = "localhost" // TODO: Read from Env
  let admin_token = "TODO_SYNAPSE_ADMIN_TOKEN"
  
  // Matrix IDs format: @username:domain.com
  let _matrix_id = "@" + user_id + ":" + domain
  
  // TODO: Use wasi:http/outgoing-handler to POST to:
  // https://matrix.localhost/_matrix/client/v3/rooms/{matrix_room_id}/invite
  // with body { "user_id": matrix_id } and Bearer admin_token

  @logging.info("SyncWorker " + self.id + ": Invited " + user_id + " to Matrix room " + matrix_room_id)
}

/// Creates a shared folder on OpenCloud (NextCloud)
pub fn SyncWorker::provision_cloud_folder(
  self: SyncWorker,
  user_id: String,
  folder_name: String
) -> Unit {
  @logging.info("SyncWorker " + self.id + ": Provisioned OpenCloud folder '" + folder_name + "' for " + user_id)
}
