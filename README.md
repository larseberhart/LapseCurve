# LapseCurve

LapseCurve is a native macOS editor for interpolating Lightroom development settings across a time-lapse photo sequence. You develop selected key photos in Lightroom, save their metadata, and use LapseCurve to calculate the settings for the photos between them. After reviewing the intervals and parameter graphs, you explicitly write those settings into existing XMP sidecars and read them back into Lightroom for rendering.

**LapseCurve edits metadata, not image pixels.** It does not export JPEGs, render RAW development, assemble movies, automate Lightroom, or modify its catalog. The image export and video assembly steps happen in other applications.

**Current status:** functional developer build with experimental XMP writes, not a distribution-ready or Adobe-certified release. Back up the complete sequence and sidecars before using it on important work. LapseCurve does not create sidecar backups.

Documentation reviewed against the current implementation on **2026-10-26**. Current limitations and release constraints are summarized in [Limitations and References](#limitations-and-references).

## Contents

- [What LapseCurve Does](#what-lapsecurve-does)
- [Requirements](#requirements)
- [Core Concepts](#core-concepts)
- [End-to-End Workflow](#end-to-end-workflow)
- [User Interface](#user-interface)
- [Interpolation and Metadata Rules](#interpolation-and-metadata-rules)
- [Supported Development Fields](#supported-development-fields)
- [Projects, Recovery, and File Safety](#projects-recovery-and-file-safety)
- [Exporting Images from Lightroom](#exporting-images-from-lightroom)
- [Making a Video](#making-a-video)
- [Implementation](#implementation)
- [Building and Testing](#building-and-testing)
- [Troubleshooting](#troubleshooting)
- [Limitations and References](#limitations-and-references)

## What LapseCurve Does

| Capability | Current behavior |
| --- | --- |
| Sequence discovery | Scans a chosen folder for recognized photo extensions, resolves existing same-basename XMP sidecars, and reports metadata problems. |
| Key-photo detection | Exactly one star identifies a keyframe. A valid sidecar rating takes precedence over embedded rating metadata. |
| Development import | Reads allowlisted numeric Camera Raw settings, camera defaults, and available capture metadata. |
| Interpolation | Calculates values strictly between consecutive keyframes using Linear, Smoothstep, or Hold, with a per-interval Curve menu. |
| Parameter graphs | Shows actual calculated frame samples for parameters that change between interval endpoints. |
| Inspection | Displays capture metadata and read-only development values; green identifies parameters participating in interval interpolation. |
| Execution | Preflights and, after confirmation, updates existing intermediate-frame XMP sidecars in place. |
| Repeated execution | Refreshes baselines after successful writes so another curve can be applied without reloading LapseCurve's own changes. |
| Project persistence | Saves and opens versioned project documents with a previous-document recovery snapshot and source relinking. |
| History | Undo and Redo restore segment curve choices in edit order. |

It does **not** provide in-app keyframe grading, rating changes, manual exposure corrections, capture-exposure compensation, image-based deflicker, rendered playback, masks/AI interpolation, image export, or video export.

## Requirements

| Item | Requirement or verified environment |
| --- | --- |
| Operating system | Deployment target is macOS 27.0 or later. Earlier macOS versions are not supported by this project. |
| Build tools | Recorded toolchain: Xcode 27.0, build 27A266a, Swift 6.4. The source uses Swift 6 language mode. |
| Hardware evidence | Builds/tests have been exercised on an arm64 MacBook Pro running macOS 27.0.1. Intel/universal artifacts are not verified. |
| Photo development | Lightroom Classic or a compatible Camera Raw workflow that supplies readable existing XMP sidecars. Exact Adobe behavior requires your own round-trip check. |
| Write access | Permission to the source folder and its existing intermediate sidecars. |
| Video tools | Optional and external: FFmpeg, Resolve, Final Cut Pro, Premiere Pro, or another sequence-capable editor. None is bundled or called by LapseCurve. |

There is currently no approved downloadable installer, notarized release, or App Store distribution. For development, open [LapseCurve.xcodeproj](LapseCurve.xcodeproj) in Xcode and run the `LapseCurve` scheme.

## Core Concepts

### Sequence, keyframe, and interval

A **sequence** is the ordered set of photos found in the working folder. A **keyframe**, also called a **key photo**, is a photo with an exactly-one-star rating. An **interval** connects two consecutive keyframes and contains the intermediate photos whose settings can be calculated.

For example, keyframes at displayed frames 1, 101, and 201 produce two intervals. Frames 2 through 100 belong to the first; frames 102 through 200 belong to the second. The three keyframes remain read-only. Photos before the first or after the last keyframe are not extrapolated.

Use key photos near the beginning and end of the desired output range. Additional key photos are useful where lighting or the intended grade changes direction. Ratings of two through five stars do not make additional LapseCurve keyframes.

### Settings are not rendered brightness

The graphs show development parameter values, not measured image brightness. A smooth Exposure curve does not guarantee a flicker-free movie: aperture variation, shutter changes, illumination, moving subjects, noise, and Lightroom's rendering can all affect the result.

Embedded thumbnails are source previews. They are not regenerated using the calculated settings and cannot certify the final appearance. Lightroom/Camera Raw remains the rendering authority.

### Project state versus source metadata

The `.lapsecurve` project contains saved editor state and imported metadata baselines. The source photos and XMP files remain external. Opening a project does not automatically adopt later Lightroom changes: **Reload Metadata** is the explicit import step.

Saving a project and executing interpolations are different actions. **Save** saves the project document; **Execute Interpolations** changes eligible source sidecars after confirmation.

## End-to-End Workflow

### 1. Prepare and protect the source folder

1. Make a separate backup of the photos, existing sidecars, and relevant Lightroom catalog before experimenting.
2. Put one intended source sequence in a dedicated folder. Keep rendered exports and alternate RAW/JPEG versions elsewhere so they are not counted as additional photos.
3. Keep filenames and relative paths stable while working. Relinking a folder is supported; arbitrary per-file renaming is not a media-reconciliation workflow.
4. Keep each existing sidecar beside its photo, with the same basename, for example `frame-0001.NEF` and `frame-0001.xmp`. These names are illustrative, not repository fixtures.

The editor uses a **nonrecursive scan** and excludes hidden files by default. The package has scan options, but the current UI does not expose a recursion or extension-filter control.

Recognized extensions are:

- RAW-family names: DNG, NEF, NRW, CR2, CR3, ARW, SRF, SR2, RAF, RW2, ORF, PEF, SRW.
- Raster names: JPG, JPEG, TIF, TIFF, PNG, HEIC.

Recognition means the scanner considers the file. It does not guarantee successful metadata extraction, a RAW thumbnail, or certified camera compatibility. Existing external XMP is required for writes, regardless of the photo extension.

### 2. Grade the key photos in Lightroom

1. Import the source sequence into Lightroom Classic.
2. Choose the anchor photos and assign them exactly one star.
3. Develop those anchors with the desired supported settings. Keep non-interpolated settings such as crop, profile, and process version consistent yourself where the project requires it.
4. Save metadata to files, typically using Lightroom's **Metadata > Save Metadata to File**. Select all relevant photos, not only the anchors, so eligible intermediate photos already have metadata on disk.
5. Verify that the expected sidecars actually exist before continuing.

**Format caveat:** Adobe may embed metadata in formats such as DNG, JPEG, or TIFF rather than produce an external sidecar. Saving metadata is therefore not a promise that a separate XMP will appear. LapseCurve never manufactures a missing sidecar or changes its write policy to accommodate an embedded-only workflow. Use a format/workflow with existing Lightroom-generated external sidecars when you need interpolation writes.

Do not blanket-synchronize the keyframe grade over the intermediate images after LapseCurve has written them; that can replace the calculated variation.

### 3. Load and inspect the sequence

1. Launch LapseCurve and choose the working folder, or use **Open** to load an existing project.
2. Wait for scanning and snapshot calculation to finish.
3. Check the supported-photo, key-photo, and in-range counts.
4. Check ordering, endpoint positions, warnings, and missing sidecars before writing.
5. Select a key-photo row to inspect its imported values, or an interval header to inspect its first intermediate frame.

Capture time participates in scan ordering. When EXIF time is unavailable, the scanner may use filesystem modification time with a warning. Natural filename ordering and tie/fallback rules also participate. If files were copied, touched, or exported in a way that changes their timestamps, inspect the displayed sequence rather than assuming the order is correct.

### 4. Choose interval curves

Use the **Curve** menu in each Interpolation element:

| Choice | Behavior | Typical reason to choose it |
| --- | --- | --- |
| Default | Uses each parameter's configured strategy, falling back to the project default. | Retain per-field behavior, including Hold for AutoLateralCA. |
| Linear | Changes at a constant rate in the configured interpolation coordinates. | A predictable ramp between anchors. |
| Smoothstep | Eases away from the first anchor and into the second. | A gradual transition with gentler ends. |
| Hold | Keeps the left anchor's value for intermediate frames; the right keyframe retains its own value. | A deliberate step or a setting that should remain fixed across the interval. |

An explicit interval choice takes precedence over the parameter definitions for all calculated fields in that interval. It is not a per-parameter curve editor. In particular, take care when forcing a smooth curve over a numeric field that represents a switch; Adobe semantics remain experimental.

Graphs and inspector values update after the background calculation completes. Undo is **Command-Z**; Redo is **Command-Shift-Z**. These actions change curve choices, not the source keyframe grade and not previously written files.

### 5. Save the project

Use the toolbar **Save** action. On the first save, select a project destination. Later saves update the associated project document. The current toolbar is not a general Save As, recent-projects, or autosave interface.

Save explicitly before closing. Do not rely on autosave or a save-before-close prompt. The model protects edits made during an asynchronous save from being incorrectly marked saved, but that is not an automatic saving feature.

### 6. Close Lightroom and execute

1. Finish saving the intended Lightroom metadata and close Lightroom Classic. Also avoid any other program that could write these sidecars.
2. If Lightroom changed anything since the current import, use **Reload Metadata** first and review the refreshed intervals.
3. Click the footer **Execute Interpolations** button.
4. Review the preflight counts, candidate fields, existing-sidecar list, output folder, warnings, and overwrite policy.
5. Confirm **Execute Interpolations** in the sheet only when the plan is correct.
6. Wait for the per-file results. A partially completed or cancelled run is not a rollback; successfully committed files remain updated.

LapseCurve replaces eligible existing sidecars **in place, without backups**. It skips missing sidecars and never writes keyframe metadata. Atomic replacement protects each individual commit; it does not make the entire sequence one all-or-nothing transaction.

After a successful run, you can choose another curve and execute again without reloading LapseCurve's own writes. Successful results refresh the exact committed baseline bytes. Failed/cancelled entries retain their old baselines, and a fresh preflight and confirmation are required for another run.

Keep Lightroom closed through this process. Byte comparisons and a LapseCurve lock file protect against stale inputs and cooperating LapseCurve writers; they cannot establish a permanent lock against a noncooperating external editor.

### 7. Read the results in Lightroom

1. Reopen Lightroom Classic.
2. Select the affected sequence and use **Metadata > Read Metadata from File** before making another metadata save or synchronizing development settings.
3. Inspect several intermediate images, especially near interval boundaries and where parameters differ most.
4. Check the actual rendered image, not just the numeric sliders. Confirm profile, white balance, tone, detail, and unsupported settings behave as intended.
5. When satisfied, export rendered still images as described below.

Reading metadata can replace catalog-only edits. Resolve any intentional catalog changes before choosing to read from disk. A later catalog save can otherwise overwrite the XMP settings LapseCurve wrote.

## User Interface

### Toolbar and activity state

Most toolbar actions are icons with tooltips.

| Element | Purpose |
| --- | --- |
| Folder name | Identifies the working source; the unlinked state indicates that source access must be restored. |
| Activity indicator/status | Reports scanning, preview loading, calculation, preflight work, completion, and errors. |
| Undo/Redo arrows | Restore interval curve choices. They are disabled when history is unavailable or conflicting work is active. |
| Reload Metadata | Explicitly imports metadata saved externally by Lightroom. There is no background folder watcher or catalog integration. |
| Open folder icon | Opens a `.lapsecurve` project. It does not import a new unrelated sequence into the current project. |
| Save icon | Saves the current project document, not image files or a video. |
| Choose/Change Folder | Chooses the initial source; once a project exists, the folder selection follows the source-relinking path and preserves that project's frame state. |
| Relink Source | Restores access to the folder expected by an opened project. |

**Important distinction:** Change Folder is not a New Project command. Do not use it to substitute an unrelated shoot and expect the existing project to become that sequence. Open the intended saved project, or start a fresh app session to scan a different sequence.

Source/project switching is blocked during confirmed sidecar execution. Execution is disabled while scanning, calculating, preparing another plan, or already writing. Saving and background calculation have request/session safeguards so an obsolete completion cannot replace newer state.

### Sequence statistics

The stats bar summarizes supported photos, exactly-one-star key photos, and intermediate photos in range. Counts describe discovered/modelled frames; they do not mean that every intermediate has a writable sidecar. Preflight determines the actual write candidates.

Warnings can include absent timestamps, filesystem-time fallback, conflicting ratings, unreadable metadata, unsupported auxiliary sidecars, or unavailable thumbnails. The editor also identifies photos outside the first/last keyframe range.

### Key-photo rows

The main list is sequence-first. Key-photo rows contain a cached source thumbnail when available, filename, sequence position, available capture metadata, rating provenance, a development summary, and warnings. Selecting a row opens its details in the inspector. Keyframe grading and ratings remain editable only in Lightroom.

There is no large rendered-preview workspace, movie playback, or separate timeline strip in the current primary layout. The former unused shell views have been removed.

### Interpolation elements

Each pair of consecutive key photos has an Interpolation element showing endpoint filenames/positions, the intermediate-photo count, Curve menu, and unavailable-field/calculation warnings. Selecting its header selects the first intermediate frame when one exists.

Intervals with no intermediate photos have nothing to write or graph. A missing parameter at an endpoint remains a diagnostic rather than an invitation to fill in a value manually.

### Parameter graphs

- A responsive grid appears immediately below the interval, with one graph per changed parameter.
- Every graph uses actual engine samples, including the endpoint anchors; it does not invent a second UI-only interpolation.
- Frame position is the horizontal axis. Parameter values use independent vertical scales and labelled units, so different graphs are not directly comparable by slope or height alone.
- Larger endpoint markers distinguish keyframe anchors. Hold is drawn as a step ending at the right keyframe. Linear/Smoothstep join the actual discrete samples without extra spline smoothing.
- Missing or nonfinite samples split the line. Constant parameters and white balance left As Shot at both anchors are omitted.
- Hover shows the nearest available frame, filename, formatted value, and keyframe/calculated status. Hover does not select frames, edit points, or dirty the project.

Graph positions retain raw calculated precision; labels follow the field's Lightroom-style precision. A displayed graph is not proof that Lightroom recognizes the field or that its sidecar can be written. The graph model is transient and rebuilt when calculations change, not serialized into the project.

### Inspector: Frame

The **Frame** tab shows the selected filename, read-only keyframe indication where applicable, capture time, shutter, aperture, ISO, rating, rating source, and metadata status. Unavailable data is shown as unavailable rather than inferred into an exposure correction.

The existing left/right arrow navigation moves selection to adjacent sequence frames. Selection is not limited to the visible key-photo rows; an interval header provides an entry point to its intermediate frames.

### Inspector: Development

The **Development** tab displays imported or calculated parameter names and values. It has no adjustment sliders. Repeated key-photo subtitles and the redundant keyframe-immutability sentence have been removed.

**Green means the parameter changes across the relevant keyframes and participates in interpolation**, matching the interval graphs. For an intermediate frame this is its interval; for a keyframe it is the union of applicable adjacent intervals with intermediate photos.

Unchanged values, values equal at Lightroom precision, unavailable endpoint fields, and white balance left As Shot remain neutral. The highlight remains after writing because it describes interpolation, not an outstanding disk change. Green does not mean a keyframe will be modified or that a skipped/missing sidecar will suddenly become writable.

Where applicable, provenance labels such as `calculated`, `as shot`, or `assumed neutral` explain the value source. There are no manual exposure override or Capture Exposure Compensation controls.

### Execution sheet

Preflight lists intermediate/ready/skipped counts, participating supported fields, imported XMP baselines, source/output location, in-place overwrite policy, warnings, and candidate sidecars. Some skipped entries are harmless no-ops because the rounded value already matches; others require action. Review warnings and per-file results rather than treating one count as a compatibility verdict.

The second Execute button is the explicit write confirmation. During execution, progress and **Cancel Execution** are available. Results distinguish updated, failed, and not-attempted/cancelled files, and remain visible after the used plan is invalidated. Hovering a result can reveal its detailed failure message. **Done** closes the sheet; closing it is not the same as requesting cancellation.

## Interpolation and Metadata Rules

### Coordinates and curve semantics

New projects use frame-index interpolation and the Linear project default. The model/engine also supports capture-time coordinates and explicit missing-value policies, but the current UI does not expose a global time-basis or missing-policy editor.

For normalized interval progress $t$ and endpoint values $a$ and $b$:

| Strategy | Value |
| --- | --- |
| Linear | $a + (b-a)t$ |
| Smoothstep | $a + (b-a)t^2(3-2t)$ |
| Hold | $a$ at intermediate frames; the right anchor remains $b$ |

An explicit segment choice takes precedence over a parameter's configured strategy, which takes precedence over the project default. Default currently preserves Hold for AutoLateralCA and Linear for the other registered fields. There is no per-parameter curve picker, editable Bezier control, or enabled monotone-cubic mode.

The engine preserves keyframe numeric samples and emits no extrapolated values outside the anchor range. Its result includes keyframe samples for inspection; that does not authorize writing those files.

### Rating authority

A valid sidecar `xmp:Rating` is authoritative. An embedded disagreement is surfaced, not silently preferred. Embedded rating is a fallback when there is no readable sidecar rating; malformed or duplicate/conflicting ratings are handled diagnostically and must not be assumed to identify a usable anchor. Exactly one star is required, not "one star or higher."

### Defaults and missing values

For an allowlisted scalar absent from `crs:`, the importer uses a valid matching `crd:` camera default when available, otherwise its configured Lightroom default. Unlisted defaults are zero; some controls are intentionally nonzero, such as Sharpening 40 and Color Noise Reduction 25. These are labelled assumed neutral. The registry is an implementation assumption, not a certification of every Adobe camera-default configuration.

Temperature and Tint have no neutral fallback. If absent, the metadata reader can query as-shot white balance from the matching RAW file. Apple's Kelvin/tint interpretation can differ from Lightroom's As Shot values. This metadata query is not a rendered RAW preview or final development pipeline.

If both keyframe samples are As Shot, the writer leaves intermediate white balance untouched. Otherwise planned Temperature/Tint changes use `WhiteBalance="Custom"`.

### Precision and preservation

Exposure is formatted to two decimals, sharpening radius to one, and other registered numeric fields to whole numbers. Changed-value comparisons use this precision to avoid unnecessary writes. Integer quantization can produce visible parameter steps even when the underlying curve is smooth.

Only allowlisted scalar settings are changed. Existing non-target metadata is preserved semantically and verified where the writer supports it; XML formatting need not remain byte-for-byte identical after serialization. Structured tone curves, masks, AI edits, crop, transforms, lens settings, and process-version fields are not interpolated.

**Camera-profile preservation is a special case, not profile animation.** An existing `crs:CameraProfile` is left unchanged. If it is missing and a `crd:CameraProfile` camera default exists, the writer can copy that default into the existing intermediate packet to avoid changing the effective profile when settings become explicit. It does not interpolate profiles, and this behavior still needs Adobe read-back verification.

## Supported Development Fields

The current source registry contains **83 experimental numeric Camera Raw mappings**, all enabled for explicitly confirmed writes, plus categorical white-balance mode handling. Earlier development records described a 96-field candidate list; that is not the current registry count.

The authoritative list is [XMPFieldRegistry.swift](LapseCurveModules/Sources/LapseCurveMetadata/XMPFieldRegistry.swift).

| Group | Numeric fields | Included controls |
| --- | ---: | --- |
| Basic tone | 6 | Exposure2012, Contrast2012, Highlights2012, Shadows2012, Whites2012, Blacks2012 |
| White balance | 2 | Temperature, Tint |
| Color and presence | 5 | Vibrance, Saturation, Texture, Clarity2012, Dehaze |
| Parametric curve | 7 | Shadows, Darks, Lights, Highlights, and the three Parametric split positions |
| Detail | 10 | Sharpness, sharpening radius/detail/masking; luminance and color noise-reduction controls |
| HSL | 24 | Hue, saturation, and luminance adjustments for eight color channels |
| Split Toning / Color Grading | 14 | Split Toning hue/saturation/balance; midtone, luminance, global and blending controls |
| Chromatic aberration / Defringe | 7 | AutoLateralCA; purple/green amount and low/high hue boundaries |
| Grain / Glow | 2 | GrainAmount, Glow |
| Calibration | 6 | Red, green, and blue hue/saturation |

Field inclusion does not establish valid ranges, Adobe-version compatibility, or correct rendering. Only a subset appeared in the supplied Lightroom fixture. Do not infer support for additional similarly named fields, grain controls, lens profiles, geometric corrections, or structured tone-curve points.

## Projects, Recovery, and File Safety

### Project documents

The project is a versioned JSON `.lapsecurve` document, not a Core Data/SwiftData database. It stores frame/keyframe identities and ordering, paths/bookmarks, imported metadata baselines/fingerprints, project settings, interval curve choices, and document timestamps. Media and preview caches remain external.

Current schema version is **2**. Version-1 documents migrate to version 2 with no segment overrides. Unsupported future schemas are rejected; older app versions cannot be assumed to open a version-2 save. Legacy manual override records are retained for document compatibility but ignored by the app's calculation, inspector, and sidecar execution.

Treat project files as potentially sensitive: they can contain paths, bookmark data, and imported metadata. Sanitizing the one bundled test fixture does not sanitize your projects.

### Save and recovery

Project saves validate data, stage a same-directory temporary file, and use atomic replacement. When replacing a valid document, the repository keeps the previous document in a sibling `.recovery` snapshot. Corrupt or unsupported existing project files are not silently overwritten.

A project recovery snapshot is **not an XMP backup and does not undo sidecar writes**. There is no dedicated recovery-browser UI. For manual recovery, preserve both files first, copy the desired snapshot to a separate filename ending in `.lapsecurve`, and open that copy. If its saved metadata is older than the on-disk sidecars, explicitly reload and review before attempting another write.

### Relinking and reload

Relinking restores source access while preserving the project's frames, keyframes, and imported metadata. Use the expected folder layout and relative filenames. It is not an import or merge of a different shoot.

Reload Metadata imports current source metadata explicitly. Curve choices survive for endpoint pairs that remain adjacent. Changed keyframe intervals lose obsolete choices with a notice; incompatible edit history is cleared. If source access or bookmarks fail, reselect the intended folder rather than discarding the project.

### Write guarantees and limits

- Normal scans and metadata inspection are read-only.
- Keyframe photo bytes and keyframe sidecars are never update targets.
- Original RAW bytes and `.ACR` auxiliary files are not modified.
- Missing XMP sidecars are skipped, never created or copied from an anchor.
- Writes preserve each intermediate frame's own packet rather than cloning a keyframe packet.
- Staged and committed values are verified; successful commits refresh their baselines.
- Cancellation is cooperative between/before commits. Updated files remain updated; cancelled/failed files are reported separately.
- External changes cause stale-input rejection when detected. An independent app can still write in the final filesystem race window or overwrite the results later.
- No per-sidecar backup, mirrored-output folder, transaction-wide rollback, or Undo for committed XMP edits exists.

Take an external backup, close other metadata writers, and verify the result in Lightroom. Passing local tests is not a replacement for those precautions.

## Exporting Images from Lightroom

Only proceed after Lightroom has read the updated sidecars and you have checked representative rendered frames.

1. Select the intended full output range, including keyframes and intermediate photos, in chronological order. Do not export only the one-star images.
2. Choose one consistent crop/aspect ratio, orientation, output size, and export recipe. LapseCurve does not interpolate crop or resize images.
3. Export to a new folder outside the scanned source folder.
4. Use unique, zero-padded, contiguous filenames, for example `frame_000001.jpg`, `frame_000002.jpg`, and so on. Match your actual Lightroom naming template to the video command's pattern.
5. Verify the first, middle, and last image, the total file count, and continuity across keyframe boundaries.

Suggested starting points, not universal delivery standards:

| Goal | Still export | Notes |
| --- | --- | --- |
| Quick review / straightforward SDR | High-quality JPEG, consistent sRGB export, final or modestly oversized dimensions | Smaller files; usually 8-bit. Avoid repeated JPEG export/recompression. |
| More grading latitude | 16-bit TIFF with an explicit, consistently interpreted color profile | Larger files; verify that the chosen editor and import settings preserve the intended bit depth/profile. |
| Pan/zoom/reframing | Images larger than the delivery resolution | Extra resolution provides cropping room, not extra temporal frames. |

For a 3840 x 2160 delivery, a 3:2 photo needs a crop or letterboxing decision. Do not stretch it to 16:9 accidentally. Avoid output sharpening or other export settings that change unpredictably between frames.

The rendered pixels already contain the Lightroom grade. A video editor importing the resulting JPEG/TIFF sequence does not need, and should not be expected, to apply Camera Raw XMP instructions again.

## Making a Video

These are external workflow suggestions, not integrations, bundled dependencies, or certification claims. Application menus, image-sequence support, codecs, and licensing vary by version and platform. The recipes assume already-rendered images, not RAW/XMP pairs.

### Frame rate, duration, and order

Choose the sequence interpretation rate before editing. Common choices are 24, 25, or 30 fps; use exact rational rates such as `24000/1001` or `30000/1001` when the delivery requires them. Do not silently substitute 24 for 23.976.

With $N$ exported images at $f$ frames per second, video duration is $T=N/f$. For a regular capture interval $\Delta t$, the approximate time-compression factor is $S=\Delta t f$. For example, 600 images captured about five seconds apart cover about 50 minutes and play for 25 seconds at 24 fps.

Sequence order matters more than file modification times. Keep numbering contiguous and padded; a numeric reader may stop at the first gap. A wildcard reader may include unrelated images or use lexicographic order, where unpadded `frame_10` sorts before `frame_2`.

Match the timeline and delivery rate to the sequence interpretation unless you deliberately want retiming. Frame blending or optical flow can invent intermediate imagery; neither is necessary to place each original photo on one video frame.

### FFmpeg

Install FFmpeg separately from a source you trust. On a Mac already using Homebrew, `brew install ffmpeg` is one option; LapseCurve does not require Homebrew. Check available encoders with `ffmpeg -encoders`; a build without `libx264` or `prores_ks` needs a suitable alternative/build.

The following examples run from the parent of a rendered-image folder named `rendered`, whose first file is `frame_000001.jpg`. Adapt the path, extension, digit count, and start number to your files. Quoting the input pattern prevents shell expansion. `-n` refuses to overwrite an existing output.

**H.264 review file at source resolution, 24 fps:**

```sh
ffmpeg -n -framerate 24 -start_number 1 -i 'rendered/frame_%06d.jpg' \
	-vf 'scale=trunc(iw/2)*2:trunc(ih/2)*2:out_range=tv,setsar=1' \
	-c:v libx264 -preset slow -crf 18 -pix_fmt yuv420p \
	-color_range tv -an -movflags +faststart 'timelapse-review.mp4'
```

`-framerate` is an input option and belongs before `-i`. The scale expression makes dimensions even for broadly compatible 4:2:0 encoding, potentially reducing an odd dimension by one pixel. `out_range=tv` converts to limited video range and `-color_range tv` labels that range consistently; pixel format alone does not establish full versus limited range. `setsar=1` requests square pixels. CRF 18 is a quality-oriented starting point, not lossless encoding. Very large source-resolution H.264 files may not play on all devices.

**ProRes 422 HQ editing master, 24 fps:**

```sh
ffmpeg -n -framerate 24 -start_number 1 -i 'rendered/frame_%06d.jpg' \
	-vf 'scale=trunc(iw/2)*2:trunc(ih/2)*2:out_range=tv,setsar=1' \
	-c:v prores_ks -profile:v 3 -pix_fmt yuv422p10le \
	-color_range tv -an 'timelapse-master.mov'
```

This is a larger, edit-friendly intermediate. Encoding an 8-bit JPEG into a 10-bit ProRes file does not restore missing bit depth or RAW information. For a 16-bit TIFF sequence, change the input extension/pattern and verify the resulting color pipeline rather than assuming the container preserves everything.

**3840 x 2160 H.264 with aspect-preserving letterboxing:**

```sh
ffmpeg -n -framerate 24 -start_number 1 -i 'rendered/frame_%06d.jpg' \
	-vf 'scale=3840:2160:force_original_aspect_ratio=decrease:force_divisible_by=2:out_range=tv,pad=3840:2160:(ow-iw)/2:(oh-ih)/2,setsar=1' \
	-c:v libx264 -preset slow -crf 18 -pix_fmt yuv420p \
	-color_range tv -an -movflags +faststart 'timelapse-4k.mp4'
```

This fits the complete image within the output and pads the remaining area; it does not crop to fill. It may upscale a small source. If you prefer a full-frame crop, make that creative choice in Lightroom or the editor instead of silently distorting the image.

**Inspect the encoded frame count and rate:**

```sh
ffprobe -v error -count_frames -select_streams v:0 \
	-show_entries stream=codec_name,width,height,pix_fmt,avg_frame_rate,nb_read_frames:format=duration \
	-of json 'timelapse-review.mp4'
```

Confirm the frame count matches the intended export and duration is approximately $N/f$. Watch the movie at normal speed and frame-step across interval boundaries. A successful encoder exit alone does not prove the right files or order were used.

For 25 fps use `-framerate 25`; for 23.976 use `-framerate 24000/1001`. Avoid adding a conflicting output `-r` casually, because changing the output rate can duplicate or drop frames. For non-contiguous filenames, the optional image2 glob mode exists, but verifying and renumbering copies of the rendered exports is usually easier to audit than relying on a broad wildcard.

**Local recipe check, 2026-10-15:** the three encoding commands above were smoke-tested with FFmpeg 9.0.2 and 24 generated JPEG frames. FFprobe verified 24 frames at 24 fps, one-second duration, expected H.264/ProRes codecs and pixel formats, limited video range, and the requested source-even/4K output sizes. This verifies local command execution and basic stream properties, not real-photo color fidelity, every FFmpeg build, or any editor import workflow.

### DaVinci Resolve

1. Create the project and set the intended timeline frame rate and resolution before building the timeline.
2. In Media Storage, use sequence grouping rather than individual-frame display. Depending on the version, the relevant toggle is **Show Individual Frames**; turn it off to recognize a numbered image sequence as a clip.
3. Import the complete, contiguous sequence and verify its frame count/duration.
4. Check the clip frame-rate interpretation, commonly under **Clip Attributes**, before editing. Match it to your intended image-per-frame rate.
5. Assign the appropriate input color interpretation and verify scaling/crop behavior. Do not assume TIFF/JPEG profiles and a video intermediate are handled identically.
6. Edit and export a master or delivery file from the Deliver page, with rate/resolution and codec settings appropriate to the target.

If sequence recognition or performance is troublesome, import the FFmpeg ProRes master instead. Proxy/optimized-media workflows can help with large images. Codec availability, maximum resolutions, and export options depend on Resolve edition, operating system, and version.

### Final Cut Pro

The most predictable route is to create a correctly timed ProRes movie first, then import it as a normal clip.

1. Create the ProRes master with the chosen frame rate using FFmpeg or another sequence assembler.
2. Import that movie into an event and create a project with the intended rate, resolution, and color configuration.
3. Check Spatial Conform/cropping rather than accepting unwanted letterboxing or scaling.
4. Add edits, titles, audio, and any deliberate retiming, then share/export the desired master or delivery format.

Do not assume that importing a folder of JPEGs behaves like Premiere's Image Sequence import. Individual still images have durations, and automatic motion treatments can be inappropriate for a one-photo-per-frame time-lapse. If constructing a timeline from individual stills, explicitly verify one-frame durations, ordering, transitions, and any Ken Burns-style motion; thousands of still clips can be cumbersome. A single preassembled movie avoids that ambiguity.

### Adobe Premiere Pro

1. Keep the rendered images in one folder with contiguous sequence numbers.
2. Use **File > Import**, select the first image, and enable **Image Sequence** in the import options. Do not import the same files as a collection of independent multi-second stills.
3. Verify the imported clip's interpreted frame rate, using the relevant **Modify > Interpret Footage** controls when necessary.
4. Create or configure a matching sequence, then check scaling and color interpretation.
5. Edit normally and export a delivery file with a deliberate frame rate and codec choice.

For heavy sequences, a ProRes intermediate or a proxy workflow can improve responsiveness. When a frame is missing, sequence import can stop or split; compare duration and frame count against the rendered folder.

### Other useful options

| Tool | Suggested use | Caution |
| --- | --- | --- |
| After Effects | Import a numbered still sequence, interpret its frame rate, and place it in a matching composition. Useful for compositing or controlled reframing. | Keep interpretation and composition rates deliberate; avoid unnecessary resampling. |
| Blender Video Sequencer | Add the ordered images as an image-sequence strip, set scene resolution/rate, then render a movie. | Verify sequence order, strip length, color management, and output encoding. |
| Shutter Encoder or another FFmpeg GUI | Assemble numbered stills using the version's image-sequence controls, or transcode a prepared master. | Confirm sequence timing rather than accepting slideshow durations. |
| iMovie or a simple movie editor | Import a preassembled H.264/ProRes clip and add a soundtrack or titles. | Importing independent stills may add long durations, transitions, or automatic motion. |

None of these tools is an alternative reader for Lightroom development XMP in this workflow. Feed them the rendered images or an already assembled movie.

### Color, quality, and delivery checklist

- Use one consistent image export color profile and bit depth across the sequence.
- These FFmpeg recipes illustrate sequence timing and codecs; they are not complete ICC-managed, broadcast, or HDR color-conversion presets.
- sRGB stills and Rec.709 video have related primaries but are not interchangeable transfer-function instructions. Configure the actual conversion/interpretation deliberately in a color-managed workflow.
- Merely adding color tags does not convert pixels. Do not correct a wrong transform by blindly retagging a file.
- `yuv420p` is an 8-bit delivery-oriented format, not an HDR preservation format.
- Compare reference images and an encoded movie in a consistent managed viewing environment. Player gamma/range differences can resemble grading errors.
- Keep an editing master and the original rendered sequence; make small delivery files from the master rather than repeatedly recompressing previews.
- If adding audio, use material you have rights to use and verify synchronization/end duration. The silent examples above intentionally use `-an`.

## Implementation

### Module boundaries

LapseCurve is an Xcode SwiftUI app backed by the local [LapseCurveModules/Package.swift](LapseCurveModules/Package.swift) package. It has no third-party Swift package dependencies.

| Module | Responsibility |
| --- | --- |
| `LapseCurveDomain` | Sendable/Codable identifiers, frames, keyframes, parameters, settings, diagnostics, schema and validation. |
| `LapseCurveSequence` | Discovery, ordering, rating authority, sidecar association, stable frame identity and scan diagnostics. |
| `LapseCurveMetadata` | ImageIO/capture metadata, bounded namespace-aware XMP reading/writing and the current allowlist/defaults. |
| `LapseCurveEngine` | Pure deterministic interpolation and validation; no UI or filesystem dependency. Legacy override APIs remain for compatibility. |
| `LapseCurveExport` | Existing-sidecar snapshots, immutable plans, eligibility, staged/atomic updates, progress, results and committed baselines. |
| `LapseCurvePersistence` | Project codec, migrations, validation, atomic saves and recovery snapshots. |
| `LapseCurvePreview` | Source-preview extraction, explicit companion handling, bounded cache and stale-source checks. |
| `LapseCurveAnalysis` | Retained legacy compensation library and tests. Not linked or invoked by the current app. |

The app links the seven active package products. Important Apple frameworks include SwiftUI, Charts, Observation, Foundation, AppKit, ImageIO, Core Graphics, and the RAW metadata facilities used for as-shot white balance. Native Charts does not add a third-party dependency.

### Editor state and concurrency

[AppModel.swift](LapseCurve/AppModel.swift) is the MainActor UI coordinator. Storage, scanning, and preview boundaries are injectable through existing protocols, while observable editor state remains on the main actor.

[EditorSnapshot.swift](LapseCurve/EditorSnapshot.swift) groups frame indexes, ordered keyframes, interval membership, changed-parameter sets, counts, calculated values, and graph models into one immutable Sendable result. An `EditorComputation` actor constructs these snapshots and parses preflight data away from MainActor. The interval builder advances through sorted frames rather than filtering the entire sequence again for every UI read.

Snapshot publication checks the current calculation/session identity. Superseded calculation and preflight tasks are cancelled or ignored. Opening a new project invalidates older source operations; preview requests have request/session guards. Save completion compares its session, request, project identity, and saved snapshot before clearing the dirty flag, so newer edits are not misreported as saved.

### XMP update pipeline

1. Import existing sidecar bytes and their fingerprint into the project baseline.
2. Calculate parameter samples from imported keyframe anchors and interval settings, ignoring legacy manual overrides in the app.
3. Preflight intermediate frames only, checking frame/packet ratings, associations, conflicts, allowlisted fields, finite/range conditions, As Shot policy, and rounded no-op values.
4. Require explicit user approval for the immutable plan.
5. Re-read and compare source bytes, generate the modified packet, validate it, and acquire a LapseCurve lock file for cooperating writers.
6. Recheck the source, stage bytes beside the sidecar, verify them, and atomically replace the existing path.
7. Verify committed bytes/values and return the exact successful metadata document with its fingerprint.
8. Refresh only successful baselines and consume the plan; leave failures/cancellations visible for review.

The XML reader limits packet size to 16 MiB, nesting to 128 levels, and property count to 100,000. DTD/external-entity inputs and malformed/ambiguous packets are rejected. Preservation and source checks are safety mechanisms, not Adobe rendering certification.

### UI ownership

| Source | Role |
| --- | --- |
| [LapseCurveApp.swift](LapseCurve/LapseCurveApp.swift) | App entry, window sizing and opt-in Debug UI fixture. |
| [ContentView.swift](LapseCurve/ContentView.swift) | Workspace composition, file/project actions, keyboard routing, alerts and execution sheet. |
| [EditorToolbarView.swift](LapseCurve/Views/EditorToolbarView.swift) | Toolbar actions and busy/history state. |
| [KeyframeSequenceListView.swift](LapseCurve/Views/KeyframeSequenceListView.swift) | Key-photo rows, interval controls, graph placement and out-of-range notice. |
| [IntervalParameterGraphsView.swift](LapseCurve/Views/IntervalParameterGraphsView.swift) | Native charts, endpoint markers, hover overlays and accessible graph descriptions. |
| [MetadataInspectorView.swift](LapseCurve/Views/MetadataInspectorView.swift) | Frame/development inspection and interpolation-only green highlighting. |
| [SegmentParameterGraphModel.swift](LapseCurve/SegmentParameterGraphModel.swift) | Projection of actual samples, finite plot domains, missing-data runs, formatting and nearest-sample lookup. |

Related export plan/result value types are grouped in their owning files, and the small interpolation algorithms share one strategies file. The parser, writer, planner/coordinator, persistence boundaries, and substantial views remain separate rather than being merged solely to reduce file count.

## Building and Testing

### Select the toolchain

From the repository root, with the recorded Xcode installation available:

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild -version
swift --version
```

Adjust the path if Xcode is installed elsewhere. Setting `DEVELOPER_DIR` for the shell avoids changing the system-wide developer-directory selection and avoids accidentally building with Command Line Tools alone.

### Build and run tests

```sh
swift test --package-path LapseCurveModules
xcodebuild -project LapseCurve.xcodeproj -scheme LapseCurve \
	-destination 'platform=macOS' build
xcodebuild test -project LapseCurve.xcodeproj -scheme LapseCurve \
	-destination 'platform=macOS'
```

For a focused hosted or native UI run:

```sh
xcodebuild test -project LapseCurve.xcodeproj -scheme LapseCurve \
	-destination 'platform=macOS' -only-testing:LapseCurveTests
xcodebuild test -project LapseCurve.xcodeproj -scheme LapseCurve \
	-destination 'platform=macOS' \
	-only-testing:LapseCurveUITests/LapseCurveUITests/testSegmentCurvePickerEditsAndUndoes
```

Use the fully qualified target/class/method for an individual XCTest UI method; an incorrect filter can select zero tests. Confirm that tests actually ran, not only that the command exited successfully.

An optimized local build is:

```sh
xcodebuild -project LapseCurve.xcodeproj -scheme LapseCurve \
	-configuration Release -destination 'platform=macOS' build
```

Signing requires an appropriate local Xcode configuration/certificate. A local Apple Development signature is not Developer ID distribution or notarization.

### Test coverage and fixtures

Package tests exercise domain validation, ordering/rating resolution, parser limits, metadata preservation, interpolation, preview/cache behavior, atomic project saves/recovery, and sidecar updates. Hosted tests cover editor snapshots, graphs, curve/history state, repeated writes, save/open completion order, sparse indexes, and overlapping calculations. Native UI tests cover startup, correction-control removal, graph hover/history, repeated execution results, chooser cancellation, and launch performance.

The most recent recorded application verification passed **19 Xcode tests: 13 hosted and 6 native UI**, with no failures or skips; the package suite and local Release build also passed. These are recorded implementation results, not camera/Adobe/video-editor compatibility certifications. Remaining evidence gaps are summarized in [Limitations and References](#limitations-and-references).

The Debug-only `-ui-testing` flag suppresses the startup picker. Combined with `-ui-testing-sequence`, it builds a synthetic nine-photo JPEG/XMP sequence in the app's own temporary directory. This isolated fixture creation is not a normal source-file operation and is excluded from Release builds. Feature tests do not depend on clipboard manipulation or native chooser path typing; chooser cancellation is tested independently.

Run native UI automation in an unlocked interactive desktop session and avoid interacting with the app during the run. macOS accessibility, permission dialogs, an unresponsive existing instance, or display changes can prevent automation even when model tests pass.

## Troubleshooting

| Symptom | What to check |
| --- | --- |
| No photos / unexpectedly many photos | Choose the correct top-level folder; the UI scan is nonrecursive. Keep derivatives and alternate RAW/JPEG copies outside it. Check recognized extensions. |
| No or too few key photos | Save ratings to metadata and use exactly one star. Inspect rating source and malformed/conflicting XMP diagnostics. Two through five stars are not keyframes. |
| Unexpected ordering | Check EXIF/time provenance, filesystem fallback warnings, filename numbering, and timestamps changed by copying/export. |
| No graph for a field | It may be unchanged at stored precision, unavailable at an endpoint, both As Shot, or in an interval without intermediate frames. |
| A value is not green | Green identifies changed interval parameters, not every recognized setting. Unsupported/unavailable/constant fields remain neutral. |
| Green field but no write | Keyframes are immutable; the intermediate sidecar may be missing/conflicted or the rounded value already matches. Inspect preflight. |
| Zero files ready | There may be no eligible intervals, no existing sidecars, only no-op values, or metadata conflicts. After a successful run, an unchanged rerun is normally a no-op. |
| Write says source changed / failed | Inspect the per-file message. Another program may have changed XMP since import. Resolve the external change, save deliberately in Lightroom, close it, reload, and review before retrying. Do not bypass the check. |
| A second curve write fails | Current builds refresh successful baselines automatically. Confirm you are running the rebuilt app; distinguish an actual external edit or permission issue from an old baseline bug. |
| Metadata appears outdated | Save from Lightroom and use Reload Metadata explicitly. There is no automatic catalog/folder synchronization. |
| Lightroom appears unchanged after execution | Use Read Metadata from File before saving back. Check that the expected existing sidecars and supported fields were updated, then verify Adobe recognition. |
| Missing RAW thumbnail | The source may not contain a usable embedded preview. LapseCurve does not render RAW pixels as a fallback. Companion JPEG association is not a general current UI feature. |
| Project source unavailable | Relink the expected folder and grant access. Keep filenames/relative paths consistent; relinking an unrelated shoot is not a new import. |
| Project save fails | Check parent existence, permissions, disk space, and corrupt/future-schema protection. Preserve the original and recovery files before manual recovery. |
| Movie too long / slideshow-like | Import as an image sequence, not independent stills with multi-second durations; verify interpretation rate and frame count. |
| Movie stops early | Look for missing sequence numbers, a mismatched pattern/start number, or an incomplete Lightroom export. |
| Movie colors differ | Check export profiles, editor input interpretation, transforms, video range/transfer settings, and the player. Do not assume retagging is conversion. |
| Native UI tests fail before reaching a control | Check the interactive session, accessibility/permission dialogs, app responsiveness, and test filter. Do not treat a zero-test run as verification. |

## Limitations and References

Current limitations include uncertified camera/Adobe combinations and field ranges, no native RAW development or corrected-image preview, no image/video rendering, no in-app grade/rating edits, no manual exposure/capture-compensation layer, no mirrored XMP export or backup mode, and no full timeline/range-selection/curve-point editing interface. Large real shoots, signed-app bookmark/permission failures, physical disk exhaustion, and comprehensive accessibility/keyboard use still need representative manual validation.

The developer tests and release build do not remove the need to verify real camera files and Lightroom read-back. Normal operation never generates a missing sidecar, and no local test result authorizes overwriting source images or keyframe metadata.

Further reading:

- [FFmpeg image2 documentation](https://ffmpeg.org/ffmpeg-formats.html#image2): numbered sequence, start-number, and frame-rate semantics.
- [FFmpeg codec documentation](https://ffmpeg.org/ffmpeg-codecs.html): available H.264/ProRes encoder options.
- [Adobe Premiere image-sequence import](https://helpx.adobe.com/premiere/desktop/organize-media/import-files/import-images-as-image-sequence.html).
- [DaVinci Resolve training and manuals](https://www.blackmagicdesign.com/products/davinciresolve/training).
- [Final Cut Pro user guide](https://support.apple.com/guide/final-cut-pro/welcome/mac).
- [Blender video editing manual](https://docs.blender.org/manual/en/latest/video_editing/).