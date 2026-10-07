# Design notes

Why the app is the shape it is. Numbers here were measured, not eyeballed; the
tools that measured them are in `tools/`.

## The frequency

Twelve-tone equal temperament, referenced to a selectable concert A:

$$f = A \times 2^{\frac{n-69}{12}}, \qquad n = 12(\text{octave} + 1) + \text{semitone index}$$

`n` is the MIDI note number, so C4 = 60 and A4 = 69. One line of arithmetic. All
108 frequencies (C0–B8) are checked against an independent `exp`/`ln`
recalculation to better than 1e-6 Hz by `tools/diff_table.py`.

Concert-A options are 415, 432, 440 and 442 Hz. The readout and the auditioned
tone both follow the selection, and the octave buttons retune a sounding tone
immediately.

### Rounding, and published charts that disagree

Some published note-frequency charts print `F#2 = 93` and `G0 = 25`. The true
values are 92.4986 and 24.4997, which round to 92 and 24. A chart built from
1-dp intermediates (92.5, 24.5) rounded half-up lands one digit higher.
`tests/main.swift` records both cases as errata rather than reproducing them, so
the readout is right where such a chart is not.

## The tone

A phase-continuous sine with a 12 ms gain envelope, so changing pitch and
starting or stopping are click-free — measured, with no sample-to-sample step
above the theoretical slope bound for the frequency in question.

Output is capped at **0.11 full scale**, and the slider scales 0…1 within that.
A full-scale sine above ~5 kHz is unpleasant in a studio, and a full slider
deliberately reaches only what once sat at the slider's midpoint. The slider
opens at 50%, i.e. 0.055.

`SineOscillator.swift` is pure DSP with no AVFoundation import, so the oscillator
can be rendered into a plain buffer and measured by tests instead of only by ear.
`ToneGenerator.swift` owns the `AVAudioEngine` graph and exposes play/stop/volume.

The engine is started on the first audition and left running with the oscillator
gain at zero: restarts are instant, and CoreAudio shares the output device so it
does not lock out other apps. It is released when the window closes. Changing
audio device tears down the graph's format assumptions, so the graph is rebuilt
and resumed if a tone was playing.

`measureOffline` renders the live graph in manual rendering mode with no device
output, so the whole path — source node, channel duplication, mixer, format
conversion — can be measured without making a sound. `tools/audio-smoke/` uses
it: C2 65.40639 / A4 440.00000 / Bb4 466.16376 / B8 7902.13254 Hz, both channels
bit-identical.

The Windows port mirrors this deliberately: one `SineOscillator` feeding one
provider, the player left running at zero gain, and raw WASAPI output so the
endpoint's own "audio enhancements" cannot level the tone or fight the slider.

## The marks

Hafod Mastering's mark, the collaboration's red "+", and Sudeep Audio's tile sit
opposite the readout, anchored bottom-right of the space beside the octave row
and the frequency. Hafod's mark is the company's own transparent wordmark;
Sudeep's is its supplied flat tile, rounded at Apple's icon radius by
`tools/MakeMark.swift`. Both are self-contained colour artwork rather than ink,
so a single PNG is correct in both appearances and is never tinted — recolouring
them would misstate the brands' colours.

They render 44 pt tall, 4 pt apart, right edge on the 20 pt content margin, and
the layout is measured by `tools/MeasureRender.swift` rather than eyeballed. A
72 pt experiment filled the space but read as heavy next to the readout and was
reverted.

`tools/stage-logos.sh` stages the marks under clean resource names and at the
size they are drawn: 44 pt tall means a 2× display wants 88 px, so the staged
files are 176 px for headroom. **If `logoHeight` in `Views.swift` changes,
change the staging size with it.**

The names and marks are trademarks of the two companies and are not covered by
the source licence — see `NOTICE` and the Licence section of the README.

## The icon

`tools/MakeIcon.swift` composes the 1024 px master icon from the artwork in
`logos/SA-Sur app logo.png`: a flat black squircle tile carrying the white Latin
**sā** and the gold Devanagari **स**. The tool takes the silhouette from the
artwork's **alpha channel** where the artwork has one — a black tile on
transparency has no brightness difference to measure — and falls back to a
brightness test for opaque artwork. It then fits the silhouette to Apple's macOS
icon grid: an 824 px body centred in the 1024 px canvas, its own edge followed
row by row rather than a geometric rounded-rect mask imposed on it. `build.sh`
downsamples that master into the `.icns`.

## Verification approach

Three layers on macOS, all runnable without Xcode:

| Command | What it proves |
|---|---|
| `./test.sh` | 110 maths and DSP checks, plus an independent diff of every note in the table |
| `./verify.sh` | `test.sh`, then the live audio graph rendered offline and measured, then the UI rendered offscreen in light and dark |

The UI is rendered to PNG offscreen rather than screenshotted from a window, so
`tools/MeasureRender.swift` can report x/y extents, gaps and centres
deterministically, and `tools/AlphaBounds.swift` can report a bitmap's real ink
bounds against its transparent margin.

The Windows build carries the same checks in xUnit — `dotnet test SA-Sur.slnx`,
80 tests — including an offscreen Avalonia render that asserts the same layout
geometry, and `windows/SaSur.Measure`, a loopback instrument that measures the
audio at the device on a machine that has a sound card. Device-dependent tests
stand down where there is no endpoint rather than failing for an environmental
reason.

The rest of `tools/` is load-bearing and wired into a script: `MakeIcon`,
`MakeMark`, `CheckBundle`, `stage-logos`, `notarize`, `diff_table`,
`audio-smoke` and `screenshot`. `MeasureRender` and `AlphaBounds` produced the
geometry claims above and are kept for the next person who needs to re-measure;
`ListWindows.swift` is a leftover and can go.

## Measured geometry — one provenance note

The pinned geometry in this file and in the Windows port — the 730×237 window,
the 690/516 rows, the 26 pt footer, the 54 pt line box, the 44 pt marks — was
measured from `docs/screenshots/ui-snapshot-*.png` under **macOS 26.2, October
2026**.

Re-measuring under a newer macOS yields a 730×235 render instead: the intrinsic
height is OS-metric-sensitive at the 2 pt level, and `verify.sh` renders but does
not compare against the committed images, so the drift is silent by design (a
comparison would fail under every OS change). **730×235 is not a correction to
730×237.** Nothing in the suite can notice this class of drift; only the
provenance above can.

## Shared facts between the two builds

A handful of facts appear in both codebases: the concert-A preset list, the 12 ms
ramp, the 0.11 headroom, the copy tick, the 44 pt / 4 pt mark geometry, the
Sudeep red `#DD3938`. Each copy is owned by, and where it matters pinned
behaviourally on, its own side. The one fact class with real cardinality — the
108 note frequencies — has its own cross-language mechanism: `docs/note-table.csv`,
checked by `tools/diff_table.py` on macOS and `TableTests.cs` on Windows.

**The duplicates stay.** They are single scalars, and a shared source-of-truth
file consumed by both builds would put build-time machinery into a macOS pipeline
whose stated virtue is *no Xcode, no project file, no package manager, no
third-party dependencies*. If the two builds ever unlock together and want
teeth, the cheapest addition is a Windows-side test comparing its constants
against a committed `docs/port-facts.csv`, mirroring how `TableTests.cs` treats
`note-table.csv`.
