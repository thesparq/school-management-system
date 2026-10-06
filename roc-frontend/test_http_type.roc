app [Model, Msg, init, update, render, subscriptions] {
    pf: platform "https://github.com/niclas-ahden/joy/releases/download/0.33.0/9UWLeQeJEUkXNGmZtibc1aqpL3gm6Li65GvXxsML5vFz.tar.zst",
    html: "https://github.com/niclas-ahden/joy-html/releases/download/0.16.0/56NBT6VkQ5xm87Wjzcv9mRuNT4RACiAmuAmPbXwc8cuk.tar.zst"
}
import pf.Http
import html.Html exposing [Html]

Model : {}
Msg : [A Http.Response]

init : Str -> (Model, List (pf.Effect.Effect Msg))
init = \_ -> ({}, [])

update : Model, Msg -> (Model, List (pf.Effect.Effect Msg))
update = \m, _ -> (m, [])

render : Model -> Html Msg
render = \_ -> Html.text("hello")

subscriptions : Model -> List (pf.Effect.Effect Msg)
subscriptions = \_ -> []
