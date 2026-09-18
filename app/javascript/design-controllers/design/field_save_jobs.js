// The save requests for one committed field (pure; node-tested), used by
// design--style-autosave for the style panel and the Page section.
// • A value → PATCH field=value.
// • Empty → DELETE (revert) — unless the field is required (never reverted:
//   the Page section's column count and gutter): then PATCH "" so the server
//   answers 422 "필수".
// • The Page section's 🔗 link on, for Left or Right: a value sets both in ONE
//   request (values[left_margin_mm], values[right_margin_mm]), validated and
//   written together; emptying either reverts both.

export const LINKED_FIELDS = [ "left_margin_mm", "right_margin_mm" ]
export const LINKED_KEY = ":linked_margins"

export function partnerOf(field) {
  const i = LINKED_FIELDS.indexOf(field)
  return i < 0 ? null : LINKED_FIELDS[1 - i]
}

export function saveJobs({ field, value, url, linked = false, required = [] }) {
  const pair = linked && LINKED_FIELDS.includes(field)
  if (value === "" && !required.includes(field)) {
    return (pair ? LINKED_FIELDS : [ field ]).map((f) => ({ key: f, method: "DELETE", url, field: f }))
  }
  if (pair) {
    return [ { key: LINKED_KEY, method: "PATCH", url, fields: [ ...LINKED_FIELDS ],
               values: Object.fromEntries(LINKED_FIELDS.map((f) => [ f, value ])) } ]
  }
  return [ { key: field, method: "PATCH", url, field, value } ]
}
