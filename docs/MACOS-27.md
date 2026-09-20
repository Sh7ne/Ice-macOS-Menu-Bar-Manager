# macOS 27 Preview

This branch adds an experimental, opt-in backend for macOS 27. The legacy
window/divider backend remains in use on macOS 14 through 26.

## Behavior and limitations

- Enable **Experimental app hiding** in Settings > Menu Bar Layout after
  accepting the warning. Disabling it immediately restores the system bar.
- Visibility is per application, not per individual icon. Assign apps to
  Visible, Hidden, or Always-Hidden in the layout settings.
- Preview 2 separates Apps and System Items. Time Machine and other legacy
  SystemUIServer extras share one visibility setting, identified by their
  live Accessibility titles when available. Battery, Bluetooth, Displays,
  Input Menu, Sound, Wi-Fi, and Screen Mirroring use the system allowlist.
  Clock, Control Center, and unknown controls remain system-managed rather
  than being silently omitted or offered nonfunctional hiding controls.
- Clicking Ice toggles Hidden; Option-click toggles Always-Hidden when enabled.
  Existing section hotkeys and automatic rehide settings remain available.
- On first use, apps left of Ice's main-display icon are assigned to Hidden
  if an old divider position was saved. Always-Hidden assignments cannot be
  reliably recovered; review the new layout. Old preferences are not erased.
- macOS temporarily conceals some additional system extras, including the
  audio/video controls, and blocks the clock's Notification Center action
  while hiding is active. Starting with preview 3, Ice observes a plain date
  click, briefly releases its own hiding assertion, presses the verified clock
  Accessibility element, then restores the current hiding policy. Icons can
  briefly appear during this workaround. Modified clicks, drags, long presses,
  other menu items, and clicks while already expanded are left untouched.
  Reveal all sections, disable experimental hiding, or quit Ice if the private
  API changes or another menu bar manager keeps an assertion active.
- Applications with unregistered/bundleless helpers or running from transient
  build directories may not obey the allowlist. Use installed applications.
- Ice Bar, icon search, divider dragging, spacing, hover/empty-area/scroll
  reveal, and automatic app-menu hiding are unavailable with this backend.
  Their saved preferences remain intact for macOS 26.
- Unknown future private API changes fail open rather than falling back to
  oversized divider windows. Changing displays, fullscreen behavior, and
  earlier macOS versions still need broader runtime regression testing.

The implementation dynamically loads MenuBarClientCore, uses Accessibility
to enumerate MenuBarAgent, and does not write MenuBarAgent's preferences,
restart system services, or relocate other apps' icons. Assertions are
invalidated on reveal and normal termination, and are process-bound. Idle
operation uses workspace notifications rather than a periodic AX polling loop.

## Verification

```sh
bash Scripts/test-native-menu-bar-policy.sh
./Scripts/smoke-test-xpc.sh
TMPDIR=/private/tmp bash Scripts/smoke-test-native-menu-bar.sh
```

The last command is a **live**, Accessibility-authorized macOS 27 test. It
creates a temporary status app, hides/reveals it three times, checks that other
registered apps and allowlisted system controls remain, and verifies restoration
of every baseline item. The private API's system side effects apply during the
brief conceal phases. Do not run during a call, recording, or presentation.
This test covers hiding, not the date-click relay. The date-click relay also
needs manual testing: with icons hidden, click the date, confirm Notification
Center opens and icons rehide, dismiss it, and repeat. Verify that ordinary
app clicks, modified clicks and expanded-state date clicks retain native behavior.
The policy test covers menu-band geometry on displays with different origins,
movement tolerance and long presses. The relay uses no idle polling, active
event tap, synthesized mouse input, screenshot capture or additional permission.

Quit Ice and other menu bar managers before live tests: concurrent assessment
assertions can interfere with the allowlist. To test an already-present system
item rather than launching the temporary fixture:

```sh
ICE_NATIVE_SMOKE_TARGET=com.apple.systemuiserver TMPDIR=/private/tmp ./Scripts/smoke-test-native-menu-bar.sh
ICE_NATIVE_SMOKE_TARGET=system:com.apple.menuextra.sound TMPDIR=/private/tmp ./Scripts/smoke-test-native-menu-bar.sh
```

Preview 2 also restores top content padding beneath the macOS 27 title bar,
removes the empty sidebar toolbar group, resets scroll position between panes,
keeps the sidebar scrollable, and uses a compact About layout. The permission
window no longer cancels the system's safe-area insets on macOS 27.

## References and licensing

The private API selectors and AX tree discovery were informed by
[Pelmet](https://github.com/fif7y/pelmet), revision
`095cc56e` (GPL-3.0), specifically `MBAssessmentShim.m`, `ItemEnumerator.swift`,
and `MenuBarPolicy.swift`. The scoped Ice integration is maintained in this
repository under the existing GPL-3.0 license. See Pelmet's
[FAQ](https://github.com/fif7y/pelmet/blob/main/docs/FAQ.md) for assessment-mode
limitations. CompactSlider remains an external MIT-licensed dependency and is
pinned to 2.1.0 for Xcode 27 compatibility.

The clock workaround was informed by Pelmet's `ClockClickRelay.swift` and
`AppState.clockClicked`, revision `899e00a92596f32505347298766218683fdc62a3`
(GPL-3.0). Ice uses a passive mouse monitor and an Accessibility action after
the physical mouse-up rather than swallowing or replaying mouse events.
