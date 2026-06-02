## 2026-05-23 — Fix: heading tag not applied in rendererTk

### Fixed

- **`lib/tm/docir/rendererTk-0.1.tm`** — headings were inserted but never
  visually tagged. In the `heading` block the start index was captured
  with `[$textWidget index "end"]`, which points *past* the text widget's
  implicit trailing newline. The heading text is inserted *before* that
  newline, so the subsequent `tag add heading$lvl $startIdx $endIdx`
  covered an empty range and the `heading$N` tag was never applied.

  Consequences: headings rendered like normal body text (no bold/size) in
  the Tk view, the TOC anchor mark was set at the wrong position, and a
  widget dump carried no heading information (so `docir::tkSource` could
  not recover heading levels).

  Fix is one line — capture the start *before* the trailing newline:

  ```
  -                set startIdx [$textWidget index "end"]
  +                set startIdx [$textWidget index "end-1c"]
  ```

### Compatibility

- No API change. Headings now carry the `heading$N` tag as documented in
  renderer-spec.md; the anchor mark lands at the heading start. Verified
  by rendering a DocIR with H1/H2 and confirming the tags appear in
  `$w dump -all`, and that `docir::tkSource::fromWidget` recovers the
  heading levels.

---
