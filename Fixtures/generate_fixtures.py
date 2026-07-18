#!/usr/bin/env python3
"""Generates the synthetic ID3v2 MP3 fixtures under Fixtures/ID3v2/.

Each fixture is a minimal, hand-built ID3v2 tag (no real audio) followed by
one silent MPEG frame so file-type sniffers (exiftool included) recognize it
as an MP3. Frame bodies are constructed byte-for-byte per the ID3v2.3/2.4
spec so they exercise exactly the parsing/disambiguation paths described in
GitHub issue #9, without depending on a real-world source file.

Re-run with `python3 generate_fixtures.py` from the repo root to regenerate
all fixtures deterministically.
"""
import pathlib

OUT_DIR = pathlib.Path(__file__).resolve().parent / "ID3v2"

# One silent, valid-looking MPEG-1 Layer III frame header (128kbps, 44.1kHz,
# stereo) plus zeroed frame body, so the file passes as a real MP3 after the
# ID3v2 tag. Content doesn't matter -- nothing here reads the audio.
MPEG_FRAME = bytes([0xFF, 0xFB, 0x90, 0x00]) + bytes(417 - 4)


def syncsafe(n: int) -> bytes:
    return bytes([(n >> 21) & 0x7F, (n >> 14) & 0x7F, (n >> 7) & 0x7F, n & 0x7F])


def be32(n: int) -> bytes:
    return n.to_bytes(4, "big")


def frame(frame_id: str, data: bytes, version_major: int) -> bytes:
    size = syncsafe(len(data)) if version_major == 4 else be32(len(data))
    return frame_id.encode("ascii") + size + b"\x00\x00" + data


def text_frame(text: str, encoding: int = 0) -> bytes:
    if encoding == 0:
        return bytes([0]) + text.encode("latin-1") + b"\x00"
    if encoding == 3:
        return bytes([3]) + text.encode("utf-8") + b"\x00"
    raise NotImplementedError(encoding)


def wxxx_frame(description: str, url: str, encoding: int = 0) -> bytes:
    if encoding == 0:
        return bytes([0]) + description.encode("latin-1") + b"\x00" + url.encode("latin-1")
    if encoding == 3:
        return bytes([3]) + description.encode("utf-8") + b"\x00" + url.encode("utf-8")
    raise NotImplementedError(encoding)


def txxx_frame(description: str, value: str, encoding: int = 0) -> bytes:
    if encoding == 0:
        return bytes([0]) + description.encode("latin-1") + b"\x00" + value.encode("latin-1") + b"\x00"
    if encoding == 3:
        return bytes([3]) + description.encode("utf-8") + b"\x00" + value.encode("utf-8") + b"\x00"
    raise NotImplementedError(encoding)


def comm_frame(lang: str, description: str, text: str, encoding: int = 0) -> bytes:
    assert len(lang) == 3
    if encoding == 0:
        return bytes([0]) + lang.encode("ascii") + description.encode("latin-1") + b"\x00" + text.encode("latin-1") + b"\x00"
    raise NotImplementedError(encoding)


def plain_url_frame(url: str) -> bytes:
    # WOAS/WOAF/WCOM/etc: no encoding byte, no terminator -- runs to end of frame.
    return url.encode("latin-1")


def build(version_major: int, frames: list[bytes]) -> bytes:
    body = b"".join(frames)
    header = b"ID3" + bytes([version_major, 0, 0]) + syncsafe(len(body))
    return header + body + MPEG_FRAME


def write(name: str, data: bytes) -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    path = OUT_DIR / name
    path.write_bytes(data)
    print(f"wrote {path} ({len(data)} bytes)")


def main() -> None:
    title = frame("TIT2", text_frame("MetaWipe Fixture"), 3)

    # -- WXXX (user-defined URL) --------------------------------------------
    write("wxxx_single.mp3", build(3, [
        title,
        frame("WXXX", wxxx_frame("SourceUrl", "https://example.com/source"), 3),
    ]))

    write("wxxx_distinct_descriptions.mp3", build(3, [
        title,
        frame("WXXX", wxxx_frame("Purchase", "https://example.com/buy"), 3),
        frame("WXXX", wxxx_frame("Artwork", "https://example.com/art.jpg"), 3),
    ]))

    write("wxxx_ambiguous_same_description.mp3", build(3, [
        title,
        frame("WXXX", wxxx_frame("Info", "https://example.com/a"), 3),
        frame("WXXX", wxxx_frame("Info", "https://example.com/b"), 3),
    ]))

    write("wxxx_single_v24_utf8.mp3", build(4, [
        frame("TIT2", text_frame("MetaWipe Fixture", encoding=3), 4),
        frame("WXXX", wxxx_frame("SourceUrl", "https://example.com/sourcé", encoding=3), 4),
    ]))

    # -- TXXX (user-defined text) --------------------------------------------
    write("txxx_single.mp3", build(3, [
        title,
        frame("TXXX", txxx_frame("CatalogNumber", "MW-001"), 3),
    ]))

    write("txxx_distinct_descriptions.mp3", build(3, [
        title,
        frame("TXXX", txxx_frame("CatalogNumber", "MW-001"), 3),
        frame("TXXX", txxx_frame("Mood", "Upbeat"), 3),
    ]))

    write("txxx_ambiguous_same_description.mp3", build(3, [
        title,
        frame("TXXX", txxx_frame("Note", "first"), 3),
        frame("TXXX", txxx_frame("Note", "second"), 3),
    ]))

    write("txxx_single_v24_utf8.mp3", build(4, [
        frame("TIT2", text_frame("MetaWipe Fixture", encoding=3), 4),
        frame("TXXX", txxx_frame("CatalogNumber", "MW-00é", encoding=3), 4),
    ]))

    # -- Single-purpose URL frames (WOAS/WOAF/WCOM) -- issue #8 --------------
    write("woas_source_url.mp3", build(3, [
        title,
        frame("WOAS", plain_url_frame("https://suno.com/song/example"), 3),
    ]))

    write("woaf_file_url.mp3", build(3, [
        title,
        frame("WOAF", plain_url_frame("https://example.com/file.mp3"), 3),
    ]))

    write("wcom_commercial_url.mp3", build(3, [
        title,
        frame("WCOM", plain_url_frame("https://example.com/buy-license"), 3),
    ]))

    # -- COMM (multi-language disambiguation) --------------------------------
    write("comm_multilang.mp3", build(3, [
        title,
        frame("COMM", comm_frame("eng", "", "An English comment."), 3),
        frame("COMM", comm_frame("fra", "", "Un commentaire francais."), 3),
    ]))

    write("comm_multilang_v24.mp3", build(4, [
        frame("TIT2", text_frame("MetaWipe Fixture", encoding=3), 4),
        frame("COMM", comm_frame("eng", "", "An English comment."), 4),
        frame("COMM", comm_frame("fra", "", "Un commentaire francais."), 4),
    ]))


if __name__ == "__main__":
    main()
