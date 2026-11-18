# Maintaining the fork

How That's What She Synced sits on top of Vorssaint, so upstream updates stay easy to take.

## How it's organised

**The fork's own files** hold nearly all of its behaviour, so upstream never edits them:

- `Services/Notch/NotchOffice*.swift`, `UI/Notch/NotchOffice*.swift`: the Office moments, the mug toggle and the shared moment components.
- `Services/Notch/NotchDanceSupport.swift`, `UI/Notch/NotchDance*.swift`, `UI/Notch/NotchDancersView.swift`: the dancers.
- `Services/Notch/NotchMascotCast.swift`, `NotchMascotShuffleService.swift`, `UI/Notch/NotchMascotCastParts.swift`: the cast.
- `Services/Notch/NotchIslandGlow.swift`, `UI/Notch/NotchGlowBackdrop.swift`, `NotchWingGlowView.swift`, `NotchMusicAurora.swift`, `NotchSongStyle.swift`, `Services/Notch/NotchArtworkPalette.swift`: colour, glow and motion.
- `Services/Notch/NotchAgentWings.swift`, `NotchAgentFinishes.swift`, `UI/Notch/NotchAgentComet*.swift`: the agents' wings.
- `UI/Settings/NotchOfficeEditionCard.swift`: the Settings group.

**Hooks** are the small edits in Vorssaint's own files that call into the fork. `Tools/check-upstream.sh` lists them, most changed first. The busiest are `NotchService`, `NotchNoticeView`, `NotchCapsuleViews`, `NotchMascotView` and `NotchAgentStrip`.

## Rules for new work

1. Put new behaviour in a fork file. Upstream files get a call, not the logic.
2. Gate every hook on `NotchOfficeEdition`, so with Office edition off the island is plain Vorssaint.
3. Use the shared pieces (`NotchPunchIn`, `NotchLowerThird`, `NotchMomentPaint`, `NotchSongMotion`) so moments stay one family.
4. Nothing runs while the island is hidden, still or in Low Power Mode. Slow motion runs at 30 fps or less.
5. A beat sets one move going per hit, never one per reading: the hit at 60 fps, its fall at 30 (`NotchBeatCurve`, `NotchSongMotion.play`). Each move starts from where the last one stands, worked out, not read from a presentation layer.

## Taking an upstream update

```bash
Tools/check-upstream.sh                  # new commits, conflicts, hooks
git merge origin/main                    # or your Vorssaint remote
./build.sh && ./build.sh --test          # 0 warnings, TESTS OK
Tools/bench-notch.sh --rounds 2          # the island's cost, Office edition on vs off
./build.sh --dev && ./build/VorssaintDeveloper --music-path-probe   # the beat's cost, no music needed
```

## Next, maybe

A theme system: casts and moments defined as data, so others can add their own characters without touching the core. `NotchMascotCast` is the natural seam.
