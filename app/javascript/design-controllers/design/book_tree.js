// Pure helpers for design--book-tree (no DOM): the open book-tree groups, the
// cookie that remembers them (read server-side by Design::Views::BookTree) and
// which theme-page grid sections they show.

export const COOKIE_NAME = "design_tree_open"
// Same as Design::Views::BookTree::KEYS / DEFAULT.
export const KEYS = ["cover", "frontmatter", "bodymatter", "rearmatter", "other"]
export const DEFAULT = ["bodymatter"]
const ONE_YEAR = 60 * 60 * 24 * 365

// The server-rendered value (already validated): "frontmatter,bodymatter".
export function parseOpen(value) {
  return String(value ?? "").split(",").map((k) => k.trim()).filter(Boolean)
}

// The open keys from a cookie string (the controller passes the page cookie),
// exactly like Design::Views::BookTree.open_keys: no cookie → null (caller falls
// back); "" → []; unknown keys dropped; no known key at all → DEFAULT.
export function readCookieKeys(cookieString) {
  const pair = String(cookieString ?? "").split(";").map((p) => p.trim())
    .find((p) => p.startsWith(`${COOKIE_NAME}=`))
  if (pair === undefined) return null
  let value
  try { value = decodeURIComponent(pair.slice(COOKIE_NAME.length + 1)) } catch { return [...DEFAULT] }
  const tokens = parseOpen(value)
  if (tokens.length === 0) return []
  const known = [...new Set(tokens)].filter((k) => KEYS.includes(k))
  return known.length ? known : [...DEFAULT]
}

// The same array back when nothing changes, so callers can skip the write.
export function toggled(keys, matter, open) {
  const has = keys.includes(matter)
  if (open === has) return keys
  return open ? [...keys, matter] : keys.filter((k) => k !== matter)
}

export function cookieFor(keys) {
  return `${COOKIE_NAME}=${encodeURIComponent(keys.join(","))}; path=/; max-age=${ONE_YEAR}; SameSite=Lax`
}

// matters: each grid section's data-matter, in order. The hint shows only when
// there are sections and every one is hidden.
export function gridState(keys, matters) {
  const hidden = matters.map((m) => !keys.includes(m))
  return { hidden, hintHidden: matters.length === 0 || hidden.some((h) => !h) }
}
