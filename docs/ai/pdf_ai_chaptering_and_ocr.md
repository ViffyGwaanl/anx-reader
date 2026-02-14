# PDF AI Chaptering & OCR (MinerU) — Design Notes

## 0. Background / Current Behavior

Anx Reader uses `foliate-js` (WebView) to render multiple formats.

### EPUB

- Chapters and TOC are natural.
- AI tools can fetch:
  - current chapter content
  - chapter content by TOC href

### PDF

In `assets/foliate-js/src/pdf.js`:

- `book.sections` is built from pages: **1 page = 1 section**
- `book.toc` comes from `pdf.getOutline()` when available

Implications:

- If a PDF has no outline, it effectively has **no chapter structure**.
- Scanned PDFs often have no usable text layer → AI tools return empty/garbled content.

## 1. Goals

1. Make PDF AI “current chapter” behave closer to a real chapter when outline exists.
2. Provide a usable fallback when outline is missing.
3. Support scanned PDFs via OCR (MinerU):
   - cache results
   - allow AI tools to fall back to OCR text

## 2. Chaptering strategies

### Strategy A — Outline-based (preferred when outline exists)

Define a “chapter” as a **page range** determined by two adjacent outline entries.

- Resolve TOC href → start page index
- Find next TOC item’s page index → end page index
- Chapter content = concatenated page text from `start..end` (respect `maxChars`)

### Strategy B — Page-window fallback (when outline missing)

Define a “chapter-like context” around current page:

- Content = current page ± N pages (default N=2 or 3)
- Also used by `current_chapter_content` when no outline

### Strategy C — OCR-based (MinerU) for scanned PDFs

- Run OCR once per PDF, store per-page text results
- When PDF text layer is empty/very short, AI tools use OCR page text

## 3. Proposed changes to AI tool behavior

Tools involved:

- `current_book_toc`
- `current_chapter_content`
- `chapter_content_by_href`

### Desired behavior for PDF

1. `current_book_toc`
   - If outline exists: return outline as TOC
   - If not: return empty TOC (as today), but UI/AI should understand “no outline”

2. `chapter_content_by_href(href)`
   - If PDF + outline: return page-range content (Strategy A)
   - Else: resolve to a single page section (legacy behavior)

3. `current_chapter_content`
   - If PDF + outline + current tocItem: Strategy A (page-range)
   - Else: Strategy B (page-window)

## 4. MinerU OCR integration (scanned PDFs)

### 4.1 Requirements

Need an OCR interface:

- HTTP API (preferred) or local CLI runner
- Input: PDF file
- Output: per-page text (plus optional layout/markdown)

### 4.2 Cache design

- Cache key: book md5 or book id
- Storage:
  - `mineru/<key>/pages/page_0001.txt` ...
  - `mineru/<key>/manifest.json` (status, createdAt, version)

Status:

- not_started / processing / ready / failed

### 4.3 Fallback logic

When retrieving PDF content:

- If text-layer content length < threshold (e.g. < 80 chars):
  - try OCR cache
  - if cache missing: prompt user to run OCR (or start background job)

## 5. Testing / Acceptance

- PDF with outline:
  - TOC visible
  - “current chapter” AI pulls multi-page range

- PDF without outline:
  - “current chapter” AI pulls page-window context

- Scanned PDF:
  - After OCR, AI tools return meaningful text
  - OCR is cached; subsequent calls do not re-run OCR

## 6. Risks

- PDF text extraction order may be messy even with text layer.
- OCR can be slow/large; caching and progress UI required.
- iOS background execution limits: OCR may need user foreground time.
