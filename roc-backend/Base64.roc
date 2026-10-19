## Standard base64 (RFC 4648) encoding.
##
## Neither the standard library nor the basic-webserver platform provides base64, and the
## SurrealDB HTTP API authenticates with `Basic base64(user:password)`. Keeping the encoder
## here lets the backend build that header from environment variables at startup instead of
## depending on a pre-computed credential.

Base64 := [].{

    ## Base64 alphabet as bytes, so encoding stays byte-oriented.
    alphabet = Str.to_utf8("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/")

    ## '=' (61) fills the unused slots of a partial final group.
    pad = 61

    ## Encode text as standard base64 with padding.
    encode : Str -> Str
    encode = |input| {
        encoded = encode_bytes(Str.to_utf8(input), [])

        match Str.from_utf8(encoded) {
            Ok(text) => text
            Err(_) => "",
        }
    }

    ## Decode standard base64 (RFC 4648 §4) or its URL-safe variant (§5, which a JWT's segments use),
    ## with or without the trailing padding.
    ##
    ## Both alphabets are accepted because the two callers differ: a cached identity was written by
    ## `encode` above, while a token's payload segment is URL-safe and carries no padding. A value
    ## that does not decode — a character outside either alphabet, or bytes that are not UTF-8 — is an
    ## `Err`, never a partial result: the callers treat that as "not there" rather than as data.
    decode : Str -> [Ok(Str), Err(Str)]
    decode = |input| {
        match decode_bytes(Str.to_utf8(input), 0, 0, []) {
            Err(message) => Err(message),
            Ok(bytes) =>
                match Str.from_utf8(bytes) {
                    Ok(text) => Ok(text)
                    Err(_) => Err("base64: the decoded bytes are not UTF-8"),
                },
        }
    }

    ## Consume the UTF-8 bytes three at a time; the tail cases emit the padded final group.
    encode_bytes : List(U8), List(U8) -> List(U8)
    encode_bytes = |remaining, out|
        match remaining {
            [] => out
            [a, b, c, .. as rest] => {
                chunk = U32.bitwise_or(
                    U32.bitwise_or(U32.shl_wrap(U8.to_u32(a), 16), U32.shl_wrap(U8.to_u32(b), 8)),
                    U8.to_u32(c),
                )
                next = out
                    .append(char_at(chunk, 18))
                    .append(char_at(chunk, 12))
                    .append(char_at(chunk, 6))
                    .append(char_at(chunk, 0))

                encode_bytes(rest, next)
            }
            [a, b] => {
                chunk = U32.bitwise_or(U32.shl_wrap(U8.to_u32(a), 16), U32.shl_wrap(U8.to_u32(b), 8))

                out
                    .append(char_at(chunk, 18))
                    .append(char_at(chunk, 12))
                    .append(char_at(chunk, 6))
                    .append(pad)
            }
            [a] => {
                chunk = U32.shl_wrap(U8.to_u32(a), 16)

                out
                    .append(char_at(chunk, 18))
                    .append(char_at(chunk, 12))
                    .append(pad)
                    .append(pad)
            }
        }

        ## Select one base64 digit from a 24-bit chunk.
        char_at : U32, U8 -> U8
        char_at = |chunk, shift| {
                index = U32.to_u64(U32.bitwise_and(U32.shr_wrap(chunk, shift), 0x3F))

                match List.get(alphabet, index) {
                        Ok(digit) => digit
                        # The index is masked to 6 bits, so this branch is unreachable.
                        Err(_) => 65,
                }
        }

    ## Emit a byte as soon as eight bits are held: six bits arrive per digit, so `bits` is what the
    ## accumulator still holds — always fewer than eight when a digit arrives, hence at most one byte
    ## leaves per digit. The bits past the last complete byte of an unpadded input are dropped, which
    ## RFC 4648 §3.2 allows.
    decode_bytes : List(U8), U32, U8, List(U8) -> [Ok(List(U8)), Err(Str)]
    decode_bytes = |remaining, acc, bits, out|
        match remaining {
            [] => Ok(out)
            [byte, .. as rest] =>
                if byte == pad {
                    # Padding closes the data; base64 never resumes after it.
                    Ok(out)
                } else {
                    match sextet(byte) {
                        Err(message) => Err(message)
                        Ok(value) => {
                            held = U32.bitwise_or(U32.shl_wrap(acc, 6), value)
                            next_bits = bits + 6

                            if next_bits >= 8 {
                                shift = next_bits - 8
                                emitted = U32.to_u8_wrap(U32.shr_wrap(held, shift))
                                kept = U32.bitwise_and(held, mask_below(shift))

                                decode_bytes(rest, kept, shift, List.append(out, emitted))
                            } else {
                                decode_bytes(rest, held, next_bits, out)
                            }
                        }
                    }
                }
        }

        ## The six-bit value a digit names, in either alphabet: `+` and `-` are both 62, `/` and `_`
        ## both 63.
        sextet : U8 -> [Ok(U32), Err(Str)]
        sextet = |byte| {
            if byte >= 65 and byte <= 90 {
                Ok(U8.to_u32(byte) - 65)
            } else if byte >= 97 and byte <= 122 {
                Ok((U8.to_u32(byte) - 97) + 26)
            } else if byte >= 48 and byte <= 57 {
                Ok((U8.to_u32(byte) - 48) + 52)
            } else if byte == 43 or byte == 45 {
                Ok(62)
            } else if byte == 47 or byte == 95 {
                Ok(63)
            } else {
                Err("base64: a character outside the alphabet")
            }
        }

        ## The low `width` bits, set: 0 when the width is 0.
        mask_below : U8 -> U32
        mask_below = |width| U32.shl_wrap(1, width) - 1
    }


