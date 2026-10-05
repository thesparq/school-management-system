## SHA-256 tests.
##
## The vectors are published ones: the two short messages and the two multi-block messages are
## NIST's (FIPS 180-4 / the SHA test vector files), so together they cover the empty input, the
## single-block padding cases, and the two-block case where the length field needs its own block.
##
## They live in their own file because `expect` blocks that call a function are reported as build
## diagnostics when the module is imported by the app. Run them with:
##
##     roc test Sha256Test.roc

import Sha256

Sha256Test := [].{}

# FIPS 180-4 / NIST: the empty message and "abc".
expect Sha256.hex(Sha256.digest(Str.to_utf8(""))) == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
expect Sha256.hex(Sha256.digest(Str.to_utf8("abc"))) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"

# NIST's 448-bit message: 56 bytes, so the padding needs the second block.
expect Sha256.hex(Sha256.digest(Str.to_utf8("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"))) == "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1"

# NIST's 896-bit message: 112 bytes, so the message itself is two blocks.
expect Sha256.hex(Sha256.digest(Str.to_utf8("abcdefghbcdefghicdefghijdefghijkefghijklfghijklmghijklmnhijklmnoijklmnopjklmnopqklmnopqrlmnopqrsmnopqrstnopqrstu"))) == "cf5b16a778af8380036ce59e7b0492370b249b11e8f07a51afac45037afee9d1"

# The digest is 32 bytes of hex, not a string that merely looks like one.
expect List.len(Sha256.digest(Str.to_utf8("abc"))) == 32
expect Sha256.hex([0, 15, 16, 255]) == "000f10ff"
expect Sha256.hex([]) == ""
