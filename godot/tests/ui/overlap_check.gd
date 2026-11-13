extends RefCounted
## Layout probes shared by the overlap regression test (ui_overlap_test.gd) and the audit / screenshot tool (ui_overlap_audit.gd).
##
## They answer the questions a person answers by looking at a screen:
##   * does anything visible overlap something else that is visible (button over label, label over label, toast over a button)?
##   * does anything stick out of the window (except inside a scroll area)?
##   * is text clipped (the control is smaller than the text needs)?
##   * is a touch / pointer target smaller than the design system allows?
## Only "content" controls count (buttons, inputs, sliders, bars and labels with text): panels, backdrops and spacers overlap
## on purpose. A control inside a ScrollContainer (or any clipping parent) only counts where it is actually visible.
const MIN_OVERLAP := 3.0   # px of intersection, per axis, before two controls count as overlapping

## Controls that carry something a person reads or presses.
static func is_content(c: Control) -> bool:
	if c is BaseButton or c is LineEdit or c is TextEdit or c is Slider or c is SpinBox or c is ProgressBar:
		return true
	if c is Label:
		return (c as Label).text != ""
	if c is RichTextLabel:
		return (c as RichTextLabel).get_parsed_text() != ""
	return false

static func is_interactive(c: Control) -> bool:
	return c is BaseButton or c is LineEdit or c is TextEdit or c is Slider or c is SpinBox

## The part of the control's rect that carries something. A label that does not wrap draws its text at one end (or the middle) of a
## rect that may be as wide as the whole row; only the text counts, otherwise a one-word title would "overlap" a card standing in
## the empty part of its row.
static func ink_rect(c: Control) -> Rect2:
	var rect := c.get_global_rect()
	if c is Label and (c as Label).autowrap_mode == TextServer.AUTOWRAP_OFF:
		var label := c as Label
		var wide := minf(rect.size.x, label.get_minimum_size().x)
		match label.horizontal_alignment:
			HORIZONTAL_ALIGNMENT_CENTER:
				rect.position.x += (rect.size.x - wide) * 0.5
			HORIZONTAL_ALIGNMENT_RIGHT:
				rect.position.x += rect.size.x - wide
		rect.size.x = wide
	return rect

## Where the control really shows: its ink rect clipped by every scrolling / clipping ancestor. Empty when nothing shows.
static func shown_rect(c: Control) -> Rect2:
	var rect := ink_rect(c)
	var parent := c.get_parent()
	while parent != null:
		if parent is Viewport:
			break   # the top of the control's own viewport (a window or a SubViewport): anything above it is in other coordinates
		if parent is Control:
			var clip := parent as Control
			if clip is ScrollContainer or clip.clip_contents:
				rect = rect.intersection(clip.get_global_rect())
				if rect.size.x <= 0.0 or rect.size.y <= 0.0:
					return Rect2()
		parent = parent.get_parent()
	return rect

static func in_scroll(c: Control, host: Node) -> bool:
	var parent := c.get_parent()
	while parent != null and parent != host:
		if parent is Viewport:
			break   # a SubViewport (the combat HUD) has a canvas of its own: the page's scroll area says nothing about it
		if parent is ScrollContainer:
			return true
		parent = parent.get_parent()
	return false

## True for controls that are meant to float over everything (toast stack).
static func is_floating(c: Control) -> bool:
	var node: Node = c
	while node != null:
		if node.name in ["ToastLayer", "Anchor", "Stack"]:
			return true
		node = node.get_parent()
	return false

static func content_controls(host: Node, include_floating: bool = false) -> Array:
	var found: Array = []
	for node in host.find_children("*", "Control", true, false):
		var c := node as Control
		if not c.is_visible_in_tree() or not is_content(c):
			continue
		if not include_floating and is_floating(c):
			continue
		var rect := shown_rect(c)
		if rect.size.x <= 0.5 or rect.size.y <= 0.5:
			continue
		found.append([c, rect])
	return found

## Pairs of visible content controls whose visible rects intersect by more than MIN_OVERLAP in both axes.
## Each entry: {"a": Control, "b": Control, "rect": Rect2 (the intersection)}.
static func overlaps(host: Node, include_floating: bool = false) -> Array:
	var items := content_controls(host, include_floating)
	var found: Array = []
	for i in items.size():
		var a: Control = items[i][0]
		for j in range(i + 1, items.size()):
			var b: Control = items[j][0]
			if a.is_ancestor_of(b) or b.is_ancestor_of(a) or a.get_viewport() != b.get_viewport():
				continue   # (rects are in the coordinates of the control's own viewport: a dialog window, the board's SubViewport...)
			var inter: Rect2 = (items[i][1] as Rect2).intersection(items[j][1])
			if inter.size.x > MIN_OVERLAP and inter.size.y > MIN_OVERLAP:
				found.append({"a": a, "b": b, "rect": inter})
	return found

## Content that sticks out of its window (outside a scroll area), has no size, or is smaller than its text needs.
## Returns entries {"kind": String, "control": Control, "detail": String}.
static func problems(host: Node) -> Array:
	var found: Array = []
	for node in host.find_children("*", "Control", true, false):
		var c := node as Control
		if not c.is_visible_in_tree() or is_floating(c):
			continue
		var view := c.get_viewport()
		var area := Rect2(Vector2.ZERO, view.get_visible_rect().size) if view != null else Rect2()
		var rect := c.get_global_rect()
		var scrolled := in_scroll(c, host)
		if not is_content(c):
			continue
		if rect.position.x < area.position.x - 1.5 or rect.end.x > area.end.x + 1.5:
			found.append({"kind": "overflow-x", "control": c, "detail": "%s in viewport %s" % [str(rect), str(area.size)]})
		elif not scrolled and (rect.position.y < area.position.y - 1.5 or rect.end.y > area.end.y + 1.5):
			found.append({"kind": "overflow-y", "control": c, "detail": "%s in viewport %s" % [str(rect), str(area.size)]})
		if c.size.x <= 0.0 or c.size.y <= 0.0:
			found.append({"kind": "zero-size", "control": c, "detail": ""})
		var texty := (c is Label and (c as Label).text != "") or (c is Button and (c as Button).text != "")
		if texty:
			var minimum := c.get_combined_minimum_size()
			var trimmed := c is Label and (c as Label).text_overrun_behavior != TextServer.OVERRUN_NO_TRIMMING
			if not trimmed and (c.size.x + 0.5 < minimum.x or c.size.y + 0.5 < minimum.y):
				found.append({"kind": "clipped-text", "control": c, "detail": "size %s min %s" % [str(c.size), str(minimum)]})
	return found

## Interactive controls smaller than `min_px` on either axis (the design system's pointer minimum).
static func small_targets(host: Node, min_px: float) -> Array:
	var found: Array = []
	for item in content_controls(host):
		var c: Control = item[0]
		if is_interactive(c) and not (c is Slider) and (c.size.x + 0.5 < min_px or c.size.y + 0.5 < min_px):
			if c is BaseButton and (c as BaseButton).disabled and c.size.y >= min_px - 8.0:
				continue
			found.append(c)
	return found

## Short human-readable name: the last three path segments plus the text, so a report line is easy to find.
static func describe(c: Control) -> String:
	var parts := str(c.get_path()).split("/")
	var tail := "/".join(parts.slice(maxi(0, parts.size() - 3)))
	var text := ""
	if c is Label:
		text = (c as Label).text
	elif c is Button:
		text = (c as Button).text
	elif c is RichTextLabel:
		text = (c as RichTextLabel).get_parsed_text()
	elif c is LineEdit:
		text = (c as LineEdit).placeholder_text
	text = text.replace("\n", " ")
	if text.length() > 28:
		text = text.substr(0, 28) + "…"
	return "%s%s [%dx%d]" % [tail, (" \"" + text + "\"") if text != "" else "", int(c.size.x), int(c.size.y)]
