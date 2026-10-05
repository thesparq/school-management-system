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
    encode : Str => Str
    encode = |input| {
        encoded = encode_bytes(Str.to_utf8(input), [])

        match Str.from_utf8(encoded) {
            Ok(text) => text
            Err(_) => "",
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
    }

