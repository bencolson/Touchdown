# Touchdown — working notes

Context for anyone (human or agent) picking this up. `README.md` is the user-facing doc; this file is the state of play and the reasoning that is expensive to rediscover.

## What this is

A macOS driver that makes taps on a Corsair Xeneon Edge (14.5", 2560×720) land where you touch. Fork of [ymlaine/TouchscreenDriver](https://github.com/ymlaine/TouchscreenDriver).

The hardware exposes two USB HID interfaces:

| Usage page / usage | Meaning | What macOS does |
|---|---|---|
| `0x0D` / `0x04` | Digitizer, Touch Screen | **Ignored** — macOS has no HID digitizer support |
| `0x01` / `0x02` | Generic Desktop, Mouse | Used, but read as *relative* deltas |

So out of the box a tap clicks wherever the cursor already sits. The driver seizes the digitizer interface exclusively, maps its coordinates to absolute screen space, and injects `CGEvent` clicks.

Controller is `wch.cn` VID `0x27c0` / PID `0x0859`.

## Machine roles

- **Client** — where the panel is plugged in and the driver runs. Needs only `./install.sh`.
- **Build machine** — holds the Developer ID certificate and the Sparkle signing key, and is the only machine that cuts releases. Run `./setup-release-machine.sh` there to audit readiness.

Keep the signing keys on the build machine only. Nothing needs to be exported to a client.

## Outstanding work

### 1. Grant permissions on the client (blocks everything)

The driver is installed and running but has never been granted anything, so no touch input is mapped yet. It sits in `Waiting for Accessibility permission`, polling every 2s.

- Grant **Accessibility** and **Input Monitoring** to `Touchdown.app` in System Settings → Privacy & Security.
- If stale `TouchscreenDriver` dialogs appear, they are ghosts from an earlier install of a bundle that no longer exists. Dismissing them with **Deny** is safe and drains the queue; `pkill universalAccessAuthWarn` clears the backlog at once. Do not click "Open System Settings" on those — it leads to a list where that app does not appear.

### 2. Verify and calibrate touch mapping

Never yet tested with real touch input, because of (1). Once granted:

- Confirm taps land under the finger across the full 2560×720 width.
- If they are offset or scaled, run `./run_analyzer.sh`, touch each corner, and update `touchscreenMaxX` / `touchscreenMaxY` in `TouchscreenDriver.swift`. Current values (`16383` / `9599`) are inherited from upstream and unverified on this unit.

### 3. Finish the build machine

- **Developer ID Application certificate** — Xcode → Settings → Accounts → Manage Certificates → **+**. A *newly issued* cert is correct; see "Signing" below for why nothing needs exporting.
- **Sparkle signing key** — `./vendor/sparkle/bin/generate_keys --account touchdown`. Must be run from a GUI session: it refuses over SSH because the data-protection keychain needs GUI context.
- **Update `PUBLIC_ED_KEY`** in `version.sh` to whatever that prints, and commit. Then reinstall on every client so the new public key is embedded.
- **Notarization** — `xcrun notarytool store-credentials touchdown-notary --team-id 99L757HY7N …` with an app-specific password.
- The **first** `sign_update` against a new key blocks on a Keychain authorization dialog. Cut the first release from a GUI session and answer **Always Allow**.

### 4. Cut the first release

Nothing is published yet: zero releases, zero `<item>` entries in `appcast.xml`. The pipeline is verified end to end via `./release.sh --dry-run`, but never against a live tag.

```bash
NOTARY_PROFILE=touchdown-notary ./release.sh "First release."
```

**The window that closes here:** adopting a different Sparkle key is free only while nothing is published. Once a release exists, the key is embedded in installed copies and must be migrated rather than regenerated — there is no recovery path.

## Established facts, so they are not re-derived

### TCC and signing

macOS keys Accessibility and Input Monitoring differently depending on signature type:

| Signing | TCC keys on | Consequence |
|---|---|---|
| None (bare Mach-O) | nothing — **no TCC record at all** | Never appears in the permission list; permission can never be granted |
| Ad-hoc | `cdhash` | Every rebuild revokes both permissions |
| Developer ID | bundle ID + team ID | Grants survive rebuilds and updates |

This is why the app is a bundle and why it is Developer ID signed. Both were bugs in the original: a bare binary in `/usr/local/bin` could not be granted Accessibility at all (`tccutil reset` reported *"No such bundle identifier"* — there was no record to toggle), and ad-hoc signing would have made every Sparkle update silently break the driver.

Verify the requirement contains no hash:

```bash
codesign -d --requirements - ~/Applications/Touchdown.app
# designated => identifier "com.bencolson.touchdown" and anchor apple generic
#   and certificate leaf[subject.OU] = "99L757HY7N"
```

Because it pins `subject.OU` — the **team** — and not a certificate, any Developer ID Application cert from the same team satisfies it. Issue a fresh one on a new build machine rather than exporting a private key.

### Notarization is mandatory, not cosmetic

Sparkle downloads updates over the network, so macOS quarantines them, and Gatekeeper rejects unnotarized Developer ID apps. An unnotarized update installs and then refuses to launch. `release.sh` therefore refuses to publish without `NOTARY_PROFILE`; `ALLOW_UNNOTARIZED=1` exists only for local testing.

### Archive with `ditto`, never `zip`

`zip` mangles a signed bundle's symlink farm and the signature stops validating. Verified by extracting a `ditto` archive and re-checking: *"valid on disk"*, *"satisfies its Designated Requirement"*.

### Never call `exit()` on a recoverable failure

The LaunchAgent uses `KeepAlive { SuccessfulExit = false }`, so any non-zero exit is relaunched. The original called `AXIsProcessTrustedWithOptions(prompt: true)` then `exit(1)`, producing an unbounded loop of stacked system dialogs — 14 before it was stopped. Missing permission, a refused HID open, and an absent device now all report state and stay resident. A clean `exit(0)` is the only correct exit, and is what the single-instance guard and the Quit menu item use.

### Single instance matters

Sparkle relaunches the app itself after installing while launchd may also start one. Two instances would both attempt an exclusive HID seize and fight over the device, so the newer one exits.

### Sparkle key is account-scoped

`SPARKLE_KEY_ACCOUNT="touchdown"` in `version.sh` keeps this key distinct from other Sparkle keys that may exist on the build machine. Sparkle's own advice is that one key can serve all your apps, which holds only when they are equally trusted — this repo and its release pipeline are public, so a shared key would let a leak here forge updates for a private app. `--account` also means generating this key cannot clobber an existing one.

### Releases are cut locally, not in CI

`.github/workflows/build.yml` verifies compilation, bundle layout, ad-hoc signing and `@rpath` linkage. It deliberately does not release: that needs both private keys, and putting them in GitHub secrets would place the signing identity for all future updates on a shared runner. Ad-hoc builds skip `--options runtime` and `--timestamp`, which `codesign` rejects for ad-hoc signatures.

## Known rough edges

- **Display selection is by elimination.** The panel reports its name as `Type-C`, not `XENEON`, so the name match in `setupScreen()` fails and it falls through to "the display that is not the main one". Correct for a two-display setup where the panel is secondary; wrong if the panel becomes the main display or a third is attached.
- **Comments are still French.** Upstream is French throughout; user-facing strings were translated but ~109 comment lines were not, to keep the diff against upstream reviewable. Translating them is mechanical if desired.
- **Swift 6 language mode is not enabled.** `swiftc` defaults to Swift 5 mode, which is why the mutable globals mutated from the C HID callback compile without concurrency errors. Do not add `-swift-version 6` expecting a no-op.
- **`touchscreenMaxX/Y` are unverified** on this hardware — inherited from upstream.
- **Upstream attribution is intentional.** `README.md` credits the original author and notes the project's AI co-authorship. That describes upstream's work, not this fork's, and should not be stripped.
