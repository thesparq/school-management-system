## RFC 2104 HMAC over SHA-256.
##
## The second half of the SigV4 signing key derivation in `R2.roc`: AWS derives the signing key
## by feeding the secret through four HMAC operations and signs the string to sign with the
## result. `HmacTest.roc` carries RFC 4231's vectors:
##
##     roc test HmacTest.roc
##
## Pure, like `Sha256.roc`, so importing it adds no effect to its callers.

import Sha256

Hmac := [].{

    ## HMAC-SHA-256 of `message` under `key`, as 32 bytes.
    sha256 : List(U8), List(U8) -> List(U8)
    sha256 = |key, message| {
        key_block = sized_key(key)

        Sha256.digest(List.concat(opad(key_block), Sha256.digest(List.concat(ipad(key_block), message))))
    }

    ## HMAC-SHA-256 as 64 lowercase hex digits — the form SigV4 puts in the signature.
    sha256_hex : List(U8), List(U8) -> Str
    sha256_hex = |key, message| Sha256.hex(sha256(key, message))

    ## RFC 2104's key preparation: a key longer than the 64-byte block is hashed down to 32
    ## bytes first, and anything shorter is padded with zeros — either way the result is
    ## exactly one block.
    sized_key : List(U8) -> List(U8)
    sized_key = |key| {
        sized = if List.len(key) > 64 { Sha256.digest(key) } else { key }

        List.concat(sized, List.repeat(0, 64 - List.len(sized)))
    }

    ## The inner padding: the key block XOR 0x36.
    ipad : List(U8) -> List(U8)
    ipad = |key_block| List.map(key_block, |byte| U8.bitwise_xor(byte, 0x36))

    ## The outer padding: the key block XOR 0x5C.
    opad : List(U8) -> List(U8)
    opad = |key_block| List.map(key_block, |byte| U8.bitwise_xor(byte, 0x5C))
}
