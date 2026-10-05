module [default_sidebar_nav_item, default_button, card, card_header, card_title, card_content, badge, button, table, table_header, table_body, table_row, table_head, table_cell, skeleton_bar, list_skeleton_cards, table_skeleton_rows, table_empty_state, table_error_state, list_empty_state, list_error_state, sidebar, sidebar_header, sidebar_nav, sidebar_nav_item, input, label]

import html.Html exposing [Html, div, h3, p, aside, nav, a, input, label, text]
import html.Attribute exposing [class, type, disabled, on_click, href, value, placeholder, on_input, attribute, data]

# --- BUTTON ---

default_button = {
	variant: Primary,
	size: Default,
	on_click: None,
	is_disabled: Bool.False,
	classes: "",
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
	
	attrs = [class(final_classes), type("button")]
	
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

sidebar_nav_item = |config, children| {
	base_classes = "group flex w-full items-center gap-2 px-3 py-2 text-sm font-medium rounded-md transition-colors cursor-pointer"
	
	active_classes =
		if config.is_active {
			"bg-secondary/20 text-foreground"
		} else {
			"text-muted-foreground hover:bg-secondary/10 hover:text-foreground"
		}
		
	final_classes = Str.join_with([base_classes, active_classes, config.classes], " ")
	
	# data-nav marks a control that changes the view without a full page load: the page's own
	# JavaScript starts the top border progress bar on a click that lands on one (and on a
	# push_state, for the navigation the click leads to).
	attrs = [class(final_classes), data("nav", "")]
	final_attrs = match config.on_click {
		None => attrs
		Click(msg) => List.append(attrs, on_click(msg))
	}
	
	div(final_attrs, children)
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

default_table_cell = { classes: "" }

table_cell = |config, children| {
	final_classes = Str.join_with(["p-4 align-middle [&:has([role=checkbox])]:pr-0", config.classes], " ")
	Html.td([class(final_classes)], children)
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
table_empty_state = |column_count, icon, title, description| {
	table_state_row(column_count, div([class("flex flex-col items-center gap-2"), data("empty-state", "")], [
		div([class("flex h-10 w-10 items-center justify-center rounded-full bg-muted text-lg")], [text(icon)]),
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
list_empty_state = |icon, title, description| {
	div([class("rounded-lg border bg-card p-10 flex flex-col items-center gap-2 text-center"), data("empty-state", "")], [
		div([class("flex h-10 w-10 items-center justify-center rounded-full bg-muted text-lg")], [text(icon)]),
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

