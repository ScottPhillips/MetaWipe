# ID3v2 fixtures

Synthetic MP3 fixtures for verifying `ID3Writer` changes without needing a
real-world source file (see issue #9). Each file is a minimal, hand-built
ID3v2 tag followed by one silent MPEG frame — enough for exiftool (and
`ID3Writer`) to recognize it as an MP3, nothing else. They're regenerated
deterministically by `generate_fixtures.py`:

```
python3 Fixtures/generate_fixtures.py
```

Verify what a fixture actually contains with the exiftool copy this app
bundles (works from Linux too — it's pure Perl):

```
perl MetaWipe/Resources/ExifTool/exiftool -G1 -a -u -s Fixtures/ID3v2/<file>.mp3
```

## Files

| File | Covers | Expected tag(s) |
| --- | --- | --- |
| `wxxx_single.mp3` | One unambiguous WXXX frame | `SourceUrl` |
| `wxxx_distinct_descriptions.mp3` | Two WXXX frames, different descriptions | `Purchase_URL`, `Artwork_URL` |
| `wxxx_ambiguous_same_description.mp3` | Two WXXX frames, same description | `Info_URL` (×2 — ambiguous, not offered for editing) |
| `wxxx_single_v24_utf8.mp3` | WXXX in ID3v2.4 with UTF-8 (encoding byte 3) instead of Latin-1 | `SourceUrl` |
| `txxx_single.mp3` | One unambiguous TXXX frame | `CatalogNumber` |
| `txxx_distinct_descriptions.mp3` | Two TXXX frames, different descriptions | `CatalogNumber`, `Mood` |
| `txxx_ambiguous_same_description.mp3` | Two TXXX frames, same description | `Note` (×2 — ambiguous) |
| `txxx_single_v24_utf8.mp3` | TXXX in ID3v2.4 with UTF-8 | `CatalogNumber` |
| `woas_source_url.mp3` | Single-purpose WOAS frame (issue #8) | `SourceURL` |
| `woaf_file_url.mp3` | Single-purpose WOAF frame (issue #8) | `FileURL` |
| `wcom_commercial_url.mp3` | Single-purpose WCOM frame (issue #8) | `CommercialURL` |
| `comm_multilang.mp3` | Two COMM frames, `eng` + `fra`, ID3v2.3 | `Comment` (eng), `Comment-fra` |
| `comm_multilang_v24.mp3` | Same as above, ID3v2.4 (syncsafe frame sizes) | `Comment`, `Comment-fra` |

`ID3TextFrameNames.urlFrameIDsByTagName` also covers `WCOP`/`WOAR`/`WORS`/
`WPAY`/`WPUB` — not given dedicated fixtures since they share the exact same
on-disk structure as WOAS/WOAF/WCOM (no encoding byte, URL runs to end of
frame), just a different frame ID and exiftool tag name.

`comm_multilang.mp3`/`comm_multilang_v24.mp3` cover the bare-`Comment`
disambiguation case (issue #10): exiftool names the `eng` comment bare
`Comment` (no `-eng` suffix) when multiple `COMM` frames with different
languages exist, and `ID3Writer.resolveCommentFrame` matches that bare name
against whichever `COMM` frame's language is `eng`, mirroring exiftool's own
naming rule.
