# Studio Shell + Host-Extension Contract — Design Spec

**Date:** 2026-06-24
**Status:** Approved (brainstorm) — pending spec review
**Repo:** `design` gem (primary). `book_design` registers actions (initializer). `book_write` unaffected (registers nothing).
**Program context:** This is **Sub-project 0** of "converge the design studio onto book_design's UI" — the foundation. Later sub-projects (#1 themes, #2 paper-sizes, #3 document-designs, #4 paragraph-styles/style-browser, #5 table-styles, #6 retire book_design `Pages::*`) port the rich page content into the shell this spec builds.

---

## Goal

Give the gem's design studio (mounted at `/design`, used by both book_design and book_write) the persistent **shell** book_design's UI has — a top bar (home link + title/breadcrumb + host-action area) and an optional contextual left sidebar — plus a **host-extension contract** so each host injects its own host-only tools (Generate, Import, Export, Generate-PDFs, Style-browser) as buttons the gem renders, without the gem depending on host services. Adopt book_design's styling so ported components render identically.

## Problem

There are two parallel UIs editing the same `Design::*` data: the lean gem studio (`/design`, breadcrumb-only, ~5 pages, slate/compact) and book_design's rich host UI (`/themes`, contextual sidebars + top action bars + colored doc-types, full CRUD + authoring tools). We're converging onto **one UI in the gem**. The blocker is that book_design's rich pages are wired to **host-only services** (`ThemeGeneratorService`, `BookDesignAutoExport`, import/export, `StylePdfBatchService`) that cannot move into the gem (book_write lacks them). So before any page can be ported, the gem needs a shell with **extension points** that hosts fill in (or omit).

## Key findings (from exploration)

- **Gem layout** `app/views/layouts/design.html.erb`: minimal `<body class="design-studio"><main>flash + yield</main></body>`, links the scoped `design` stylesheet. No nav chrome.
- **Gem base component** `app/components/design/views/base.rb`: includes `Phlex::HTML`, Routes/ButtonTo/TurboFrameTag, `RubyUI`. Area views wrap content in a centered `.design-studio mx-auto max-w-6xl …` div. Navigation is `Design::Views::Breadcrumb` only.
- **`Design::Configuration`** (`lib/design.rb`) already exposes host hooks (`current_user`, `authorize`, `authenticate`, `user_class`, `authoring`, `locale_for`, `home_url`, `themes_dir`) — the established pattern this spec extends with an `actions` registry.
- **book_design** uses per-page contextual sidebars (e.g. `Pages::PaperSizes::Show` renders a sidebar of that size's doc-types), top action bars, and `Shared::EditorToolbar` (a breadcrumb + doc-type quick-switch dropdown). Both apps use **RubyUI**, but **neither defines the RubyUI token palette** — verified: `--primary`/`--background`/`text-muted-foreground` produce 0 rules in both builds, so RubyUI buttons (`bg-primary`) and `text-muted-foreground` (used 52× in book_design) currently no-op; book_design's look comes from explicit utilities (slate/gray/blue) + layout classes that DO compile. The gem's scoped Tailwind build (`design.css`, `source(none)` + `@source` over component files) compiles whatever **explicit** classes the ported components use, but **not** the missing tokens.
- **Host-only tools in book_design** surfaced as buttons/links: New theme, Import, Generate, Style browser (themes index); Export DB, Generate PDFs, Clone (theme show); Regenerate (paper size). Their actual flows are host controllers/pages.

## Decisions

| # | Decision |
|---|----------|
| 1 | **Host-extension = declarative action registry.** Hosts register button **descriptors** per named slot via `Design.config.actions.for(slot){…}`; the gem renders them. book_write registers nothing → no buttons. |
| 2 | **Shell = contextual sidebar (book_design model).** Top bar (home link + title/breadcrumb + host-action slot) + optional per-area sidebar slot + full-screen main. No global fixed nav. |
| 3 | **Match book_design's exact current look — do NOT author tokens.** Reuse book_design's exact classes; the explicit utilities (slate/blue/layout) compile automatically via the gem's scoped `@source`, and the dead token classes (`bg-primary`, `text-muted-foreground`) stay no-op in the gem just as they do in book_design → pixel-identical. The goal is **consistency** (one UI, one look), not a nicer studio. (Authoring the token palette is deferred as a future *single-place* improvement — done once in the gem, it would properly style both apps.) No host CSS bleed; book_write isolated. |
| 4 | **#0 re-houses the existing gem pages** in the shell as the verifiable deliverable; rich content ports are #1–#5. |
| 5 | **Top bar is minimal:** home link + title/breadcrumb + action slot. No locale indicator / theme switcher in #0. |
| 6 | **Doc-type switcher deferred to #3** (it's document-design-editor-specific). |

## Design

### Action registry (the contract)

`Design::Configuration#actions` returns a `Design::ActionRegistry` that only **stores raw blocks** — it does NOT call them (a `Proc` is bound to its definition site, the initializer, where `main_app`/route helpers don't exist; calling it there raises `NameError`). The block must be **re-bound to the view context** at render time. This mirrors the gem's existing host-hook pattern — `home_url` is invoked as `helpers.instance_exec(&Design.config.home_url)` (`app/components/design/views/themes/index.rb:25`; same `instance_exec` pattern in `app/controllers/design/application_controller.rb:22,46`).

```ruby
module Design
  class ActionRegistry
    def for(slot, &block) = registrations[slot.to_sym] = block   # host registers a block
    def resolve(slot)     = registrations[slot.to_sym]           # gem fetches the RAW block (or nil)
    private def registrations = @registrations ||= {}
  end
end
```
- **Descriptor schema** (a Hash): `label:` (required), `path:` (required), `method:` (`:get`/`:post`/`:delete`, default `:get`), `icon:` (optional symbol), `confirm:` (optional string), `variant:` (optional RubyUI button variant).
- **Gem render helper** `render_host_actions(slot, context = nil)` (in `Design::Views::Base`):
  ```ruby
  def render_host_actions(slot, context = nil)
    block = Design.config.actions.resolve(slot) or return
    Array(helpers.instance_exec(context, &block)).each { |d| render_action_descriptor(d) }
  end
  ```
  `helpers.instance_exec` re-binds the block against the Phlex view's `ActionView` context, where **`main_app.*` resolves host routes** (the engine is `isolate_namespace Design`, so bare `helpers.export_theme_db_path` would hit the *engine's* routes — host routes are reachable only via `helpers.main_app.*`). `render_action_descriptor` emits `button_to`/`a` per `method`, maps `confirm:` → `data: { turbo_confirm: ... }` (the gem's Turbo convention, cf. the delete button in `themes/index.rb`), and `icon:`/`variant:` onto `RubyUI::Button`.
- **book_design** registers in `config/initializers/design.rb` — descriptors use `main_app.*`:
  ```ruby
  Design.config.actions.for(:theme_show) do |theme|
    [ { label: "Export",        path: main_app.export_theme_db_path(theme),     method: :post, icon: :download },
      { label: "Generate PDFs", path: main_app.generate_style_pdfs_path(theme), method: :post } ]
  end
  ```
- **book_write** registers nothing → `resolve` returns `nil` → `render_host_actions` no-ops → no host buttons. Graceful by construction; no gem code path assumes a host action exists.

### Shell component

New `Design::Views::Shell` (Phlex), used by area views instead of the bare centered div:
```
Design::Views::Shell.new(title:, breadcrumb: nil, action_slot: nil, action_context: nil, sidebar: nil) { main_content }
```
renders:
```
.design-studio (full-screen flex-col)
  ├─ top bar: [home link → Design.config.home_url or themes] · title/breadcrumb · render_host_actions(action_slot, action_context)
  └─ body (flex): [sidebar component if given] + [main: yield]
```
- **Sidebar contract:** `sidebar:` accepts a **Phlex component instance** (or `nil` → full-width main). When present, `Shell` renders it via `render sidebar` in a fixed-width left column (`w-64`, vertical-scroll) with main flexing to fill; when `nil`, main spans full width. #0 ships the shell with **no sidebar** (all re-housed pages pass `nil`); #1–#5 supply area sidebars conforming to this contract.
- **Flash stays in the layout.** `design.html.erb` keeps its existing `data-flash` divs in `<main>` (above the Shell); `Shell` does **not** render flash. (Placement above the top bar is acceptable for #0; a later sub-project may move it in.)
- **No JavaScript in #0.** The shell is fully static server-render (home link `a`, host actions via `button_to`/`a`); no Stimulus controller. (The interactive doc-type dropdown — `Shared::EditorToolbar` — is deferred to #3.)
- `Design::Views::Base` gains `render_host_actions` + a `shell(**opts, &block)` convenience. `design.html.erb` stays the outer HTML (csrf/asset tags + flash); `Shell` is the in-`<main>` chrome.
- **Slot-naming convention:** `<area>_<context>` — `themes_index`, `theme_show`, `paper_size_show`, `document_design_editor`, etc. #0 defines the convention + mechanism and wires the slots the **re-housed existing pages** use (`themes_index`, `theme_show`); later sub-projects add theirs.

### Styling foundation

**There is no existing token palette to copy** — verified: neither the gem's `design.css` nor book_design's `tailwind.css` defines the RubyUI tokens (`--primary`/`--background`/… → 0 rules in both builds). book_design's components use `text-muted-foreground` 52× and RubyUI buttons emit `bg-primary`, but those classes produce **no CSS rules today** — they silently no-op; book_design "looks fine" only because it leans on explicit utilities (slate/gray/blue) + layout classes that DO compile. (The token palette could be authored from the RubyUI install template — but doing so is explicitly **out of scope** for #0, since it would make the studio diverge from book_design's current look.)

**To match book_design exactly, #0 does NOT author tokens.** The gem must reproduce *both* of book_design's behaviors — which its scoped build already does automatically:
- **Explicit utilities** (slate/blue/layout): build the shell chrome with the same explicit classes book_design's top bars/sidebars use; the gem's `@source "../../components/**"` build compiles them → identical chrome.
- **Dead tokens**: the gem also lacks the palette, so `bg-primary`/`text-muted-foreground` no-op in the gem exactly as in book_design → identical (non-)styling.

So the styling work is small: build the shell chrome with book_design's explicit classes, rebuild `app/assets/builds/design.css` via the `design:tailwind:build` flow, keep `DesignTailwindBuildFreshnessTest` green. **No `:root`/`@theme` token block** (that would make the studio look *better than* book_design — a divergence we don't want). If proper token styling is ever wanted, it's a future single-place change in the gem that upgrades both apps at once. **Small** task.

### Scope / proof of #0

Re-house the existing gem pages in `Shell` — minimal content change, just so the shell + styling are live. This is **per-view** (the centered `mx-auto max-w-*` wrapper lives in each view's `view_template`, not in `Base`): edit the **4 view files** `app/components/design/views/{themes/index,themes/show,paper_sizes/edit,document_designs/edit}.rb` to call `shell(...)` and drop their own wrapper. `themes/index.rb` already renders its own header + host home link (`:25`) — **remove/de-duplicate** it when the Shell top bar takes over. Verifiable: `/design/themes` renders the new top bar + proper styling; in book_design a registered `themes_index`/`theme_show` action button appears; in a no-registration context it's absent.

## Data flow

Host boot → `Design.config.actions.for(slot){…}` stores blocks. Request → gem controller renders an area view → view calls `shell(action_slot: :theme_show, action_context: @theme){ … }` → `Shell` top bar calls `render_host_actions(:theme_show, @theme)` → registry resolves the block in view context → descriptors → `RubyUI::Button`s linking to host routes. Clicking a button hits a **host** controller/page (e.g. `/themes/:id/export_theme_db`), unchanged.

## Testing

- **`ActionRegistry` unit test:** `for`/`resolve` stores and returns the raw block; unregistered slot → `nil`.
- **`render_host_actions` component test (incl. the render-time binding):** renders a registered descriptor as a button with the right path/method; **a descriptor whose `path:` is computed from a host route via `main_app.*` resolves correctly** (proves the `instance_exec` binding, not boot-time `call`); renders nothing when unregistered; arity-0 and arity-1 blocks both work; maps `confirm:` → `data-turbo-confirm`; honors `method`/`icon`/`variant`.
- **`Shell` component test:** renders top bar (home link + title) + main (yielded content); renders the sidebar component (`render sidebar`) when given, omits the column when nil.
- **Integration:** a gem dummy-app studio page renders through `Shell` (top bar present); with a stubbed registered action → button in output; without → absent.
- **Styling:** `design.css` rebuilt; `DesignTailwindBuildFreshnessTest` stays green. (No token-authoring, so no token/scoper check needed in #0.)
- Minitest only.

## Risks

- **Route-helper context (was a spec bug, now fixed)** — a registered block is bound to its initializer definition site, so `block.call` raises `NameError` on `main_app`. Mitigation: the registry stores the **raw block**; `render_host_actions` re-binds it via `helpers.instance_exec(context, &block)` in the Phlex view (the proven `home_url` pattern), and descriptors use `main_app.*` (host routes; the engine is `isolate_namespace`d). A unit test renders a descriptor whose path is a host route.
- **Look-match fidelity** — matching book_design exactly relies on the shell chrome reusing book_design's *exact* explicit utility classes (the gem's `@source` compiles them) and on the dead token classes no-opping identically in both apps. Mitigation: build the shell from book_design's chrome classes verbatim; the #0 proof page (compare `/design` vs `/themes` chrome) surfaces any drift. No token block is authored (out of scope), so there's no scoper/`:root` concern in #0.
- **Scoped-build coverage** — the gem's `@source` globs must cover the shell/new components so their classes compile. Mitigation: shell lives under the already-globbed `app/components/**`.
- **book_write regression** — additive only (new config method, new components); book_write registers nothing and its `/design` pages gain the shell. Low risk; covered by rendering a studio page with no registrations.

## Out of scope (later sub-projects)

Rich page-content ports (themes/sizes/docs CRUD, populated sidebars, the editor toolbar + doc-type switcher), retiring book_design's `Pages::*`, table styles, style browser, the host-only flows themselves (they stay host pages the action buttons link to).
