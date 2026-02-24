# PaperTok (Papers Feed) — Integration Notes (Fork)

This fork integrates **PaperTok** into Anx Reader as a first-class home tab.

## Summary

- Home tab: **PaperTok** (first tab by default)
- Feed UX: vertical PageView (TikTok-style), historical random feed
- Detail UX: 2 tabs
  - **Explain**: title + one-liner + image carousel + *Markdown-rendered* explanation
  - **Original**: import actions (EPUB/PDF) + external link
- Import behavior:
  - **EPUB/PDF**: download → import into bookshelf → **auto-open** the book in Reading Page

## Data source

- Default API base: `https://papertok.ai`
- Endpoints used:
  - Feed: `GET /api/papers/random?limit=20&lang=zh`
  - Detail: `GET /api/papers/{id}?lang=zh`

> Media URLs returned by PaperTok may be relative (e.g. `/static/...`).
> The client resolves them against the base URL.

## EPUB editions (EN / ZH / Bilingual)

PaperTok detail can expose up to 4 fields:

- `epub_url` (primary)
- `epub_url_en`
- `epub_url_zh`
- `epub_url_bilingual`

The UI shows an **edition picker** (BottomSheet) listing only available editions.

## Home navigation configuration

The fork replaces scattered bottom-nav switches with a unified config:

- **Order**: `homeTabsOrder` (List<String>)
- **Enable**: `homeTabsEnabled` (Map<String,bool>)

Constraints:
- `papers` (PaperTok) is **mandatory** and cannot be disabled
- `settings` is **mandatory** and cannot be disabled

UI entry:
- Settings → Appearance → **Home navigation**
  - reorder by drag
  - toggle visibility for optional tabs
  - reset to defaults

## Import + auto-open implementation

To provide the “Import → start reading immediately” UX, PaperTok import uses a dedicated flow:

1) Download file to temp directory
2) Import by calling the existing metadata pipeline (`getBookMetadata`)
3) Resolve the imported book (prefer lookup by MD5)
4) Push Reading Page route (`pushToReadingPage`)

This avoids the batch import dialog used by `importBookList()` and guarantees the auto-open behavior.

## Code map

- Feed page: `lib/page/home_page/papers_page.dart`
- Detail page: `lib/page/papers/paper_detail_page.dart`
- PaperTok API client: `lib/service/papertok/papertok_api.dart`
- Models: `lib/service/papertok/models.dart`
- Home nav config UI: `lib/page/settings_page/home_navigation.dart`
- Home nav config storage: `lib/config/shared_preference_provider.dart`

## Known limitations

- The feed is random; it may return duplicates. The client de-dupes by paper id.
- macOS/iOS builds require correct signing setup (unrelated to PaperTok itself).
