# AI Translation Design Notes

## 0. Current pipeline

Full-text translation in the reader is implemented inside `foliate-js` and calls back into Flutter:

- JS calls: `window.flutter_inappwebview.callHandler('translateText', text)`
- Flutter handler: `lib/page/book_player/epub_player.dart` (`translateText` handler)
- Translation provider: `Prefs().fullTextTranslateService.provider.translateTextOnly(...)`

AI translation provider:

- `lib/service/translate/ai.dart` → builds `AiPrompts.translate` prompt and streams via `aiGenerateStream(...)`.

## 1. Observed issues

1. **Full-text translation output is “weird”**
   - The current `AiPrompts.translate` prompt is designed as “translation + dictionary + encyclopedia + notes”.
   - This is good for a *selected snippet*, but bad for *inline full-text translation*.

2. **PDF text is often messy**
   - Text layer can be missing (scanned PDFs) or fragmented.
   - Even with a text layer, reading order can be incorrect.

3. **Long text chunks may fail**
   - Full-text translation may feed long paragraphs repeatedly.
   - Higher failure rate (timeouts / provider limits) and poor UX.

## 2. Goals

- Selection translation: keep “translator + tutor” experience.
- Full-text translation: output **clean translation only**, minimal formatting.
- Provide safe fallbacks for PDF.

## 3. Proposed design

### 3.1 Split prompts by scenario

Add two prompts:

- `translate_selection` (existing behavior): translation + explanation + glossary.
- `translate_fulltext` (new): **translation-only**.

Rules for `translate_fulltext`:

- Output only the translated text.
- No headings, no dictionary sections.
- Preserve paragraph breaks where possible.

### 3.2 Route based on caller

- `translateText` handler (full-text translator) must use `translate_fulltext`.
- “Selection translate” UI (context menu translate) uses `translate_selection`.

### 3.3 PDF-specific UX hardening

- If format is PDF:
  - Prefer selection translation.
  - Consider disabling inline full-text translation mode by default, or show a warning.

### 3.4 Chunking / length caps

For full-text translation:

- Limit each translation request length (e.g. 800–2000 chars) to reduce failures.
- If input is longer, split by sentence/paragraph boundaries.

## 4. Testing / Acceptance

- EPUB full-text translation produces clean inline translation (no “analysis” blocks).
- Selection translation still provides detailed explanation.
- PDF:
  - selection translation works
  - full-text translation is either stable or safely discouraged

## 5. Future extension

- If MinerU OCR is enabled for scanned PDFs, use OCR text as the source for translation.
