
import html.Html exposing [div, h3, p, aside, nav, a, input, label, text, element]
import html.Attribute exposing [Attribute, aria, attribute, class, data, disabled, href, on_click, on_input, on_key, on_submit, placeholder, prevent_default, role, tabindex, type, value]
UI := [].{

# --- ICONS ---

# One inline SVG from the Lucide set (MIT), drawn with `currentColor` so it follows the surrounding
# text colour. The same stroke style everywhere is what keeps the UI uniform; `name` is a key from
# `icon_paths`, with a nearly-invisible fallback for anything not listed. The size is the caller's
# classes ("w-4 h-4", "h-5 w-5", ...).
icon : Str, Str -> Html(msg)
icon = |name, classes| {
    (viewbox, paths) = icon_paths(name)
    element(
        "svg",
        [
            class("${classes} shrink-0"),
            attribute("viewBox", viewbox),
            attribute("fill", "none"),
            attribute("stroke", "currentColor"),
            attribute("stroke-width", "2"),
            attribute("stroke-linecap", "round"),
            attribute("stroke-linejoin", "round"),
            attribute("aria-hidden", "true"),
        ],
        List.map(paths, |path_d| element("path", [attribute("d", path_d)], [])),
    )
}

# The Lucide paths per icon: `(viewBox, List(path d strings)`. Kept to the icons this app calls.
icon_paths : Str -> (Str, List(Str))
icon_paths = |name| {
    match name {
        "plus" => ("0 0 24 24", ["M5 12h14", "M12 5v14"])
        "x" => ("0 0 24 24", ["M18 6 6 18", "m6 6 12 12"])
        "users" => ("0 0 24 24", ["M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2", "M9 7a4 4 0 1 0 0 8 4 4 0 0 0 0-8", "M22 21v-2a4 4 0 0 0-3-3.87", "M16 3.13a4 4 0 0 1 0 7.75"])
        "graduation-cap" => ("0 0 24 24", ["M21.42 10.92a1 1 0 0 0-.42-.92l-8.58-5.72a2 2 0 0 0-2.84 0L1.58 10a1 1 0 0 0 0 1.67l2.92 1.94", "M22 10v6", "M6 12.5V16a6 3 0 0 0 12 0v-3.5"])
        "presentation" => ("0 0 24 24", ["M2 3h20", "M21 3v7a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V3", "M7 21l5-5 5 5"])
        "shield" => ("0 0 24 24", ["M20 13c0 5-3.5 7.5-7.66 8.95a1 1 0 0 1-.67-.01C7.5 20.5 4 18 4 13V6a1 1 0 0 1 1-1c2.2 0 4-1.5 5-4 1 2.5 2.8 4 5 4a1 1 0 0 1 1 1z"])
        "camera" => ("0 0 24 24", ["M14.5 4h-5L7 7H4a2 2 0 0 0-2 2v9a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2V9a2 2 0 0 0-2-2h-3l-2.5-3z", "M15 13a3 3 0 1 1-6 0 3 3 0 0 1 6 0z"])
        "key" => ("0 0 24 24", ["M2.586 17.414A2 2 0 0 0 2 18.828V21a1 1 0 0 0 1 1h3a1 1 0 0 0 1-1v-1a1 1 0 0 1 1-1h1a1 1 0 0 0 1-1v-1a1 1 0 0 1 1-1h.172a2 2 0 0 0 1.414-.586l.814-.814a6.5 6.5 0 1 0-4-4z", "M16.5 8a.5.5 0 1 0 0 1 .5.5 0 0 0 0-1"])
        "pencil" => ("0 0 24 24", ["M17 3a2.85 2.83 0 1 1 4 4L7.5 20.5 2 22l1.5-5.5Z"])
        "trash" => ("0 0 24 24", ["M3 6h18", "M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6", "M8 6V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"])
        "folder" => ("0 0 24 24", ["M20 7a2 2 0 0 1 2 2v10a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h5l3 3h8a2 2 0 0 1 2 2z"])
        "book-open" => ("0 0 24 24", ["M12 7v14", "M3 18a1 1 0 0 1-1-1V4a1 1 0 0 1 1-1h5a4 4 0 0 1 4 4 4 4 0 0 1 4-4h5a1 1 0 0 1 1 1v13a1 1 0 0 1-1 1h-6a3 3 0 0 0-3 3 3 3 0 0 0-3-3z"])
        "calendar" => ("0 0 24 24", ["M8 2v4", "M16 2v4", "M3 10h18", "M21 6v14a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"])
        _ => ("0 0 24 24", ["M12 8v.01", "M12 12v.01", "M12 16v.01"])
    }
}


# --- BUTTON ---

default_button = {
	variant: Primary,
	size: Default,
	on_click: None,
	is_disabled: Bool.False,
	classes: "",
	# Whether this button submits the form it sits in. A submit button is what the browser's own
	# Enter key presses, so a form whose fields are typed into needs exactly one (see `form`).
	is_submit: Bool.False,
}

button = |config, children| {
	base_classes = "inline-flex items-center justify-center rounded-md text-sm font-medium transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 disabled:opacity-50 disabled:pointer-events-none ring-offset-background"
	
	variant_classes =
		match config.variant {
			Primary => "bg-primary text-primary-foreground hover:bg-primary/90"
			Secondary => "bg-secondary text-secondary-foreground hover:bg-secondary/80"
			Destructive => "bg-destructive text-destructive-foreground hover:bg-destructive/90"
			Outline => "border border-input hover:bg-accent hover:text-accent-foreground"
			Ghost => "hover:bg-accent hover:text-accent-foreground"
			Link => "underline-offset-4 hover:underline text-primary"
		}
	
	size_classes =
		match config.size {
			Default => "h-10 py-2 px-4"
			Sm => "h-9 px-3 rounded-md"
			Lg => "h-11 px-8 rounded-md"
			Icon => "h-10 w-10"
		}
	
	final_classes = Str.join_with([base_classes, variant_classes, size_classes, config.classes], " ")
	
	# A `<button>` unless the form it sits in says otherwise: `is_submit: Bool.True` makes it that
	# form's submit button — the one the browser's own Enter key presses (see `form`).
	# `default_button` leaves it False, so only the buttons that send a form set it.
	attrs = [class(final_classes), type(if config.is_submit { "submit" } else { "button" })]
	
	attrs_with_click =
		match config.on_click {
			None => attrs
			Click(msg) => List.append(attrs, on_click(msg))
		}
		
	final_attrs =
		if config.is_disabled {
			List.append(attrs_with_click, disabled(Bool.True))
		} else {
			attrs_with_click
		}
			
	Html.button(final_attrs, children)
}


# --- CARD ---

default_card = { classes: "" }

card = |config, children| {
	final_classes = Str.join_with(["rounded-xl border border-border bg-card text-card-foreground shadow", config.classes], " ")
	div([class(final_classes)], children)
}

card_header = |config, children| {
	final_classes = Str.join_with(["flex flex-col space-y-1.5 p-6", config.classes], " ")
	div([class(final_classes)], children)
}

card_title = |config, children| {
	final_classes = Str.join_with(["font-semibold leading-none tracking-tight", config.classes], " ")
	h3([class(final_classes)], children)
}

card_content = |config, children| {
	# `pt-0` is for content that follows a card header. It is emitted after `p-*` and `py-*`, so it wins
	# over a top padding passed in `classes`: a header-less card has to give its content its own padding
	# (as the signed-out dashboard does) rather than pass one here.
	final_classes = Str.join_with(["p-6 pt-0", config.classes], " ")
	div([class(final_classes)], children)
}


# --- BADGE ---

default_badge = {
	variant: Default,
	classes: "",
}

badge = |config, children| {
	base_classes = "inline-flex items-center border rounded-full px-2.5 py-0.5 text-xs font-semibold transition-colors focus:outline-none focus:ring-2 focus:ring-ring focus:ring-offset-2"
	
	variant_classes =
		match config.variant {
			Default => "bg-primary hover:bg-primary/80 border-transparent text-primary-foreground"
			Secondary => "bg-secondary hover:bg-secondary/80 border-transparent text-secondary-foreground"
			Destructive => "bg-destructive hover:bg-destructive/80 border-transparent text-destructive-foreground"
			Outline => "text-foreground"
		}
	
	final_classes = Str.join_with([base_classes, variant_classes, config.classes], " ")
	div([class(final_classes)], children)
}

# --- INPUT ---

default_input = {
	type: "text",
	value: "",
	placeholder: "",
	on_input: None,
	is_disabled: Bool.False,
	classes: "",
}

input = |config| {
	base_classes = "flex h-10 w-full rounded-md border border-input bg-background px-3 py-2 text-sm ring-offset-background file:border-0 file:bg-transparent file:text-sm file:font-medium placeholder:text-muted-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 disabled:cursor-not-allowed disabled:opacity-50"
	
	final_classes = Str.join_with([base_classes, config.classes], " ")
	
	attrs = [
		class(final_classes), 
		type(config.type),
		value(config.value),
		placeholder(config.placeholder)
	]
	
	attrs_with_input =
		match config.on_input {
			None => attrs
			Input(msg_fn) => List.append(attrs, on_input(msg_fn))
		}
		
	final_attrs =
		if config.is_disabled {
			List.append(attrs_with_input, disabled(Bool.True))
		} else {
			attrs_with_input
		}
			
	Html.input(final_attrs)
}

# --- KEYBOARD ---
# Every control a pointer can work has to work from the keyboard too, and the rule is the same
# everywhere: Tab reaches it, Enter and Space do what a click does, and Escape backs out of
# whatever is on top of the page (that one is the app's own subscription — see app.roc). Native
# controls get all of it for free, which is why this app uses a `<button>`, an `<a href>`, an
# `<input>`, a `<select>` and a real `<form>` wherever it can. The helpers below are for the
# places where the markup has to be a `div` or a `span`: a card that opens a page, a tab, a
# badge's ✕, one row of a search dropdown.

# The ring a focused control draws, so a keyboard user can see where they are: the same one the
# buttons draw, so the whole app marks the keyboard the same way.
focus_ring = "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2"

# What Enter and Space mean on a control that is not a `<button>`: the same thing a click means.
# The filter runs in the browser (the platform's `on_key`), and `prevent_default` stops the two
# keys' own defaults — Space scrolling the page, Enter submitting the form the control may sit in
# — so a press can only ever activate the control once.
activation_keys = ["Enter", " "]

# The attributes of a control that behaves like a button. `label` is its accessible name: set it
# whenever the children are not already the words of the action (a bare ✕, a badge). `is_nav` marks
# a control whose press changes the view without a page load, which is what the page's own
# JavaScript reads to start the top border progress bar (the same marker the sidebar items carry).
pressable_attrs : Str, Str, Bool, msg -> List(Attribute(msg))
pressable_attrs = |classes, label, is_nav, msg| {
	base = [
		class(Str.join_with([focus_ring, "cursor-pointer", classes], " ")),
		role("button"),
		tabindex(0),
		on_click(msg),
		prevent_default(on_key("keydown", activation_keys, |_| msg)),
	]
	named = if Str.is_empty(label) { base } else { List.append(base, aria("label", label)) }
	if is_nav { List.append(named, data("nav", "")) } else { named }
}

default_pressable = { classes: "", label: "", is_nav: Bool.False }

# A `div` that behaves like a button: in the tab order, announced as a button, activated by Enter
# or Space as well as by a click. `msg` is the message itself, not a `Click(...)` wrapper (see
# `link`).
pressable = |config, msg, children| {
	Html.div(pressable_attrs(config.classes, config.label, config.is_nav, msg), children)
}

# The same, inline — a badge's ✕, or any small control that has to sit inside a line of text.
pressable_span = |config, msg, children| {
	Html.span(pressable_attrs(config.classes, config.label, config.is_nav, msg), children)
}

default_link = { classes: "", href: "", label: "" }

# A link the app owns: a real `<a href>`. Tab reaches it, Enter follows it, the status bar says
# where it goes, and Ctrl-click or a middle click opens it in a second tab — all of it the
# browser's own link behaviour, which a `div` with a click handler cannot have. What the app adds
# is the click: `prevent_default` keeps the browser from loading that address as a page, because
# the app owns the URL and pushes it itself (the href and the pushed URL are the same address —
# State's `route_path` is where both read it from).
#
# `msg` is the message itself (`NavigateTo(Dashboard)`), not the `Click(...)` wrapper the button
# config carries: a link always goes somewhere, so there is no "no handler" case to express.
link = |config, msg, children| {
	attr_list = [
		class(Str.join_with([focus_ring, "cursor-pointer", config.classes], " ")),
		href(config.href),
		prevent_default(on_click(msg)),
	]
	Html.a(
		if Str.is_empty(config.label) { attr_list } else { List.append(attr_list, aria("label", config.label)) },
		children,
	)
}

# A real `<form>`. The browser submits it when Enter is pressed in any field inside — which is the
# whole point of it: every one of the app's forms is a form, so a keyboard can fill and send one
# without a pointer. `on_submit` already suppresses the browser's own default (a page load, which
# would throw the model away), and a submit button does the same from the other direction (see
# `is_submit` on `button`). Give the form's submit button no `on_click` of its own: a click on it
# fires the click *and* the submit, and the message would land twice.
form = |classes, msg, children| {
	Html.form([class(classes), on_submit(msg)], children)
}

default_tick = { classes: "", label: "", is_disabled: Bool.False }

# One tick — a checkbox this app draws itself. A `<button>` rather than an `<input
# type=checkbox>`, so the click stays a Joy message like every other control in the app; `role`
# and `aria-checked` are what carry the on/off state to a screen reader (the glyph says nothing to
# one), and a button answers Enter and Space on its own. The glyph's size is the caller's
# (`classes`), because a tick in a table row and a tick in a permission list are not the same size.
tick = |config, ticked, msg| {
	classes = Str.join_with([
		focus_ring,
		"inline-flex items-center justify-center rounded-md hover:bg-accent hover:text-accent-foreground h-9 px-3 leading-none disabled:opacity-50 disabled:pointer-events-none",
		config.classes,
	], " ")
	base = [
		class(classes),
		type("button"),
		role("checkbox"),
		aria("checked", if ticked { "true" } else { "false" }),
		on_click(msg),
	]
	attrs = if Str.is_empty(config.label) { base } else { List.append(base, aria("label", config.label)) }
	Html.button(
		if config.is_disabled { List.append(attrs, disabled(Bool.True)) } else { attrs },
		[Html.text(if ticked { "☑" } else { "☐" })],
	)
}


# --- LABEL ---

default_label = { classes: "" }

label = |config, children| {
	final_classes = Str.join_with(["text-sm font-medium leading-none peer-disabled:cursor-not-allowed peer-disabled:opacity-70", config.classes], " ")
	Html.label([class(final_classes)], children)
}

# --- AVATAR ---

default_avatar = { classes: "" }

avatar = |config, initials| {
	final_classes = Str.join_with(["relative flex h-10 w-10 shrink-0 overflow-hidden rounded-full bg-muted flex items-center justify-center text-sm font-medium", config.classes], " ")
	div([class(final_classes)], [text(initials)])
}

# --- SEPARATOR ---

default_separator = { classes: "" }

separator = |config| {
	final_classes = Str.join_with(["shrink-0 bg-border h-[1px] w-full", config.classes], " ")
	div([class(final_classes)], [])
}

# --- SIDEBAR ---

default_sidebar = { classes: "" }

sidebar = |config, children| {
	final_classes = Str.join_with(["flex flex-col border-r border-border bg-sidebar bg-card", config.classes], " ")
	aside([class(final_classes)], children)
}

default_sidebar_header = { classes: "" }

sidebar_header = |config, children| {
	final_classes = Str.join_with(["flex h-14 items-center px-4 border-b border-border", config.classes], " ")
	div([class(final_classes)], children)
}

default_sidebar_nav = { classes: "" }

sidebar_nav = |config, children| {
	final_classes = Str.join_with(["space-y-1 px-2", config.classes], " ")
	nav([class(final_classes)], children)
}

default_sidebar_nav_item = { classes: "", href: "#", is_active: Bool.False, on_click: None }

# One navigation item. It is a real link — the app's pages have addresses, so the sidebar says
# them: Tab reaches every item, Enter follows the focused one, the status bar shows where it goes,
# and Ctrl-click opens a second tab on it. The click is still the app's (`prevent_default` stops
# the browser from loading the page itself, which would throw the model away), and `href` is the
# address the navigation pushes: State's `route_path` is the one place both read it from.
sidebar_nav_item = |config, children| {
	base_classes = "group flex w-full items-center gap-2 px-3 py-2 text-sm font-medium rounded-md transition-colors cursor-pointer"
	
	active_classes =
		if config.is_active {
			"bg-secondary/20 text-foreground"
		} else {
			"text-muted-foreground hover:bg-secondary/10 hover:text-foreground"
		}
		
	final_classes = Str.join_with([base_classes, active_classes, focus_ring, config.classes], " ")
	
	# data-nav marks a control that changes the view without a full page load: the page's own
	# JavaScript starts the top border progress bar on a click that lands on one (and on a
	# push_state, for the navigation the click leads to).
	attrs = [class(final_classes), data("nav", ""), href(config.href)]
	final_attrs = match config.on_click {
		None => attrs
		Click(msg) => List.append(attrs, prevent_default(on_click(msg)))
	}
	
	Html.a(final_attrs, children)
}

# --- TABLE ---

default_table = { classes: "" }

table = |config, children| {
	final_classes = Str.join_with(["w-full caption-bottom text-sm", config.classes], " ")
	wrapper_classes = "relative w-full overflow-auto"
	div([class(wrapper_classes)], [
		Html.table([class(final_classes)], children)
	])
}

default_table_header = { classes: "" }

table_header = |config, children| {
	final_classes = Str.join_with(["[&_tr]:border-b", config.classes], " ")
	Html.thead([class(final_classes)], children)
}

default_table_body = { classes: "" }

table_body = |config, children| {
	final_classes = Str.join_with(["[&_tr:last-child]:border-0", config.classes], " ")
	Html.tbody([class(final_classes)], children)
}

default_table_row = { classes: "" }

table_row = |config, children| {
	final_classes = Str.join_with(["border-b transition-colors hover:bg-muted/50 data-[state=selected]:bg-muted", config.classes], " ")
	Html.tr([class(final_classes)], children)
}

default_table_head = { classes: "" }

table_head = |config, children| {
	final_classes = Str.join_with(["h-12 px-4 text-left align-middle font-medium text-muted-foreground [&:has([role=checkbox])]:pr-0", config.classes], " ")
	Html.th([class(final_classes)], children)
}

# The classes every cell shares, labelled or not.
table_cell_classes = "p-4 align-middle [&:has([role=checkbox])]:pr-0"

default_table_cell = { classes: "" }

table_cell = |config, children| {
	final_classes = Str.join_with([table_cell_classes, config.classes], " ")
	Html.td([class(final_classes)], children)
}

# The class a table carries to lay its rows out as stacked cards on a phone: below `sm` the header row
# is dropped and each cell prints the name of the column it sits in beside its value (see the
# `stack-rows` rules in www/app.css). It goes on the tables whose columns are too many to read panned
# sideways inside a phone-width card — the configuration hub's and user management's.
table_stack_classes = "stack-rows"

default_table_stack_cell = { classes: "", label: "" }

# A cell of a table marked `table_stack_classes`: the same cell as `table_cell`, plus the name of its
# column, which the phone layout prints beside the value. A `label` of "" says the cell needs no
# name — a row's tick, its avatar, its buttons — and those cells are the ones a view marks
# `stack-inline` to keep them together on the row's first line. At `sm` and up both are inert: the
# table is a table again and the name is never rendered.
table_stack_cell = |config, children| {
	final_classes = Str.join_with([table_cell_classes, config.classes], " ")
	attrs =
		if Str.is_empty(config.label) {
			[class(final_classes)]
		} else {
			[class(final_classes), attribute("data-label", config.label)]
		}

	Html.td(attrs, children)
}

# --- LIST STATES ---
# Every list fed by the page's fetch_data port has three states, and the views render all three:
# not loaded yet (skeleton), loaded (the rows, or a real empty state), and failed (what failed,
# the backend's own message, and a retry). A failure never leaves a skeleton or a spinner behind.

# One grey bar of a skeleton, sized by the caller's width class. `data-skeleton` marks the
# placeholder so the browser checks can tell "not loaded yet" apart from a loaded list.
skeleton_bar = |classes| {
	div([class("rounded bg-muted animate-pulse ${classes}"), data("skeleton", "")], [])
}

# Card-shaped skeleton rows, for the lists the page's JavaScript renders into a panel (assessments,
# submissions) and for the ones the views draw as cards rather than table rows.
list_skeleton_cards = |row_widths| {
	div([class("space-y-3")], List.map([1, 2, 3], |_row| {
		div([class("rounded-lg border p-4 flex items-center gap-4")], List.map(row_widths, |width| skeleton_bar("h-4 ${width}")))
	}))
}

# Skeleton rows shaped like the table's own columns: a few rows of grey bars, one per column.
table_skeleton_rows = |column_widths| {
	List.map([1, 2, 3, 4], |_row| table_row({ classes: "" }, List.map(column_widths, |width| {
		table_cell({ classes: "" }, [skeleton_bar("h-4 ${width}")])
	})))
}

# The single cell that carries a table's empty or failed state across its columns.
table_state_row = |column_count, content| {
	table_row({ classes: "" }, [
		Html.td([class("px-4 py-12 text-center"), attribute("colspan", U64.to_str(column_count))], [content])
	])
}

# A real empty state: the list loaded and holds no rows. `data-empty-state` marks it, like the
# page's own JavaScript-rendered empty states, so the two are the same thing to a browser check.
table_empty_state = |column_count, icon_name, title, description| {
	table_state_row(column_count, div([class("flex flex-col items-center gap-2"), data("empty-state", "")], [
		div([class("flex h-10 w-10 items-center justify-center rounded-full bg-muted text-muted-foreground")], [icon(icon_name, "h-5 w-5")]),
		p([class("text-sm font-medium text-foreground")], [text(title)]),
		p([class("text-xs text-muted-foreground")], [text(description)])
	]))
}

# A failed list: the backend's own message is what the user reads. `data-error-state` marks it.
table_error_state = |column_count, title, message, retry_msg| {
	table_state_row(column_count, div([class("flex flex-col items-center gap-2"), data("error-state", "")], [
		p([class("text-sm font-medium text-destructive")], [text(title)]),
		p([class("text-xs text-muted-foreground")], [text(message)]),
		button({ ..default_button, variant: Outline, size: Sm, on_click: retry_msg }, [text("Retry")])
	]))
}

# The same empty and failed states for the lists that are card grids rather than tables.
list_empty_state = |icon_name, title, description| {
	div([class("rounded-lg border bg-card p-10 flex flex-col items-center gap-2 text-center"), data("empty-state", "")], [
		div([class("flex h-10 w-10 items-center justify-center rounded-full bg-muted text-muted-foreground")], [icon(icon_name, "h-5 w-5")]),
		p([class("text-sm font-medium text-foreground")], [text(title)]),
		p([class("text-xs text-muted-foreground")], [text(description)])
	])
}

list_error_state = |title, message, retry_msg| {
	div([class("rounded-lg border bg-card p-10 flex flex-col items-center gap-2 text-center"), data("error-state", "")], [
		p([class("text-sm font-medium text-destructive")], [text(title)]),
		p([class("text-xs text-muted-foreground")], [text(message)]),
		button({ ..default_button, variant: Outline, size: Sm, on_click: retry_msg }, [text("Retry")])
	])
}


}