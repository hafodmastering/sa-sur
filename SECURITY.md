# Security policy

## What this is

SA-Sur converts note names to frequencies in twelve-tone equal temperament and
can audition the result as a sine tone. It runs on macOS and Windows. It has no
network code, no updater, no telemetry, no accounts, and writes nothing outside
its own preferences. It opens only its own bundled resources and the system
audio output device.

## Reporting something

Email **security@hafodmastering.co.uk** with the version, the OS version, and
what you observed. Please do not open a public issue for anything exploitable
until we have replied.

Be aware of what you are getting: this software is offered as-is, with no
warranty and no commitment to fix anything (see `LICENSE`, sections 7 and 8).
There is no bug bounty, no SLA, and no support. A report will be read and, if it
is real and we agree it matters, acted on when we can. That is the whole promise.

## Scope

In scope: anything that lets this app do more than convert notes and play a tone
— memory-safety faults in the DSP or rendering path, a bundle or resource that
can be replaced to execute code, a notarization or signature weakness.

Out of scope: the Gatekeeper prompt on an unnotarized build, the SmartScreen
prompt on an unsigned one, audio-quality opinions, feature requests, and
anything requiring an already-compromised machine.

## Publication

If a fix ships, it will appear in the release notes of the version that carries
it, credited to the reporter unless asked otherwise.
