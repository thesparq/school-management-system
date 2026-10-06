# roc-backend

The school app's backend: one Roc program on the [`basic-webserver`](https://github.com/roc-lang/basic-webserver)
platform that serves the JSON API *and* the built frontend bundle, so the whole app is one process
with no separate web server. Every route is in `main.roc`; the pieces it needs sit beside it —
`SurrealDB.roc` and `Authentik.roc` are the two services it talks to, `R2.roc` signs the passport-photo
uploads, and `AuthUrls.roc`, `Base64.roc`, `Hmac.roc`, `Sha256.roc` and `Url.roc` are the small pure
helpers those build on. `Golem.roc` is the last of the retired MoonBit agent stack: only the
`/api/enroll` prototype calls it. Configuration comes entirely from the environment (see
`.env.example`), and `../docs/architecture.md` holds the boundaries, the auth and storage rules, and
the invariants.

## Check it

```sh
roc check main.roc     # 0 errors and 3 warnings is the expected result
```

Use the compiler nightly pinned in `../Dockerfile.app`; a `roc` from another channel may disagree
about the platform and package URLs the file header names.

## Test it

```sh
roc test Base64Test.roc    # one `*Test.roc` file at a time
```

`AuthUrlsTest.roc`, `Base64Test.roc`, `HmacTest.roc`, `R2Test.roc`, `Sha256Test.roc` and
`UrlTest.roc` are standalone programs with the unit tests for the module beside them. Each one runs
on its own; `roc test` takes a single file. The signing ones carry published vectors: RFC 4231's HMAC
cases (`HmacTest.roc`) and AWS's worked SigV4 presign example (`R2Test.roc`).

## Build it

```sh
roc build main.roc     # writes ./main (gitignored), a static binary
```

`../Dockerfile.app` does the same build for deployment, after building the frontend bundle.

## Run it locally

The binary reads everything at startup from the environment, so it needs a SurrealDB and an Authentik
to talk to — `../devops/docker-compose.yml` describes the deployed pair, and `../docs/architecture.md`
says which one holds what. Then:

```sh
cp .env.example .env       # placeholders; fill in the values you have
set -a; . ./.env; set +a
roc run main.roc
```

`../roc-frontend/build.roc` writes the bundle it serves into `../roc-frontend/www` (`STATIC_DIR`). It
listens on `http://127.0.0.1:8000` by default; `BIND_HOST=0.0.0.0` is what a container or another
network namespace needs. With `DEV_MODE=true` a `dev-skip` token is enough to call the API, so local
work and the sandbox suites need no Authentik login — production runs `false`, which turns that
bypass off.
