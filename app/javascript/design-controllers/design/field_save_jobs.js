// The save requests for one committed field (pure; node-tested), used by
// design--style-autosave for the style panel and the Page section.
// • A value → PATCH field=value.
// • Empty → DELETE (revert) — unless the field is required (never reverted:
//   the Page section's column count and gutter): then PATCH "" so the server
//   answers 422 "필수".
// • The Page section's 🔗 link on, for Left or Right: a value sets both in ONE
//   request (values[left_margin_mm], values[right_margin_mm]), validated and
//   written together; emptying either reverts both.
// • The Object section's joint sets: a control Ruby marked data-joint-with is
//   written together with the fields it names (a cell size with its partner,
//   typed or dragged) in ONE request, so the set is validated as a whole.
//   Emptying one of them still reverts that field alone.

export const LINKED_FIELDS = [ "left_margin_mm", "right_margin_mm" ]
export const LINKED_KEY = ":linked_margins"

export function partnerOf(field) {
  const i = LINKED_FIELDS.indexOf(field)
  return i < 0 ? null : LINKED_FIELDS[1 - i]
}

// The input for `field`'s linked partner among `inputs` (anything with a
// `name`), matched by field name through `fieldOf` — never by building a
// selector from the name. null when there is no partner or it isn't there.
export function partnerInput(inputs, fieldOf, field) {
  const partner = partnerOf(field)
  if (!partner) return null
  return Array.from(inputs).find((input) => fieldOf(input.name) === partner) ?? null
}

// One request key per set, so two commits of the same set coalesce in the queue.
export const JOINT_KEY_PREFIX = ":joint:"

// The fields a control must be written with: itself plus the ones its
// data-joint-with names (a space-separated list Ruby renders). null when it
// names none.
export function jointFields(dataset, field) {
  const others = String(dataset?.jointWith ?? "").split(/\s+/).filter((f) => f && f !== field)
  return others.length ? [ field, ...others ] : null
}

// { field => trimmed value } for `fields`, read off `inputs` (anything with a
// `name`) by matching each name through `fieldOf` — never by building a
// selector from a field name. null when one of them isn't there, so a
// half-known set is never sent.
export function valuesFor(inputs, fieldOf, fields) {
  const found = new Map()
  for (const input of inputs) {
    const field = fieldOf(input.name)
    if (field && fields.includes(field) && !found.has(field)) found.set(field, (input.value ?? "").trim())
  }
  if (!fields.every((field) => found.has(field))) return null
  return Object.fromEntries(fields.map((field) => [ field, found.get(field) ]))
}

export function saveJobs({ field, value, url, linked = false, required = [], joint = null }) {
  const pair = linked && LINKED_FIELDS.includes(field)
  if (value === "" && !required.includes(field)) {
    return (pair ? LINKED_FIELDS : [ field ]).map((f) => ({ key: f, method: "DELETE", url, field: f }))
  }
  if (joint) {
    const fields = Object.keys(joint)
    return [ { key: JOINT_KEY_PREFIX + [ ...fields ].sort().join(","), method: "PATCH", url,
               fields: fields, values: { ...joint } } ]
  }
  if (pair) {
    return [ { key: LINKED_KEY, method: "PATCH", url, fields: [ ...LINKED_FIELDS ],
               values: Object.fromEntries(LINKED_FIELDS.map((f) => [ f, value ])) } ]
  }
  return [ { key: field, method: "PATCH", url, field, value } ]
}
