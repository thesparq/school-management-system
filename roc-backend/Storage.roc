## Cloudflare R2 through the app's own hands: the one write the backend makes to the store itself.
##
## An upload is the browser's: the backend signs a URL (`R2.roc`) and the page PUTs the photo at it. A
## delete is different — it is the school's decision, made from a screen an administrator opened, so the
## backend sends it with the credential it already holds rather than handing the page anything.

import http.Request
import http.Response
import pf.Http

Storage := [].{

    ## Take one object out of the bucket. `Ok({})` only for the two statuses S3 answers a successful
    ## delete with (204, or 200 when it echoes the request), so the caller reads a single verdict and
    ## its refusal carries what went wrong.
    delete! : Str => [Ok({}), Err(Str)]
    delete! = |delete_url| {
        match Http.send!(Request.with_uri(Request.from_method(DELETE), delete_url)) {
            Err(_) => Err("the store could not be reached"),
            Ok(response) =>
                if Response.status(response) == 204 or Response.status(response) == 200 {
                    Ok({})
                } else {
                    Err("HTTP ${U16.to_str(Response.status(response))}")
                },
        }
    }
}
