import { test } from "node:test"
import assert from "node:assert/strict"
import { saveResponseOutcome } from "../../app/javascript/design-controllers/design/panel_save_response.js"

const stream = '<turbo-stream action="replace" target="properties_panel"><template>…</template></turbo-stream>'
const frame = '<turbo-frame id="properties_panel"><div class="design-studio">…</div></turbo-frame>'

test("an ok turbo-stream save renders the stream and reports Saved", () => {
  assert.deepEqual(saveResponseOutcome({ ok: true, contentType: "text/vnd.turbo-stream.html; charset=utf-8", body: stream }),
                   { render: "stream", status: "Saved" })
})

test("a stale Save's 409 still swaps in the live panel but reports Error", () => {
  assert.deepEqual(saveResponseOutcome({ ok: false, contentType: "text/vnd.turbo-stream.html; charset=utf-8", body: stream }),
                   { render: "stream", status: "Error" })
})

test("a 422 panel page is swapped in as a frame and reports Error", () => {
  assert.deepEqual(saveResponseOutcome({ ok: false, contentType: "text/html; charset=utf-8", body: frame }),
                   { render: "frame", status: "Error" })
})

test("an error with no panel renders nothing and reports Error", () => {
  assert.deepEqual(saveResponseOutcome({ ok: false, contentType: "text/html", body: "<h1>500</h1>" }),
                   { render: null, status: "Error" })
  assert.deepEqual(saveResponseOutcome({ ok: false, contentType: null, body: "" }),
                   { render: null, status: "Error" })
})
