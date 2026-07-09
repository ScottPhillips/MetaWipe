# MetaWipe

A native macOS app for viewing, editing, and erasing file metadata — EXIF/IPTC/XMP, GPS location, extended attributes (Finder comments/tags), and filesystem timestamps.

[**Download MetaWipe-1.0.0.dmg**](https://github.com/ScottPhillips/MetaWipe/releases/latest)

## Features

- View and filter all metadata tags on any file, grouped by source (EXIF, IPTC, XMP, GPS, etc.)
- Edit and save individual tag values
- View and remove individual extended attributes
- Edit filesystem creation/modification timestamps
- One-click **Erase All Metadata**, with separate toggles for embedded metadata, extended attributes, and timestamps, and an option to keep a backup copy

## Installing

Download the DMG from the [latest release](https://github.com/ScottPhillips/MetaWipe/releases/latest), open it, and drag MetaWipe to Applications.

This build is ad-hoc signed (no paid Apple Developer ID), so macOS Gatekeeper will block the first launch. To open it: right-click (or Control-click) MetaWipe.app in Applications and choose **Open**, then confirm in the dialog that appears. You only need to do this once.

## Building from source

MetaWipe wraps [exiftool](https://exiftool.org) (vendored in `MetaWipe/Resources/ExifTool` so the built app works standalone) and uses [XcodeGen](https://github.com/yonaskolb/XcodeGen) to generate the Xcode project:

```
brew install xcodegen
xcodegen generate
open MetaWipe.xcodeproj
```
