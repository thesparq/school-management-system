module [login_url, parse_token_from_hash]

login_url : Str -> Str
login_url = |redirect_uri| "http://localhost:9000/application/o/authorize/?client_id=school-frontend&response_type=token&redirect_uri=${redirect_uri}"

parse_token_from_hash : Str -> [Ok(Str), Err(Str)]
parse_token_from_hash = |hash| {
    hash_no_pound = if Str.starts_with(hash, "#") { Str.replace_first(hash, "#", "") } else { hash }
    parts = Str.split_on(hash_no_pound, "&")
    
    val = List.find_first(parts, |p| Str.starts_with(p, "access_token="))
    match val {
        Ok(first) => Ok(Str.replace_first(first, "access_token=", ""))
        Err(_) => Err("No access_token found")
    }
}
