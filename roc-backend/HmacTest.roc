## HMAC-SHA-256 tests: RFC 4231's cases 1-4 and its long-key case 6.
##
## Case 6 is the one that exercises the key-hashing branch (a 131-byte key, longer than the
## 64-byte block). Case 5 is the truncated-output case, which HMAC-SHA-256 does not produce.
##
##     roc test HmacTest.roc

import Hmac
import Sha256

HmacTest := [].{}

# RFC 4231 case 1: a 20-byte key of 0x0b, data "Hi There".
expect Hmac.sha256_hex(List.repeat(0x0b, 20), Str.to_utf8("Hi There")) == "b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7"

# RFC 4231 case 2: the key is shorter than the block, so the zero padding is exercised.
expect Hmac.sha256_hex(Str.to_utf8("Jefe"), Str.to_utf8("what do ya want for nothing?")) == "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843"

# RFC 4231 case 3: a 20-byte key of 0xaa, 50 bytes of 0xdd.
expect Hmac.sha256_hex(List.repeat(0xaa, 20), List.repeat(0xdd, 50)) == "773ea91e36800e46854db8ebd09181a72959098b3ef8c122d9635514ced565fe"

# RFC 4231 case 4: a 25-byte key, sequential from 0x01, 50 bytes of 0xcd.
expect Hmac.sha256_hex([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25], List.repeat(0xcd, 50)) == "82558a389a443c0ea4cc819899f2083a85f0faa3e578f8077a2e3ff46729665b"

# RFC 4231 case 6: a 131-byte key, longer than the block, so it is hashed first.
expect Hmac.sha256_hex(List.repeat(0xaa, 131), Str.to_utf8("Test Using Larger Than Block-Size Key - Hash Key First")) == "60e431591ee0b67f0d8a26aacbf5b77f8e0bc6213728c5140546040f0ee37f54"

# The unkeyed case degenerates to SHA-256 of the padded message; both produce 32 bytes.
expect List.len(Hmac.sha256([], Str.to_utf8(""))) == 32
expect Hmac.sha256_hex(Str.to_utf8("abc"), Str.to_utf8("")) == Sha256.hex(Hmac.sha256(Str.to_utf8("abc"), Str.to_utf8("")))
