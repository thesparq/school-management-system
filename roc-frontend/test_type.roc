app [main] {
    pf: platform "https://github.com/niclas-ahden/joy/releases/download/0.33.0/9UWLeQeJEUkXNGmZtibc1aqpL3gm6Li65GvXxsML5vFz.tar.zst",
}
import pf.Http
main = Http.get("http://localhost", |res| res)
