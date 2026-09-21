const fs = require('fs');
let code = fs.readFileSync('agents/app-agents/admin_agent.mbt', 'utf8');

// The incomplete part:
//   // To avoid this, we'll use `UPDATE $tt MERGE { day_configs: ... }` but we can't string interpolate JSON safely easily.
//   let configs_json_str = configs_json.to_string()
//   let tt_id_safe = tt_id
//   
//   let q = "UPDATE type::thing('timetables', '" + tt_id_safe + "') MERGE { day_configs: " + configs_json_str + " }"
//   
//   let db_result = surreal_query(self.config.value, q)
//   match db_result {
//     Ok(json_arr) => Ok(json_arr.to_json().to_string())
//     Err(e) => Err(e.to_json_string())
//   }
// }

// Let's just find the `// To avoid this` and replace the end of file.
const splitStr = "// To avoid this, we'll use `UPDATE $tt MERGE { day_configs: ... }` but we can't string interpolate JSON safely easily.";
if (code.includes(splitStr)) {
  const parts = code.split(splitStr);
  code = parts[0] + splitStr + `
  let configs_json_str = configs_json.to_json().to_string()
  let q = "UPDATE type::thing('timetables', '" + tt_id + "') MERGE { day_configs: " + configs_json_str + " }"
  let db_result = surreal_query(self.config.value, q)
  match db_result {
    Ok(json_arr) => Ok(json_arr.to_json().to_string())
    Err(e) => Err(e.to_json_string())
  }
}
`;
  fs.writeFileSync('agents/app-agents/admin_agent.mbt', code);
}
