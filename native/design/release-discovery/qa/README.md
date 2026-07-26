# Release discovery visual QA

Captured on the iPhone 17 Pro, iOS 26.5 simulator from
`testReleaseOptInIsExplicitAndOfflineDeepLinkFocusesTheAuthoredWorldPlace` and
`testFocusedFutureReleaseOffersOneWorkingWorldNodeAction`.
Each capture is `1206 × 2622` pixels.

| Artifact | SHA-256 |
|---|---|
| `release-world-focus-v1.png` | `44d15386621cbc82925f9fd27baabb75544fc7b38b335f7c9320ab2386c9784b` |
| `release-notification-settings-v1.png` | `31f3db0f9d8e6752297e7fb9cdbbf0423b3df36722b08ad39e697713461072cd` |
| `world-focus-comparison-v1.png` | `832e99024450ef822e7a6a3a4965b9ef192aac7be56575320ead564e7516d580` |
| `release-world-download-v1.png` | `dc055e47d7b957dc7129f7c5bf53ffbc3b7f31d3cde83f0a7549f1a8be0ff005` |
| `release-world-download-comparison-v1.png` | `0ffe81818e2eb982371c78483bd2c4c42892500346cd7dc41f65c43ffe6bdf19` |

The comparison places `native/design/download-surface/reference/current-world-before.png`
on the left and the focused release state on the right. The release keeps the
existing road geometry and chapter spacing. Its double ring marks the exact
world node; the title and year sit at the opposite lower edge without covering
the road or a node. The marker does not imply that the package is installed.

`release-world-download-comparison-v1.png` places that focus state on the left
and the explicit pre-install action on the right. The action keeps the world
geometry unchanged, places one 44-point target below the title and year, and
uses the established square-edged gold control instead of adding a card or a
second route. Its paired UI test taps the control and requires the state to
become `Preparing`; it is not a visual-only fixture.

The settings capture verifies that notification enrolment remains one explicit
action in the existing sheet. No separate banner, launch prompt or blocking
onboarding surface was added.

These captures validate the shell integration only. The current living-world
canvas remains a development shell, not a finished 2.5D shipping scene.
