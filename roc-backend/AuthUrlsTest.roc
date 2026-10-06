## Tests for the Authentik URL derivation.
##
## They live in their own file because `expect` blocks that call a function are reported as build
## diagnostics when the module is imported by the app. Run them with:
##
##     roc test AuthUrlsTest.roc
##
## The case that matters: Authentik's userinfo endpoint is per instance, not per application, so an
## issuer of the form https://host/application/o/<slug>/ must lose the slug. Deriving it as
## issuer + "userinfo" 404s, and every real token is then rejected.

import AuthUrls exposing [userinfo_url]

AuthUrlsTest := [].{}

expect userinfo_url("https://auth.johnethel.school/application/o/school-management-system/") == "https://auth.johnethel.school/application/o/userinfo/"
expect userinfo_url("https://auth.johnethel.school/application/o/school-management-system") == "https://auth.johnethel.school/application/o/userinfo/"
expect userinfo_url("http://localhost:9000/application/o/school-management-system/") == "http://localhost:9000/application/o/userinfo/"
expect userinfo_url("https://auth.example.org/") == "https://auth.example.org/userinfo"
