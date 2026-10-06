#!/bin/bash
cat << 'INNER_EOF' >> agents/app-agents/admin_agent.mbt

  let configs_json_str = configs_json.to_string()
  let tt_id_safe = tt_id
  
  let q = "UPDATE type::thing('timetables', '" + tt_id_safe + "') MERGE { day_configs: " + configs_json_str + " }"
  
  let db_result = surreal_query(self.config.value, q)
  match db_result {
    Ok(json_arr) => Ok(json_arr.to_json().to_string())
    Err(e) => Err(e.to_json_string())
  }
}
INNER_EOF

export PATH="$HOME/.moonup/toolchains/0.9.2+bbe2b338f/bin:$PATH"
cd agents && moon check
