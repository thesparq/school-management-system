## Presigned uploads to Cloudflare R2 (AWS SigV4, query-string form).
##
## R2 speaks the S3 API, so a browser can PUT an object straight at the bucket if the backend
## signs the URL first. The signature is AWS Signature Version 4: SHA-256 and HMAC-SHA256 over a
## canonical form of the request, with the credentials and an expiry carried in the query string
## (`X-Amz-Algorithm`, `X-Amz-Credential`, `X-Amz-Date`, `X-Amz-Expires`, `X-Amz-SignedHeaders`)
## and the signature itself appended as `X-Amz-Signature`.
##
## Everything here is pure string work — the clock is the caller's business, so the timestamp is
## an argument — which is what lets `R2Test.roc` reproduce AWS's published example exactly:
##
##     roc test R2Test.roc

import Sha256
import Hmac

R2 := [].{

    ## One request to sign. `amz_date` is the SigV4 timestamp form (`20130524T000000Z`);
    ## `amz_date_of` below turns an ISO-8601 instant into it.
    Request : {
        method : Str,
        host : Str,
        path : Str,
        region : Str,
        service : Str,
        access_key : Str,
        secret_key : Str,
        amz_date : Str,
        expires : U64,
    }

    ## What the endpoint knows about R2: where it lives, which bucket, and the credentials.
    UploadConfig : {
        endpoint : Str,
        bucket : Str,
        key : Str,
        access_key : Str,
        secret_key : Str,
        amz_date : Str,
        expires : U64,
    }

    ## The signed URL a browser PUTs the object to: `<endpoint>/<bucket>/<key>?<query>`.
    ##
    ## R2 wants `auto` as the region and `s3` as the service code, and the payload is the
    ## constant `UNSIGNED-PAYLOAD` because the bytes do not exist yet at signing time.
    upload_url : UploadConfig -> Str
    upload_url = |config| {
        host = host_of(config.endpoint)
        path = "/${config.bucket}/${uri_encode_path(config.key)}"
        query = presign({
            method: "PUT",
            host: host,
            path: path,
            region: "auto",
            service: "s3",
            access_key: config.access_key,
            secret_key: config.secret_key,
            amz_date: config.amz_date,
            expires: config.expires,
        })

        "${endpoint_root(config.endpoint)}${path}?${query}"
    }

    ## The query string of a presigned request, signature included. The signature is appended
    ## last and is itself not part of the canonical query string: the verifier strips it off
    ## before rebuilding the request.
    presign : Request -> Str
    presign = |request| "${query_string(request)}&X-Amz-Signature=${signature(request)}"

    ## The canonical query string: every parameter SigV4 sends, sorted by name (they already are)
    ## and percent-encoded. The credential holds slashes, so it arrives as `%2F`.
    query_string : Request -> Str
    query_string = |request| Str.join_with([
        "X-Amz-Algorithm=AWS4-HMAC-SHA256",
        "X-Amz-Credential=${uri_encode("${request.access_key}/${credential_scope(request)}")}",
        "X-Amz-Date=${request.amz_date}",
        "X-Amz-Expires=${U64.to_str(request.expires)}",
        "X-Amz-SignedHeaders=host",
    ], "&")

    ## `20130524/us-east-1/s3/aws4_request`, the tail of `X-Amz-Credential`.
    credential_scope : Request -> Str
    credential_scope = |request| "${date_stamp(request.amz_date)}/${request.region}/${request.service}/aws4_request"

    ## The canonical request, in the order the AWS documentation writes it: method, path, query,
    ## the signed headers with their values, the blank line that closes them, the list of signed
    ## header names, and the payload hash. Only `host` is signed, because a presigned upload
    ## cannot know any other header.
    canonical_request : Request -> Str
    canonical_request = |request| "${request.method}\n${request.path}\n${query_string(request)}\nhost:${request.host}\n\nhost\nUNSIGNED-PAYLOAD"

    ## The string to sign: the algorithm, the timestamp, the credential scope, and the hash of
    ## the canonical request.
    string_to_sign : Request -> Str
    string_to_sign = |request| "AWS4-HMAC-SHA256\n${request.amz_date}\n${credential_scope(request)}\n${Sha256.hex(Sha256.digest(Str.to_utf8(canonical_request(request))))}"

    ## The lowercase hex signature: HMAC-SHA-256 of the string to sign under the signing key.
    signature : Request -> Str
    signature = |request| Hmac.sha256_hex(signing_key(request), Str.to_utf8(string_to_sign(request)))

    ## The signing key: `AWS4` and the secret fed through the date, the region, the service and
    ## the `aws4_request` terminator, each step an HMAC keyed by the step before.
    signing_key : Request -> List(U8)
    signing_key = |request| {
        date_key = Hmac.sha256(Str.to_utf8("AWS4${request.secret_key}"), Str.to_utf8(date_stamp(request.amz_date)))
        region_key = Hmac.sha256(date_key, Str.to_utf8(request.region))
        service_key = Hmac.sha256(region_key, Str.to_utf8(request.service))

        Hmac.sha256(service_key, Str.to_utf8("aws4_request"))
    }

    # --- timestamps and URLs ---

    ## The `X-Amz-Date` form out of an ISO-8601 instant, as `Utc.to_iso_8601` produces it:
    ## "2013-05-24T00:00:00Z" becomes "20130524T000000Z".
    amz_date_of : Str -> Str
    amz_date_of = |iso| without_separators(iso)

    ## The `YYYYMMDD` date used in the credential scope, out of either timestamp form.
    date_stamp : Str -> Str
    date_stamp = |timestamp| match without_separators(timestamp).split_first("T") {
        Ok(at_time) => at_time.before
        Err(_) => ""
    }

    ## Drop the `-` and `:` separators an ISO-8601 instant is written with.
    without_separators : Str -> Str
    without_separators = |text| text_of(List.keep_if(Str.to_utf8(text), |byte| byte != 45 and byte != 58))

    ## The host of an endpoint URL, without the scheme or any path.
    host_of : Str -> Str
    host_of = |endpoint| {
        after_scheme = match endpoint.split_first("://") {
            Ok(at_scheme) => at_scheme.after
            Err(_) => endpoint
        }

        match after_scheme.split_first("/") {
            Ok(at_path) => at_path.before
            Err(_) => after_scheme
        }
    }

    ## The endpoint without a trailing slash, so the object's path can follow it directly.
    endpoint_root : Str -> Str
    endpoint_root = |endpoint|
        if Str.ends_with(endpoint, "/") {
            Str.drop_suffix(endpoint, "/")
        } else {
            endpoint
        }

    # --- percent-encoding ---

    ## Encode one query value: every byte except the unreserved characters (`A-Za-z0-9-_.~`)
    ## becomes `%XX` with uppercase hex. A space is `%20`, not `+`, and the slashes inside the
    ## credential are encoded like any other reserved byte.
    uri_encode : Str -> Str
    uri_encode = |text| encode(Str.to_utf8(text), Bool.False, [])

    ## Encode a path: the same rule, except that `/` separates the key's segments and stays.
    uri_encode_path : Str -> Str
    uri_encode_path = |text| encode(Str.to_utf8(text), Bool.True, [])

    encode : List(U8), Bool, List(U8) -> Str
    encode = |remaining, keep_slashes, out| match remaining {
        [] => text_of(out)
        [byte, .. as rest] =>
            if unreserved(byte) or (keep_slashes and byte == 47) {
                encode(rest, keep_slashes, out.append(byte))
            } else {
                encode(rest, keep_slashes, out.append(37).append(hex_digit(U8.shr_wrap(byte, 4))).append(hex_digit(U8.bitwise_and(byte, 0x0F))))
            }
    }

    unreserved : U8 -> Bool
    unreserved = |byte| {
        (byte >= 65 and byte <= 90) or (byte >= 97 and byte <= 122) or (byte >= 48 and byte <= 57) or byte == 45 or byte == 46 or byte == 95 or byte == 126
    }

    ## Uppercase hex digits, as SigV4's encoding rules require.
    hex_digit : U8 -> U8
    hex_digit = |nibble| if nibble < 10 { nibble + 48 } else { nibble + 55 }

    text_of : List(U8) -> Str
    text_of = |bytes| match Str.from_utf8(bytes) {
        Ok(text) => text
        Err(_) => ""
    }
}
