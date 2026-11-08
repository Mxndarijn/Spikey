# Audio licences

Every file in this folder was made for Flapjaw. Nothing here comes from a third party.

| Files | Made with | Licence |
| --- | --- | --- |
| `sfx/*.ogg` (19 sounds) | `src/spikey_synth.py`, rendered to WAV, then `ffmpeg -c:a libvorbis -q:a 5` | owned by the project, no credit needed |
| `music/<track>/<track>_{pad,bass,drums,lead}.ogg` (5 tracks) | `src/spikey_synth.py`, then `ffmpeg -c:a libvorbis -q:a 4` | owned by the project, no credit needed |
| `src/spikey_synth.py` | written for this project, Python standard library only | project code |

Re-render: `python -I assets/audio/src/spikey_synth.py <out_dir>` (deterministic, same
output every time), then convert the WAVs to OGG with the ffmpeg settings above.

Not allowed here: the user's reference pack `Flapping_Cage_sounds` (unknown licence).
Any future third-party sound must be CC0 (or a licence we have checked) and be listed
in this file with its source URL and author.

See `docs/AUDIO.md` for which sound plays on which event.
