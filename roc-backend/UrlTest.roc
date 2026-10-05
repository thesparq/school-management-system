## Query parameter decoding tests.
##
## They live in their own file because `expect` blocks that call a function are reported as build
## diagnostics when the module is imported by the app. Run them with:
##
##     roc test UrlTest.roc

import Url

UrlTest := [].{}

# Record ids: the colon arrives escaped from any conforming client, and the id survives.
expect Url.decode("lessons%3Aabc") == "lessons:abc"
expect Url.decode("terms%3Anoel_term") == "terms:noel_term"
expect Url.decode("lessons%3aabc") == "lessons:abc"

# %20 and + both decode to a space.
expect Url.decode("hello%20world") == "hello world"
expect Url.decode("hello+world") == "hello world"

# Mixed escapes, an escaped slash, and a multi-byte UTF-8 sequence.
expect Url.decode("lessons%3Aabc%2Fdef") == "lessons:abc/def"
expect Url.decode("a+b%3Ac%20d") == "a b:c d"
expect Url.decode("caf%C3%A9") == "café"

# Malformed escapes are left alone rather than dropped or turned into a replacement byte.
expect Url.decode("%zz") == "%zz"
expect Url.decode("%") == "%"
expect Url.decode("100%") == "100%"
expect Url.decode("%2") == "%2"
expect Url.decode("50%25 off") == "50% off"

# Nothing to do: empty and unescaped values pass through.
expect Url.decode("") == ""
expect Url.decode("lessons:abc") == "lessons:abc"
expect Url.decode("agricultural_science") == "agricultural_science"
