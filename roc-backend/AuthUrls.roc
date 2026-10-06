## Authentik URLs derived from configuration.
##
## Authentik serves a single userinfo endpoint for the whole instance
## (https://<host>/application/o/userinfo/), not one per application, so an issuer such as
## https://<host>/application/o/<slug>/ has to be cut back to its host before the path is appended.
## Deriving it the obvious way — issuer + "userinfo" — points at a 404, and every real token is then
## rejected with 401. dev-skip hides that locally, so check it against the deployed Authentik
## (`tests/e2e/auth_config_check.sh` does).
##
## Its own module, with no HTTP in it, so `roc test AuthUrlsTest.roc` covers the rule cleanly.

AuthUrls := [].{
    ## The userinfo endpoint to validate tokens against, given AUTHENTIK_ISSUER_URL.
    userinfo_url : Str => Str
    userinfo_url = |issuer| {
        if Str.contains(issuer, "/application/o/") {
            match Str.split_on(issuer, "/application/o/") |> List.first {
                Ok(origin) => if Str.is_empty(origin) { "${issuer}userinfo" } else { "${origin}/application/o/userinfo/" }
                Err(_) => "${issuer}userinfo"
            }
        } else {
            # Not an Authentik issuer path: leave it alone and append, as before.
            "${issuer}userinfo"
        }
    }
}
