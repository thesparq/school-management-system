## FIPS 180-4 SHA-256.
##
## Signing an R2 upload is AWS SigV4, which needs SHA-256 and HMAC-SHA256, and neither the
## standard library nor the basic-webserver platform provides them. The implementation is the
## paper algorithm — message schedule, compression function, padding — so it can be checked
## line by line against the published vectors in `Sha256Test.roc`:
##
##     roc test Sha256Test.roc
##
## Everything here is pure (`->`, not `=>`), so importing it adds no effect to its callers and
## the tests report no effectful-expect diagnostics.

Sha256 := [].{

    ## SHA-256 of `message`, as 32 bytes.
    digest : List(U8) -> List(U8)
    digest = |message| {
        state = List.fold(List.chunks_of(pad(message), 64), initial_state, compress)

        state_bytes(state)
    }

    ## The digest of `message` as 64 lowercase hex digits — the form SigV4 publishes a signature in.
    hex : List(U8) -> Str
    hex = |bytes| {
        digits = List.fold(bytes, [], |out, byte| out.append(digit(U8.shr_wrap(byte, 4))).append(digit(U8.bitwise_and(byte, 0x0F))))

        text_of(digits)
    }

    # --- constants ---

    ## The initial hash state: the first 32 bits of the fractional parts of the square roots of
    ## the first eight primes (2, 3, 5, 7, 11, 13, 17, 19).
    initial_state : List(U32)
    initial_state = [
        0x6a09e667,
        0xbb67ae85,
        0x3c6ef372,
        0xa54ff53a,
        0x510e527f,
        0x9b05688c,
        0x1f83d9ab,
        0x5be0cd19,
    ]

    ## The round constants: the first 32 bits of the fractional parts of the cube roots of the
    ## first sixty-four primes.
    constants : List(U32)
    constants = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
        0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
        0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
        0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
        0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
    ]

    # --- padding ---

    ## Append the `0x80` marker, the zeros that take the length to 56 mod 64, and the message
    ## length in bits as a big-endian 64-bit integer, so the result is whole 64-byte blocks.
    pad : List(U8) -> List(U8)
    pad = |message| {
        length = List.len(message)
        remainder = length % 64
        zeros = if remainder < 56 { 55 - remainder } else { 119 - remainder }

        List.concat(List.concat(message, List.concat([128], List.repeat(0, zeros))), length_bytes(8 * length))
    }

    ## The message length as eight big-endian bytes.
    length_bytes : U64 -> List(U8)
    length_bytes = |bits| [
        U64.to_u8_wrap(U64.shr_wrap(bits, 56)),
        U64.to_u8_wrap(U64.shr_wrap(bits, 48)),
        U64.to_u8_wrap(U64.shr_wrap(bits, 40)),
        U64.to_u8_wrap(U64.shr_wrap(bits, 32)),
        U64.to_u8_wrap(U64.shr_wrap(bits, 24)),
        U64.to_u8_wrap(U64.shr_wrap(bits, 16)),
        U64.to_u8_wrap(U64.shr_wrap(bits, 8)),
        U64.to_u8_wrap(bits),
    ]

    # --- compression ---

    ## The eight working registers of one block, threaded through its sixty-four rounds.
    Registers : {
        a : U32,
        b : U32,
        c : U32,
        d : U32,
        e : U32,
        f : U32,
        g : U32,
        h : U32,
    }

    ## Compress one 64-byte block into the state.
    compress : List(U32), List(U8) -> List(U32)
    compress = |state, block| {
        schedule = message_schedule(block)

        add_state(state, rounds(0, registers(state), schedule))
    }

    ## The working registers start as the state's eight words ...
    registers : List(U32) -> Registers
    registers = |state| match state {
        [a, b, c, d, e, f, g, h] => { a: a, b: b, c: c, d: d, e: e, f: f, g: g, h: h }
        _ => { a: 0, b: 0, c: 0, d: 0, e: 0, f: 0, g: 0, h: 0 }
    }

    ## ... and are added back into it, modulo 2^32, when the block is done.
    add_state : List(U32), Registers -> List(U32)
    add_state = |state, r| match state {
        [a, b, c, d, e, f, g, h] => [
            U32.plus_wrap(a, r.a),
            U32.plus_wrap(b, r.b),
            U32.plus_wrap(c, r.c),
            U32.plus_wrap(d, r.d),
            U32.plus_wrap(e, r.e),
            U32.plus_wrap(f, r.f),
            U32.plus_wrap(g, r.g),
            U32.plus_wrap(h, r.h),
        ]
        _ => state
    }

    ## The sixty-four rounds of one block.
    rounds : U64, Registers, List(U32) -> Registers
    rounds = |index, regs, schedule|
        if index >= 64 {
            regs
        } else {
            rounds(index + 1, round(index, regs, schedule), schedule)
        }

    ## One round. The two words from outside the registers are the schedule's and the round
    ## constant's, both at `index`.
    round : U64, Registers, List(U32) -> Registers
    round = |index, regs, schedule| {
        e = regs.e
        t1 = sum([
            regs.h,
            big_sigma1(e),
            choose(e, regs.f, regs.g),
            word_at(constants, index),
            word_at(schedule, index),
        ])
        t2 = U32.plus_wrap(big_sigma0(regs.a), majority(regs.a, regs.b, regs.c))

        {
            a: U32.plus_wrap(t1, t2),
            b: regs.a,
            c: regs.b,
            d: regs.c,
            e: U32.plus_wrap(regs.d, t1),
            f: regs.e,
            g: regs.f,
            h: regs.g,
        }
    }

    ## The block's first sixteen words, then the schedule grown to sixty-four.
    message_schedule : List(U8) -> List(U32)
    message_schedule = |block| extend(List.map(List.chunks_of(block, 4), word_of), 16)

    ## Four big-endian bytes as one word.
    word_of : List(U8) -> U32
    word_of = |chunk| match chunk {
        [a, b, c, d] => U32.bitwise_or(U32.shl_wrap(U8.to_u32(a), 24), U32.bitwise_or(U32.shl_wrap(U8.to_u32(b), 16), U32.bitwise_or(U32.shl_wrap(U8.to_u32(c), 8), U8.to_u32(d))))
        _ => 0
    }

    ## Grow the schedule to sixty-four words: W[t] = s1(W[t-2]) + W[t-7] + s0(W[t-15]) + W[t-16].
    extend : List(U32), U64 -> List(U32)
    extend = |words, index|
        if index >= 64 {
            words
        } else {
            extend(words.append(next_word(words, index)), index + 1)
        }

    next_word : List(U32), U64 -> U32
    next_word = |words, index| sum([
        word_at(words, index - 16),
        small_sigma0(word_at(words, index - 15)),
        word_at(words, index - 7),
        small_sigma1(word_at(words, index - 2)),
    ])

    ## The word at `index`. The schedule and the constants are exactly sixty-four long, so the
    ## out-of-range arm is never reached.
    word_at : List(U32), U64 -> U32
    word_at = |words, index| match List.get(words, index) {
        Ok(word) => word
        Err(_) => 0
    }

    # --- the round functions ---

    ## Ch(x, y, z): (x & y) ^ (~x & z).
    choose : U32, U32, U32 -> U32
    choose = |x, y, z| U32.bitwise_xor(U32.bitwise_and(x, y), U32.bitwise_and(U32.bitwise_not(x), z))

    ## Maj(x, y, z): (x & y) ^ (x & z) ^ (y & z).
    majority : U32, U32, U32 -> U32
    majority = |x, y, z| U32.bitwise_xor(U32.bitwise_xor(U32.bitwise_and(x, y), U32.bitwise_and(x, z)), U32.bitwise_and(y, z))

    ## Sigma0(x): rotr(x, 2) ^ rotr(x, 13) ^ rotr(x, 22).
    big_sigma0 : U32 -> U32
    big_sigma0 = |x| xor3(rotr(x, 2), rotr(x, 13), rotr(x, 22))

    ## Sigma1(x): rotr(x, 6) ^ rotr(x, 11) ^ rotr(x, 25).
    big_sigma1 : U32 -> U32
    big_sigma1 = |x| xor3(rotr(x, 6), rotr(x, 11), rotr(x, 25))

    ## sigma0(x): rotr(x, 7) ^ rotr(x, 18) ^ shr(x, 3).
    small_sigma0 : U32 -> U32
    small_sigma0 = |x| xor3(rotr(x, 7), rotr(x, 18), U32.shr_wrap(x, 3))

    ## sigma1(x): rotr(x, 17) ^ rotr(x, 19) ^ shr(x, 10).
    small_sigma1 : U32 -> U32
    small_sigma1 = |x| xor3(rotr(x, 17), rotr(x, 19), U32.shr_wrap(x, 10))

    xor3 : U32, U32, U32 -> U32
    xor3 = |x, y, z| U32.bitwise_xor(U32.bitwise_xor(x, y), z)

    ## A 32-bit rotation right; there is no rotate primitive, so the bits come back through a
    ## shift in the other direction.
    rotr : U32, U8 -> U32
    rotr = |x, n| U32.bitwise_or(U32.shr_wrap(x, n), U32.shl_wrap(x, 32 - n))

    ## Add a list of words modulo 2^32.
    sum : List(U32) -> U32
    sum = |words| List.fold(words, 0, |total, word| U32.plus_wrap(total, word))

    # --- output ---

    ## The state's eight words as the digest's 32 bytes, big-endian.
    state_bytes : List(U32) -> List(U8)
    state_bytes = |state| List.fold(state, [], |out, word| List.concat(out, bytes_of(word)))

    bytes_of : U32 -> List(U8)
    bytes_of = |word| [
        U32.to_u8_wrap(U32.shr_wrap(word, 24)),
        U32.to_u8_wrap(U32.shr_wrap(word, 16)),
        U32.to_u8_wrap(U32.shr_wrap(word, 8)),
        U32.to_u8_wrap(word),
    ]

    ## One lowercase hex digit per nibble.
    digit : U8 -> U8
    digit = |nibble| if nibble < 10 { nibble + 48 } else { nibble + 87 }

    text_of : List(U8) -> Str
    text_of = |bytes| match Str.from_utf8(bytes) {
        Ok(text) => text
        Err(_) => ""
    }
}
