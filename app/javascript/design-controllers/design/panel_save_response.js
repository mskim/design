// What the style panel does with a Save response (pure; node-tested).
// render: "stream" — a turbo-stream body (the preview + panel after a save, or
// a stale Save's 409 carrying the live panel); "frame" — a plain panel page
// (a 422 with validation errors); null — nothing to swap in.
// status: "Saved" only for an ok response; any other status is "Error", even
// when a panel comes back with it.
export function saveResponseOutcome({ ok, contentType, body }) {
  const text = body || ""
  let render = null
  if ((contentType || "").includes("turbo-stream") || text.includes("<turbo-stream")) render = "stream"
  else if (/<turbo-frame[^>]*\bid="properties_panel"/.test(text)) render = "frame"
  return { render, status: ok ? "Saved" : "Error" }
}
