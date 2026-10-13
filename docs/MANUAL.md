# SA-Sur : Note to Frequency

## User manual

Applies to SA-Sur 1.0 and later. Issue 1, 13 October 2026.

---

## 1. About SA-Sur

SA-Sur is a single-window app that shows the frequency of a note and plays it as a sine tone.

It covers every note of a twelve-tone equal temperament scale, from C0 to B8.

SA-Sur is free of charge. **Hafod Mastering Ltd** and **Sudeep Audio.com LLP** publish it together, for macOS and Windows.

About the name: *SA* is the first note of the Indian scale, and also the abbreviation of Sudeep Audio. *Sur* is note, or pitch.

## 2. Install SA-Sur

### macOS - the download version

Requirements: macOS 13.0 or later, Apple Silicon or Intel.

1. Download `SA-Sur-1.0-notarized.zip` from the Releases page.
2. Double-click the zip file. macOS unpacks the folder.
3. Move `SA-Sur.app` to the Applications folder.
4. Open SA-Sur.

The app is signed and notarized by Apple. macOS shows the usual confirmation for a downloaded app, and no other message.

### macOS - the App Store version

1. Open the App Store.
2. Search for `SA-Sur`.
3. Click *Get*, then click *Install*.

The App Store copy is the same app, sandboxed for the store. Its version number is its own number, because App Review releases it on its own schedule.

### Windows

Requirements: Windows 10 or later, 64-bit.

1. Download `SA-Sur.exe` from the Releases page.
2. Run the file.

There is no installer, and no .NET runtime to add.

The Windows file is not signed yet. Windows therefore shows *"Windows protected your PC"* and the publisher **Unknown publisher** on the first run. Do this:

1. Click *More info*.
2. Click *Run anyway*.

## 3. The window

All the controls are in one window. The window keeps its size.

**Figure 1** - the parts of the SA-Sur window.

| # | Item | Where | What it does |
|---|---|---|---|
| 1 | Note buttons | top row | Select the note: `C C# D Eb E F F# G G# A Bb B` |
| 2 | Octave buttons | second row | Select the octave: `0` to `8` |
| 3 | Readout | below the octave row, large digits | Shows the frequency in hertz |
| 4 | Copy icon | right of the readout | Copies the frequency |
| 5 | Company marks | right of the octave row | Open the Hafod Mastering website or the Sudeep Audio website |
| 6 | Play / Stop | bottom left | Starts and stops the tone |
| 7 | Level slider | next to the Play button | Sets the output level |
| 8 | Concert A | bottom right, first group | Sets the concert-A reference: `440`, `432`, `415`, `442` |
| 9 | Decimals | bottom right, after Concert A | Sets the number of decimal places: 0 to 6 |
| 10 | Appearance | bottom right, last icon | Selects the System, Light or Dark appearance |

SA-Sur opens in the state A4, octave 4, 440 Hz and 2 decimal places. The readout is therefore 440.00 Hz.

SA-Sur quits when you close the window.

## 4. Procedures

### Select a note

1. Find the note in the top row.
2. Click the note.

SA-Sur shows the frequency of the note. If a tone is playing, SA-Sur retunes the tone at once.

### Select an octave

1. Find the octave in the second row.
2. Click the octave.

SA-Sur shows the new frequency. If a tone is playing, SA-Sur retunes the tone at once.

### Play and stop the tone

1. Use the Play button, or press the **Space bar**.
2. Use the same control again to stop the tone.

The button shows `Stop` while the tone plays.

### Set the level

- Move the slider next to the Play button.

The slider opens at 50%. The output level is limited to 11% of full scale, so a full slider is not loud. Section 6 gives the details.

### Set the concert-A reference

1. Click `440`, `432`, `415` or `442` in the Concert A group.
2. Look at the readout.

SA-Sur changes the readout and the tone. If a tone is playing, SA-Sur retunes the tone at once. `440` Hz is the usual reference. `432`, `415` and `442` Hz are other references in common use.

### Set the number of decimal places

1. Click the up arrow or the down arrow of the Decimals stepper.
2. Look at the readout.

The range is 0 to 6 decimal places. At 6 decimal places, A4 shows 440.000000.

### Copy the frequency

1. Click the copy icon.
2. Paste the value into another application.

SA-Sur puts the number on the clipboard, without the unit Hz. The icon shows a check mark for about one second.

### Change the appearance

1. Click the appearance icon at the bottom right.
2. Click it again to see the next appearance.

The icon goes through System, Light and Dark. SA-Sur keeps your choice for the next time that you open the app.

## 5. Frequency values

SA-Sur calculates each frequency from the concert-A reference. The frequency doubles at each octave, and there are twelve equal steps between two octaves.

| Note | Frequency |
|---|---|
| C0 | 16.35 Hz |
| A3 | 220.00 Hz |
| A4 | 440.00 Hz |
| A5 | 880.00 Hz |
| B8 | 7902.13 Hz |

The lowest note is C0 at 16.35 Hz. The highest note is B8 at 7902.13 Hz.

### Rounding, and printed charts that disagree

Some printed charts give F#2 as 93 Hz and G0 as 25 Hz. The correct values are 92.4986 Hz and 24.4997 Hz. To two decimal places these values are 92.50 Hz and 24.50 Hz, and to whole numbers they are 92 Hz and 24 Hz.

A chart that rounds an intermediate value first shows a value one digit high. SA-Sur calculates the frequency directly from the reference, so its readout is correct where such a chart is not.

## 6. The tone

SA-Sur plays a sine tone. A sine tone has one frequency and no harmonics.

The level goes up and down over 12 ms. Therefore, you hear no clicks when the tone starts, when the tone stops, or when the pitch changes.

The level follows the slider. The maximum level is 11% of full scale.

> **WARNING:** Do not use a high level with headphones. A sine tone at a high frequency is more tiring to the ear than music at the same level. Set the level low first, then increase it if necessary.

SA-Sur sends the tone to the default output device of the computer. To use a different device, change the output device in the sound settings of the computer:

- **macOS:** System Settings > Sound.
- **Windows:** Settings > System > Sound.

SA-Sur follows the new device and continues to play.

SA-Sur keeps the audio engine ready after the first time that you play the tone. The next start is therefore immediate. SA-Sur releases the audio device when you close the window.

## 7. If you have a problem

### There is no sound

1. Increase the level with the slider.
2. Make sure that the computer uses the correct output device, and that its volume is not zero.
3. Press the Space bar to stop the tone. Press it again to start the tone.

### macOS will not open a build that you made yourself

A build from the source code is not notarized. macOS therefore stops the first start. Do this:

1. Try to open SA-Sur.
2. Dismiss the message.
3. Open System Settings.
4. Go to Privacy & Security.
5. Click *Open Anyway* for SA-Sur, then confirm.

For advanced users: in Terminal, run this command.

```sh
xattr -dr com.apple.quarantine /Applications/SA-Sur.app
```

The command removes the quarantine flag from the app. No administrator password is necessary.

### Windows warns about an unknown publisher

The Windows file is not signed yet. Section 2 gives the two steps.

### The App Store version will not open

Reinstall the app from the App Store. This corrects most install problems.

### There is a security problem

Read `SECURITY.md` in the repository.

## 8. Privacy

SA-Sur makes no network connections. It collects no data and it sends no data. There is no analytics, no telemetry, no advertising and no third-party framework.

SA-Sur stores one setting on the computer: the appearance choice (System, Light or Dark).

The window shows the marks of the two companies. A click on a mark asks your browser to open that company's website. That visit is a usual visit to a website, and the privacy terms of that website apply.

The full policy is in `docs/PRIVACY.md` in the repository.

## 9. Licence and marks

SA-Sur is released under the **Apache License 2.0**. You can use it, change it and redistribute it, also inside a product whose source is closed. Keep the licence notices, and state the significant changes that you make.

There is no paid edition and no support contract.

The names, the logos and the marks of Hafod Mastering and Sudeep Audio, and the **SA-Sur** name and app artwork, are not part of the code licence (Apache-2.0, section 6). Forks are welcome. Replace those marks, or remove them, from a build that you publish.

## 10. Help and links

- Source code and documentation: https://github.com/hafodmastering/sa-sur
- Privacy policy: https://github.com/hafodmastering/sa-sur/blob/main/docs/PRIVACY.md
- Hafod Mastering: https://hafodmastering.co.uk
- Sudeep Audio: https://sudeepaudio.com

### Support

Neither company supplies product support for SA-Sur. Neither company reviews changes or collects feature requests. The app is published free of charge, as it is.

The source code is open and short. Give it to an AI assistant that you already use, and ask for the change that you want. That is the fastest route to the app that you need.

---

## Appendix A - note frequencies at A4 = 440 Hz

Values are given to four decimal places. For another concert-A reference, multiply the value by the reference divided by 440. Example: at 432 Hz, A4 is 432.0000 Hz.

<!-- APPENDIX-TABLE: note-table.csv columns=3 decimals=4 -->

---

SA-Sur : Note to Frequency - User manual, issue 1, 13 October 2026.
