# TubMeasure

An iPhone app that scans a bathroom with LiDAR and turns it into a top-down plan, an
isometric drawing and a 3D model, with the measurements you need for a tub, shower, toilet or
vanity job.

## What it measures

| Measurement | How it is found |
| --- | --- |
| Room length, width, height, floor area, each wall's length | Automatic (LiDAR scan) |
| Toilet overall height, width, depth, centreline to side walls | Automatic |
| Toilet seat height | You mark the seat rim |
| Flange bolt distance from the wall (rough-in), bolt spacing | You mark the two closet bolts |
| Tub length, width, rim height | Automatic |
| Drain centre to the closest tub or shower edge, and to each edge and nearest walls | You mark the drain; tub edges are automatic, shower edges/curbs you mark |
| Vanity width, depth, height, sink height, position along its wall | Automatic |
| Window width, height, sill and head height, position along its wall | Automatic |
| Door and opening width and height, position along the wall | Automatic |
| Any two points (tape measure) | You mark custom points |

It also lists loose items to clear before work starts: chairs (from the 3D scan), and
carpets/bath mats, toiletries, shower curtains, towels and bins (recognised from camera frames).

## Using it

1. **Scan a bathroom**: walk slowly around the room, sweeping each wall from floor to ceiling.
   Tap the camera button to keep reference photos. Tap **Done scanning**.
2. **Mark points**: the camera stays on. Pick a point type, aim the crosshair at it from
   30–100 cm away and tap **Mark**. Mark the drain centre, both toilet flange bolt caps, and
   (for a shower) points along the edge or curb. Tap **Finish**.
3. Switch between **Plan**, **Isometric**, **3D**, **Sizes** and **Items**. Change inches/cm
   from the toolbar, and share the measurement report or the USDZ 3D model from the ⋯ menu.

No LiDAR device handy? **Open a demo room** shows every screen with a sample 5 × 8 ft bathroom.

## Things to know

- **Accuracy.** Apple's LiDAR room scanning is typically within about 1–2 cm (½ in). Confirm
  critical dimensions with a tape before ordering or cutting. Marked points are as accurate as
  your aim; the bolt-spacing readout (should be about 6 in) is a quick check on flange marks.
- **Drains and flange bolts are marked by hand** because the scanner does not recognise them.
- **Shower stalls are not recognised as objects** (tubs are). Mark the shower edge or curb.
- **Toilet height is to the top of the scanned shape**, normally the tank lid. Mark the seat
  rim for seat height.
- **Loose items from the camera are a presence check**, not a location, and the recogniser can
  miss small things or guess wrong. You can remove or add items on the Items tab.

## Requirements

- iPhone or iPad with LiDAR (iPhone 12 Pro or later Pro models, iPad Pro 2020 or later), iOS 17+
- Xcode 16 or later to build

## Build and run

1. Open `TubMeasure.xcodeproj` in Xcode.
2. Select the **TubMeasure** target → **Signing & Capabilities** and choose your team.
3. Plug in your iPhone, select it as the run destination and press Run.

## Project layout

```
TubMeasure/Core      Measurement engine and data model (pure Swift, no Apple frameworks)
TubMeasure/Capture   RoomPlan scanning, AR point marking, Vision item detection
TubMeasure/Views     SwiftUI screens: plan, isometric, 3D, measurements, items
TubMeasure/Store     Saved scans (Documents/Scans)
Tests/               Unit tests for the measurement engine
```

The measurement maths has unit tests that run anywhere Swift does:

```
swift test
```
