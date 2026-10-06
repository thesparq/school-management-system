## SigV4 presign tests.
##
## The main vector is AWS's own worked example, "Authenticating Requests: Using Query Parameters
## (AWS Signature Version 4)" in the Amazon S3 API Reference: a presigned `GET /test.txt` on
## `examplebucket.s3.amazonaws.com`, signed at `20130524T000000Z` with `AKIAIOSFODNN7EXAMPLE` /
## `wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY`, for which the page publishes the canonical
## request, its hash, the string to sign and the signature (the full presigned URL is published
## too). It is the closest published example to what this module does — the same query-string
## presign, only with a GET instead of an upload's PUT — and it is checked here layer by layer.
##
## The second vector is the same algorithm over the app's own shape (an R2 endpoint, region
## `auto`, a PUT, a key with slashes in it) at the same fixed date, expected URL computed with
## an independent implementation (Python's hashlib/hmac).
##
##     roc test R2Test.roc

import R2
import Sha256

R2Test := [].{}

# The published example, as one request record.
aws_request = {
    method: "GET",
    host: "examplebucket.s3.amazonaws.com",
    path: "/test.txt",
    region: "us-east-1",
    service: "s3",
    access_key: "AKIAIOSFODNN7EXAMPLE",
    secret_key: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
    amz_date: "20130524T000000Z",
    expires: 86400,
}

# The canonical request, exactly as the AWS page prints it.
expect R2.canonical_request(aws_request) == "GET\n/test.txt\nX-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Credential=AKIAIOSFODNN7EXAMPLE%2F20130524%2Fus-east-1%2Fs3%2Faws4_request&X-Amz-Date=20130524T000000Z&X-Amz-Expires=86400&X-Amz-SignedHeaders=host\nhost:examplebucket.s3.amazonaws.com\n\nhost\nUNSIGNED-PAYLOAD"

# ... and its published SHA-256.
expect Sha256.hex(Sha256.digest(Str.to_utf8(R2.canonical_request(aws_request)))) == "3bfa292879f6447bbcda7001decf97f4a54dc650c8942174ae0a9121cf58ad04"

# The string to sign, exactly as the AWS page prints it.
expect R2.string_to_sign(aws_request) == "AWS4-HMAC-SHA256\n20130524T000000Z\n20130524/us-east-1/s3/aws4_request\n3bfa292879f6447bbcda7001decf97f4a54dc650c8942174ae0a9121cf58ad04"

# The published signature, and the published presigned URL it produces.
expect R2.signature(aws_request) == "aeeed9bbccd4d02ee5c0109b86d86835f995330da4c265957d157751f604d404"
expect "https://${aws_request.host}${aws_request.path}?${R2.presign(aws_request)}" == "https://examplebucket.s3.amazonaws.com/test.txt?X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Credential=AKIAIOSFODNN7EXAMPLE%2F20130524%2Fus-east-1%2Fs3%2Faws4_request&X-Amz-Date=20130524T000000Z&X-Amz-Expires=86400&X-Amz-SignedHeaders=host&X-Amz-Signature=aeeed9bbccd4d02ee5c0109b86d86835f995330da4c265957d157751f604d404"

# The app's own shape: R2's `auto` region, a PUT, and a key whose slashes stay in the path
# (only the credential's slashes are encoded). Expected URL from the independent implementation.
expect R2.upload_url({
    endpoint: "https://example.r2.cloudflarestorage.com",
    bucket: "test",
    key: "student/passports/abc.jpg",
    access_key: "AKIDEXAMPLE",
    secret_key: "wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY",
    amz_date: "20130524T000000Z",
    expires: 600,
}) == "https://example.r2.cloudflarestorage.com/test/student/passports/abc.jpg?X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Credential=AKIDEXAMPLE%2F20130524%2Fauto%2Fs3%2Faws4_request&X-Amz-Date=20130524T000000Z&X-Amz-Expires=600&X-Amz-SignedHeaders=host&X-Amz-Signature=713f7cb1867e0d9a6d47cfe1f312d70521ecae30ab04e8f7cd35a7fcc7dce9d3"

# A trailing slash on the endpoint does not double up in the URL, and the expiry is the caller's.
expect R2.upload_url({
    endpoint: "https://example.r2.cloudflarestorage.com/",
    bucket: "test",
    key: "student/passports/abc.jpg",
    access_key: "AKIDEXAMPLE",
    secret_key: "wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY",
    amz_date: "20130524T000000Z",
    expires: 600,
}) == R2.upload_url({
    endpoint: "https://example.r2.cloudflarestorage.com",
    bucket: "test",
    key: "student/passports/abc.jpg",
    access_key: "AKIDEXAMPLE",
    secret_key: "wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY",
    amz_date: "20130524T000000Z",
    expires: 600,
})

# ISO-8601 in, the two SigV4 timestamp forms out.
expect R2.amz_date_of("2013-05-24T00:00:00Z") == "20130524T000000Z"
expect R2.amz_date_of("2026-01-01T09:30:15Z") == "20260101T093015Z"
expect R2.date_stamp("20130524T000000Z") == "20130524"
expect R2.date_stamp("2013-05-24T00:00:00Z") == "20130524"

# Host extraction and URI encoding under SigV4's rules.
expect R2.host_of("https://example.r2.cloudflarestorage.com") == "example.r2.cloudflarestorage.com"
expect R2.host_of("https://example.r2.cloudflarestorage.com/") == "example.r2.cloudflarestorage.com"
expect R2.host_of("http://127.0.0.1:9000") == "127.0.0.1:9000"
expect R2.uri_encode("AKIDEXAMPLE/20130524/auto/s3/aws4_request") == "AKIDEXAMPLE%2F20130524%2Fauto%2Fs3%2Faws4_request"
expect R2.uri_encode("a b") == "a%20b"
expect R2.uri_encode("a+b") == "a%2Bb"
expect R2.uri_encode("-_.~") == "-_.~"
expect R2.uri_encode_path("student/passports/abc.jpg") == "student/passports/abc.jpg"
expect R2.uri_encode_path("student/passports/a b.jpg") == "student/passports/a%20b.jpg"
