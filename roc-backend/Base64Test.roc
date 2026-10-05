## Base64 encoding tests.
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
