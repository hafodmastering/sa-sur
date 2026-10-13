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
starting or stopping are click-free - measured, with no sample-to-sample step
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
output, so the whole path - source node, channel duplication, mixer, format
conversion - can be measured without making a sound. `tools/audio-smoke/` uses
it: C2 65.40639 / A4 440.00000 / Bb4 466.16376 / B8 7902.13254 Hz, both channels
bit-identical.

## The studio marks

The SA-Sur app mark and the Hafod Mastering mark sit opposite the readout,
anchored bottom-right of the space beside the octave row and the frequency. Both
are self-contained colour artwork - the SA-Sur mark is the app icon's artwork
with its black backdrop removed (composed by `tools/MakeIcon.swift`), the Hafod
mark is the studio's own transparent PNG - not dark or light ink, so a single
PNG is correct in both appearances and is never tinted. Recolouring them would
misstate the brands' colours.

They render 44 pt tall, 14 pt apart, right edge on the 20 pt content margin, and
the layout is measured by `tools/MeasureRender.swift` rather than eyeballed. A
72 pt experiment filled the space but read as heavy next to the readout and was
reverted (see the version history in `docs/RELEASE.md`).

`tools/stage-logos.sh` stages the marks under clean resource names and at the
size they are drawn: 44 pt tall means a 2× display wants 88 px, so the staged
files are 176 px for headroom. **If `logoHeight` in `Views.swift` changes,
change the staging size with it.**

The marks are trademarks of the studios and are not covered by the source
licence - see `NOTICE` and the Licence section of the README.

## The icon

`tools/MakeIcon.swift` composes the 1024 px master icon from the artwork in
`logos/SA-Sur app logo.png`. The artwork is Aditya's redraw (6 Oct 2026): a flat
black squircle tile carrying the white Latin **sā** and the gold Devanagari
**स**, supplied with the tile's exterior flat (black on black), so the tile
outline was restored from the silhouette of his red-tile export and scaled onto
this canvas before the file was committed.

The tool takes the silhouette from the artwork's **alpha channel** where the
artwork has one - a black tile on transparency has no brightness difference to
measure - and falls back to the original brightness test (ink = anything
brighter than a pure-black backdrop) for opaque artwork. It then fits the
silhouette to Apple's macOS icon grid: an 824 px body centred in the 1024 px
canvas, its own edge followed row by row rather than a geometric rounded-rect
mask imposed on it. `build.sh` downsamples that master into the `.icns`.

`tools/CleanIcon.swift` (the diffusion cleanup that removed the ring, waveform
bars and credit line from the previous artwork) was retired with that artwork:
the redraw arrives finished, so the build feeds MakeIcon directly.

## Verification approach

Three layers, all runnable without Xcode:

| Command | What it proves |
|---|---|
| `./test.sh` | 110 maths and DSP checks, plus an independent diff of every note in the table |
| `./verify.sh` | `test.sh`, then the live audio graph rendered offline and measured, then the UI rendered offscreen in light and dark |

The UI is rendered to PNG offscreen rather than screenshotted from a window, so
`tools/MeasureRender.swift` can report x/y extents, gaps and centres
deterministically, and `tools/AlphaBounds.swift` can report a bitmap's real ink
bounds against its transparent margin.
