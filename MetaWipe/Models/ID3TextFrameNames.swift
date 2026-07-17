import Foundation

/// Maps the human-readable tag names exiftool assigns to ID3v2 frames (e.g. "Title", "Comment")
/// back to their raw 4-character frame IDs (TIT2, COMM), for the subset of frames `ID3Writer`
/// knows how to write.
///
/// Deliberately excludes: TXXX/WXXX (keyed by a user description exiftool doesn't expose
/// alongside the value, so we can't safely identify which one to overwrite), plain URL frames
/// like WCOM/WOAF (no encoding byte — a different, simpler structure we don't handle), frames
/// with a PrintConv exiftool can't reliably reverse if we write the displayed string back
/// literally (date frames TYER/TDAT/TIME/TORY/TRDA/TDEN/TDOR/TDRC/TDRL/TDTG, TCMP's Yes/No,
/// TLEN's millisecond conversion), and structured/binary frames (APIC, GEOB, MCDI, OWNE, PCNT,
/// POPM, PRIV, SYLT, USER, USLT). Comment (COMM) is included despite its extra language/
/// description fields — `ID3Writer` special-cases those.
enum ID3TextFrameNames {
    static let frameIDsByTagName: [String: String] = [
        "Title": "TIT2",
        "Subtitle": "TIT3",
        "Grouping": "TIT1",
        "Artist": "TPE1",
        "Band": "TPE2",
        "Conductor": "TPE3",
        "InterpretedBy": "TPE4",
        "Album": "TALB",
        "OriginalAlbum": "TOAL",
        "Track": "TRCK",
        "PartOfSet": "TPOS",
        "Genre": "TCON",
        "Composer": "TCOM",
        "OriginalArtist": "TOPE",
        "OriginalLyricist": "TOLY",
        "Lyricist": "TEXT",
        "EncodedBy": "TENC",
        "EncoderSettings": "TSSE",
        "Copyright": "TCOP",
        "Publisher": "TPUB",
        "InitialKey": "TKEY",
        "Language": "TLAN",
        "Media": "TMED",
        "BeatsPerMinute": "TBPM",
        "ISRC": "TSRC",
        "FileOwner": "TOWN",
        "InternetRadioStationName": "TRSN",
        "InternetRadioStationOwner": "TRSO",
        "OriginalFileName": "TOFN",
        "Comment": "COMM",
    ]
}
