module [view]

import html.Html
import html.Attribute
import UI
import State exposing [Model, Msg]

view = |_model| {
    Html.div([Attribute.class("p-6 md:p-8 space-y-6")], [
        Html.div([], [
            Html.h1([Attribute.class("text-3xl font-bold tracking-tight")], [Html.text("Messaging")]),
            Html.p([Attribute.class("text-muted-foreground mt-1")], [Html.text("School announcements and messages.")])
        ]),
        Html.div([Attribute.class("grid md:grid-cols-3 gap-6 h-96")], [
            # Rooms sidebar
            Html.div([Attribute.id("matrix-rooms"), Attribute.class("border rounded-lg bg-card overflow-y-auto p-4 space-y-2")], [
                Html.p([Attribute.class("text-sm font-medium text-muted-foreground mb-3")], [Html.text("Channels")]),
                Html.div([Attribute.id("matrix-rooms-list"), Attribute.class("space-y-1")], [
                    Html.p([Attribute.class("text-sm text-muted-foreground italic")], [Html.text("Loading channels...")])
                ])
            ]),
            # Chat area
            Html.div([Attribute.class("md:col-span-2 flex flex-col border rounded-lg bg-card overflow-hidden")], [
                Html.div([Attribute.id("matrix-room-name"), Attribute.class("p-4 border-b font-medium text-sm")], [Html.text("Select a channel")]),
                Html.div([Attribute.id("matrix-messages"), Attribute.class("flex-1 overflow-y-auto p-4 space-y-3")], [
                    Html.p([Attribute.class("text-sm text-muted-foreground italic text-center py-8")], [Html.text("No channel selected")])
                ]),
                Html.div([Attribute.class("p-4 border-t flex gap-2")], [
                    Html.input([
                        Attribute.id("matrix-input"),
                        Attribute.class("flex-1 border rounded-md px-3 py-2 text-sm bg-background"),
                        Attribute.placeholder("Type a message...")
                    ]),
                    Html.button([
                        Attribute.id("matrix-send-btn"),
                        Attribute.class("px-4 py-2 bg-primary text-primary-foreground rounded-md text-sm font-medium hover:bg-primary/90 cursor-pointer")
                    ], [Html.text("Send")])
                ])
            ])
        ])
    ])
}
