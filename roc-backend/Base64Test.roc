## Base64 encoding and decoding tests.
##
## They live in their own file because `expect` blocks that call a function are reported as
## build diagnostics when the module is imported by the app. Run them with:
##
##     roc test Base64Test.roc

import Base64

Base64Test := [].{}

expect Base64.encode("") == ""
expect Base64.encode("f") == "Zg=="
expect Base64.encode("fo") == "Zm8="
expect Base64.encode("foo") == "Zm9v"
expect Base64.encode("foob") == "Zm9vYg=="
expect Base64.encode("fooba") == "Zm9vYmE="
expect Base64.encode("foobar") == "Zm9vYmFy"
expect Base64.encode("root:p@ss:word") == "cm9vdDpwQHNzOndvcmQ="
expect Base64.encode("root:S3cr3t!Pass") == "cm9vdDpTM2NyM3QhUGFzcw=="

# The decoder, against RFC 4648 §10's vectors: each one round-trips, which covers the padded tail
# cases (one and two bytes left over) rather than only whole three-byte groups.
expect Base64.decode("") == Ok("")
expect Base64.decode("Zg==") == Ok("f")
expect Base64.decode("Zm8=") == Ok("fo")
expect Base64.decode("Zm9v") == Ok("foo")
expect Base64.decode("Zm9vYg==") == Ok("foob")
expect Base64.decode("Zm9vYmE=") == Ok("fooba")
expect Base64.decode("Zm9vYmFy") == Ok("foobar")
expect Base64.decode("cm9vdDpwQHNzOndvcmQ=") == Ok("root:p@ss:word")

# A JWT segment is URL-safe and unpadded (RFC 7515 §2); both departures are the ones the cache
# depends on when it reads a token's `exp`.
expect Base64.decode("eyJhIjoxfQ") == Ok("{\"a\":1}")
expect Base64.decode("eyJhIjoxfQ==") == Ok("{\"a\":1}")
expect Base64.decode("Pz4/") == Ok("?>?")
expect Base64.decode("Pz4_") == Ok("?>?")
expect Base64.decode("Pz5+") == Ok("?>~")
expect Base64.decode("Pz5-") == Ok("?>~")

# Decoding is the inverse of encoding for text that is not valid UTF-8 once split, so the two uses
# that matter here — a JSON body with quotes, and a name outside ASCII — survive the round trip.
expect Base64.decode(Base64.encode("{\"sub\":\"a b\",\"groups\":[\"Students\"]}")) == Ok("{\"sub\":\"a b\",\"groups\":[\"Students\"]}")
expect Base64.decode(Base64.encode("Ọláyínká Àjàyí")) == Ok("Ọláyínká Àjàyí")

# What cannot be decoded is an Err, never a partial result: a character outside either alphabet,
# and bytes that decode to something that is not UTF-8 (0xFF alone).
expect Base64.decode("Zm9v!") == Err("base64: a character outside the alphabet")
expect Base64.decode("Zm9vYmFy=") == Ok("foobar")
expect Base64.decode("/w==") == Err("base64: the decoded bytes are not UTF-8")
