app [main] {
    pf: platform "https://github.com/niclas-ahden/joy/releases/download/0.33.0/9UWLeQeJEUkXNGmZtibc1aqpL3gm6Li65GvXxsML5vFz.tar.zst",
}
import pf.Http exposing [Response]
import pf.Effect exposing [Effect]

Model : { students : Str }
Msg : [Fetched(Result(Response, [HttpErr([Timeout, NetworkError])]))]

init : Str -> (Model, List(Effect(Msg)))
init = |_| ({ students: "" }, [])

main = init
