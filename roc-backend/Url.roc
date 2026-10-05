## Percent-decoding for query parameter values.
##
## The API takes record ids as query values (`?lesson_id=lessons:abc`), and a colon is not a legal
## query value: a conforming client sends `lessons%3Aabc` instead. Reading the value raw looks up a
## record literally named `lessons%3Aabc` and finds nothing, so `query_param` in `main.roc` decodes
## every value through here first.
##
## No HTTP in it, so `roc test UrlTest.roc` covers the rule cleanly.

Url := [].{
    ## Percent-decode one query component: `%XX` (upper- or lowercase hex) becomes the byte it names
    ## and `+` becomes a space. Malformed escapes stay literal — a value that merely contains `%`
    ## (`100%`, `%zz`) is passed through unchanged — and a decoded byte sequence that is not valid
    ## UTF-8 keeps the undecoded input, since a record id is text either way.
    decode : Str -> Str
    decode = |text| {
        decoded = decode_bytes(Str.to_utf8(text), [])

        match Str.from_utf8(decoded) {
            Ok(result) => result
            Err(_) => text
        }
    }

    ## Walk the bytes once, emitting each one either decoded or as it stands.
    decode_bytes : List(U8), List(U8) -> List(U8)
    decode_bytes = |remaining, out|
        match remaining {
            [] => out
            # 37 is '%': the escape needs two hex digits after it.
            [37, hi, lo, .. as rest] =>
                match hex_value(hi, lo) {
                    Ok(byte) => decode_bytes(rest, out.append(byte))
                    # Not an escape: keep the '%' and both bytes, and carry on after the '%' so a
                    # later valid escape in the same value still decodes.
                    Err(_) => decode_bytes(rest, out.append(37).append(hi).append(lo))
                }
            # A '%' with fewer than two bytes left (`100%`, `%2`) is literal too.
            [37, .. as rest] => decode_bytes(rest, out.append(37))
            # 43 is '+': the form encoding of a space in the query part.
            [43, .. as rest] => decode_bytes(rest, out.append(32))
            [byte, .. as rest] => decode_bytes(rest, out.append(byte))
        }

    ## The byte one hex digit names, or `Err` when it is not a hex digit at all.
    hex_digit : U8 -> [Ok(U8), Err({})]
    hex_digit = |byte|
        if byte >= 48 and byte <= 57 {
            Ok(byte - 48)
        } else if byte >= 97 and byte <= 102 {
            Ok(byte - 87)
        } else if byte >= 65 and byte <= 70 {
            Ok(byte - 55)
        } else {
            Err({})
        }

    ## The byte a two-digit hex escape names.
    hex_value : U8, U8 -> [Ok(U8), Err({})]
    hex_value = |hi, lo|
        match hex_digit(hi) {
            Ok(high) =>
                match hex_digit(lo) {
                    # Each digit is at most 15, so the sum fits a byte.
                    Ok(low) => Ok((16 * high) + low)
                    Err(_) => Err({})
                }
            Err(_) => Err({})
        }
}
