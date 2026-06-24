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
- **book_design** uses per-page contextual sidebars (e.g. `Pages::PaperSizes::Show` renders a sidebar of that size's doc-types), top action bars, and `Shared::EditorToolbar` (a breadcrumb + doc-type quick-switch dropdown). Both apps use **RubyUI**, so the design-token palette is largely shared; the gem's scoped Tailwind build (`app/assets/tailwind/design.css`, `source(none)` + `@source` over component files) compiles whatever classes the ported components use.
- **Host-only tools in book_design** surfaced as buttons/links: New theme, Import, Generate, Style browser (themes index); Export DB, Generate PDFs, Clone (theme show); Regenerate (paper size). Their actual flows are host controllers/pages.

## Decisions

| # | Decision |
|---|----------|
| 1 | **Host-extension = declarative action registry.** Hosts register button **descriptors** per named slot via `Design.config.actions.for(slot){…}`; the gem renders them. book_write registers nothing → no buttons. |
| 2 | **Shell = contextual sidebar (book_design model).** Top bar (home link + title/breadcrumb + host-action slot) + optional per-area sidebar slot + full-screen main. No global fixed nav. |
| 3 | **Adopt book_design's styling wholesale** (token palette + doc-type colors) into the gem's **scoped** `.design-studio` build — fidelity first. No host CSS bleed; book_write isolated. |
| 4 | **#0 re-houses the existing gem pages** in the shell as the verifiable deliverable; rich content ports are #1–#5. |
| 5 | **Top bar is minimal:** home link + title/breadcrumb + action slot. No locale indicator / theme switcher in #0. |
| 6 | **Doc-type switcher deferred to #3** (it's document-design-editor-specific). |

## Design

### Action registry (the contract)

`Design::Configuration#actions` returns a `Design::ActionRegistry`:
```ruby
module Design
  class ActionRegistry
    def for(slot, &block) = registrations[slot.to_sym] = block      # host registers
    def resolve(slot, context = nil) = registrations[slot.to_sym]   # gem renders
      &.then { |b| Array(b.arity.zero? ? b.call : b.call(context)) } || []
    private def registrations = @registrations ||= {}
  end
end
```
- **Descriptor schema** (a Hash): `label:` (required), `path:` (required), `method:` (`:get`/`:post`/`:delete`, default `:get`), `icon:` (optional symbol), `confirm:` (optional string), `variant:` (optional RubyUI button variant).
- **Gem render helper** `render_host_actions(slot, context = nil)` (in `Design::Views::Base`): calls `Design.config.actions.resolve(slot, context)` and renders each descriptor as a `RubyUI::Button`/link with the path + method (`button_to` for non-GET, `a` for GET), icon, and confirm. **The registered block is evaluated at render time inside the view context**, so host route helpers resolve via `main_app.*`.
- **book_design** registers in `config/initializers/design.rb`:
  ```ruby
  Design.config.actions.for(:theme_show) do |theme|
    [ { label: "Export", path: Rails.application.routes.url_helpers.export_theme_db_path(theme), method: :post, icon: :download },
      { label: "Generate PDFs", path: …generate_style_pdfs_path(theme), method: :post } ]
  end
  ```
  (Exact route-helper access — `main_app.*` in view vs `url_helpers` in block — is settled in the plan; the block runs in the gem view context where `main_app` is available, so the simplest form returns descriptors using `main_app.*`.)
- **book_write** registers nothing → every slot resolves to `[]` → no host buttons. Graceful by construction; no gem code path assumes a host action exists.

### Shell component

New `Design::Views::Shell` (Phlex), used by area views instead of the bare centered div:
```
Design::Views::Shell.new(title:, breadcrumb: nil, action_slot: nil, action_context: nil, sidebar: nil) { main_content }
```
renders:
```
.design-studio (full-screen flex-col)
  ├─ top bar: [home link → Design.config.home_url or themes] · title/breadcrumb · render_host_actions(action_slot, action_context)
  ├─ flash region
  └─ body (flex): [sidebar component if given] + [main: yield]
```
- `sidebar:` is an optional Phlex component an area supplies (nil → full-width main). #0 ships the shell + an empty/absent sidebar; areas populate it in #1–#5.
- `Design::Views::Base` gains `render_host_actions` + a `shell(**opts, &block)` convenience. The gem `design.html.erb` layout stays the outer HTML; `Shell` is the in-`<main>` chrome (so flash/csrf/asset tags remain in the layout).
- **Slot-naming convention:** `<area>_<context>` — `themes_index`, `theme_show`, `paper_size_show`, `document_design_editor`, etc. #0 defines the convention + mechanism and wires the slots the **re-housed existing pages** use (`themes_index`, `theme_show`); later sub-projects add theirs.

### Styling foundation

Adopt book_design's RubyUI/Tailwind **token palette** (the `--background`/`--foreground`/`--muted`/… CSS variables + doc-type color helpers) into the gem's scoped `design.css`, kept under `.design-studio`. Since both apps already use RubyUI, much of the palette is shared; the work is ensuring the gem's scoped build defines the same CSS variables and that doc-type color/icon helpers exist in the gem. Verify the exact token source in book_design (RubyUI install CSS vs a theme block) and mirror it into the gem build. Rebuild `app/assets/builds/design.css` (per the existing `design:tailwind:build` flow) and keep the freshness test green.

### Scope / proof of #0

Re-house the existing gem pages (`themes/index`, `themes/show`, `paper_sizes/edit`, `document_designs/edit`) in `Shell` — minimal content change, just so the shell + styling are live. Verifiable: `/design/themes` renders the new top bar + book_design-like styling; in book_design a registered `themes_index`/`theme_show` action button appears; in a no-registration context it's absent.

## Data flow

Host boot → `Design.config.actions.for(slot){…}` stores blocks. Request → gem controller renders an area view → view calls `shell(action_slot: :theme_show, action_context: @theme){ … }` → `Shell` top bar calls `render_host_actions(:theme_show, @theme)` → registry resolves the block in view context → descriptors → `RubyUI::Button`s linking to host routes. Clicking a button hits a **host** controller/page (e.g. `/themes/:id/export_theme_db`), unchanged.

## Testing

- **`ActionRegistry` unit test:** `for`/`resolve` returns descriptors; unregistered slot → `[]`; arity-0 and arity-1 blocks both work.
- **`render_host_actions` component test:** renders a registered descriptor as a button with the right path/method; renders nothing when unregistered; honors `method`/`confirm`/`icon`.
- **`Shell` component test:** renders top bar (home link + title) + main (yielded content); renders the sidebar component when given, omits it when nil.
- **Integration:** a gem dummy-app studio page renders through `Shell` (top bar present); with a stubbed registered action → button in output; without → absent.
- **Styling:** `design.css` rebuilt; the existing `DesignTailwindBuildFreshnessTest` stays green.
- Minitest only.

## Risks

- **Route-helper context** — the registered block must resolve host routes at render time, not boot. Mitigation: blocks are `call`ed inside the view context (where `main_app`/url helpers exist); the registry stores blocks, never eager strings. A unit test renders a descriptor whose path is computed from a host route.
- **Token-palette divergence** — if book_design's tokens come from a source the gem lacks, ported components look off. Mitigation: identify the exact token source and mirror it into the scoped build; the #0 proof page surfaces mismatches early.
- **Scoped-build coverage** — the gem's `@source` globs must cover the shell/new components so their classes compile. Mitigation: shell lives under the already-globbed `app/components/**`.
- **book_write regression** — additive only (new config method, new components); book_write registers nothing and its `/design` pages gain the shell. Low risk; covered by rendering a studio page with no registrations.

## Out of scope (later sub-projects)

Rich page-content ports (themes/sizes/docs CRUD, populated sidebars, the editor toolbar + doc-type switcher), retiring book_design's `Pages::*`, table styles, style browser, the host-only flows themselves (they stay host pages the action buttons link to).
