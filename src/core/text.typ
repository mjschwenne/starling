// Text helpers — the string rules shared by captions and alt text.
//
// These are not drawing code: they decide how an element is *named* in prose
// so that a caption, an alt string, and the drawn label all agree.

/// The string used to refer to an element in captions and alt text.
///
/// An element visually displays its `label` whenever that is a plain string
/// (the backends fall back to the ordering value only for `auto`), so text
/// referring to it should read the same way. `auto` and arbitrary content
/// can't be spliced into a string, so those fall back to the ordering value.
///
/// `value-key` names the field holding that ordering value — `"value"` for
/// the trees, `"key"` for the sort and skip-list element dicts.
#let display-value(elem, value-key: "value") = if type(elem.label) == str {
  elem.label
} else {
  str(elem.at(value-key))
}

/// The binary-tree case of `display-value`: a node carrying a `value` /
/// `label` pair (BST, RBT, AVL).
#let alt-label(node) = display-value(node)

/// The n-ary case: a node carries parallel `keys` / `labels` arrays, so a
/// reference names one compartment `i` (B24).
#let alt-key-label(node, i) = {
  let l = node.labels.at(i, default: auto)
  if type(l) == str { l } else { str(node.keys.at(i)) }
}

/// Alt text for a static `display()` frame:
/// `"<Structure>: <describe>."`
#let alt-describe(ds-name, describe-text) = ds-name + ": " + describe-text + "."

/// Alt text for the first frame of an operation:
/// `"<Structure>: <describe>. About to <action>."`
///
/// Every display's opening frame goes through this, so a screen-reader user
/// gets the whole structure once as a baseline and only the per-step change
/// thereafter.
#let alt-intro(ds-name, describe-text, action) = {
  alt-describe(ds-name, describe-text) + " About to " + action + "."
}
