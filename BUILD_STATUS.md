# Zwift Ride Controller → MyWhoosh Bridge — Build Status

**Date:** 2026-10-15  
**Repo:** `/Users/dmw/git/sport/zwift-ride-controller` (fork of `OpenBikeControl/bikecontrol`)  
**Branch:** `main` @ `addf76d` + custom patches  
**Target:** iPhone (Znift Ride BLE) + iPad (MyWhoosh app) → MyWhoosh Link over local network  

---

## What was built

### Phase 0 — Toolchain + fork

- Installed via Homebrew: **Flutter 3.47.4** (stable), **CocoaPods 1.17.0**, `gh` (not used — pure git from now on)
- Xcode 26.6 at `/Applications/Xcode.app` (system default switched via `xcode-select`)
- Cloned upstream `OpenBikeControl/bikecontrol` `main` @ `addf76d` into this repo
- Fork origin: `git@github.com:abaebae/bikecontrol.git` (already set by you before this session)
- Reconfigured signing for **free Apple ID** (manual → automatic, cleared upstream team `UZRHKPVWN9`)
- Bundle IDs renamed to `de.dominicwein.bikecontrol` (+ `.TrainerActivity`, `.RunnerTests`)
- RevenueCat 5.54.1 was incompatible with Xcode 26 Swift → vendored `purchases_flutter` 9.16.1 + `purchases_ui_flutter` 9.16.1 under `vendor/` with `purchases-hybrid-common` bumped to **18.20.1** → RevenueCat **5.80.2** (fixes ambiguous `init(stringRepresentation:)`); wired via `dependency_overrides` in `pubspec.yaml`
- iOS 26.5 Simulator platform SDK installed via `xcodebuild -downloadPlatform iOS`

### Phase 1 — Baseline build (public tree was broken)

Upstream `main` is currently **non-compilable** (issue #281, "Missing prop package" — the public `prop_public/` submodule is missing 5 required files). Fixed by writing stubs against the repo's pinned test contracts:

| File | Content |
|---|---|
| `prop_public/lib/mdns/mdns_responder.dart` | `MdnsQueryLogEntry` class (query log entry with identity-based folding) |
| `prop_public/lib/emulators/definitions/sensor_definition.dart` | `SensorDefinition` (HR/CSC/CPS service exposure + metric setters) |
| `prop_public/lib/utils/csc_measurement.dart` | `CscMeasurement` parse/build, `cscCadenceRpm`, `advanceCrankCounter` |
| `prop_public/lib/utils/cps_measurement.dart` | `CpsMeasurement` parse/build, `cpsCadenceRpm`, `buildCyclingPowerMeasurement` |
| `prop_public/lib/utils/serialized_lifecycle.dart` | `SerializedLifecycle` (serialises async start/stop) |

Also extended ~8 existing stubs with ~40 missing members: `DirconEmulator` (incl. `kWahooDirconStandardPort`, `hasNothingToServe`, setter override hooks, owner support), `FitnessBikeDefinition` (incl. `TrainerControlProtocol`, `ZwiftGearEchoVerdict`, `ControlWriteResult`, exposure getters/setters, `effectiveVirtualShiftingMode`, `defaultVirtualShiftingMode`), `ClickLogic` (keep-awake state + `ClickKeepAwakeStatus`), `Logger.trace`, `ServiceAdvertiser`/`NsdServiceAdvertiser`, `ResilientTcpServer` (real impl below), `BridgeUsageTracker`, `BikeControlMdnsMarkers`.

Result: `flutter analyze` lib/ errors **→ 0**; `flutter build ios --debug --no-codesign` **✓ builds**; stub-contract tests **pass**.

### Fork patches on top of `main`

1. **Pro unlock — `IAPManager.unlockAllPro = true`**
   - `lib/utils/iap/iap_manager.dart`: single static `unlockAllPro` short-circuits `hasActiveSubscription`, `isProEnabled`, `isProEnabledForCurrentDevice`, `isProButDeviceUnregistered`, `isProEnabledForCurrentDeviceOrDidPurchaseOld`, `getStatusMessage()` (→ empty), `canExecuteCommand`
   - `getStatusMessage()` returns `''` — no "Pro"/trial badge in the title bar
   - Trial card on home self-hides (already returns null for Pro)
   - `lib/utils/iap/revenuecat_service.dart`: `initialize()` early-returns when `unlockAllPro` (notifiers set to true), so `Purchases.configure` never runs and no native assertion can fire
   - `IAPManager.isUsingRevenueCat` returns `!unlockAllPro && _revenueCatService != null` — routes diagnostics screen away from the SDK
   - Four remaining `Purchases.appUserID` call sites in `lib/widgets/iap_status_widget.dart` patched to `"unlocked-build"` placeholder under `unlockAllPro`

2. **RevenueCat crash fix (from "setup crashes")**
   - Root cause: with no RevenueCat API key compiled in, `Purchases.configure` never ran, but setup screens still called `Purchases.appUserID` → native SDK asserted → `EXC_BREAKPOINT` in `appUserID.getter` (confirmed via device crash log `Runner-2026-10-14-112438.ips`)
   - With `unlockAllPro` the service never configures the SDK, so the assertion path is dead; plus `isUsingRevenueCat = false` keeps the diagnostics screen from touching it

3. **MyWhoosh Link — real TCP server (the main functional fix)**
   - `prop_public/lib/utils/resilient_tcp_server.dart` was a no-op stub (`start() async {}`) — MyWhoosh Link port 21587 was never opened
   - Replaced with a real `dart:io` `ServerSocket` implementation:
     - `start()` binds to port 21587 (fixed-port contract: `portAttempts: 1`, iOS may pick actual port if 21587 taken) and listens for incoming TCP
     - `onClientConnected`, `onData`, `onClientDisconnected` callbacks fire for real
     - `isRunning`, `hasClient`, `client`, `boundPort` report real state
     - `stop()` closes the server; `dropClient()` drops the current client
     - `expectProbe()`/`acceptProbe()` test seams kept for the network self-test (with corrected types)
   - `lib/bluetooth/devices/mywhoosh/link.dart` → `WhooshLink.startServer()` uses this and now actually opens port 21587

4. **Network self-test — real advertised-address picker (the "No Wi-Fi" / invisible-advertisement fix)**
   - `prop_public/lib/utils/network_address.dart` was a stub that returned the *first* non-loopback IPv4 with score 0
   - On iOS the interface enumeration yields the cellular (`pdp_ip0`) and `ipsec0` (192.0.0.x) addresses before Wi-Fi `en0`, so the app advertised a non-LAN address: the self-test's *Advertised address* row reported "no Wi-Fi" and *Advertisement visible on the network* failed (the dns_sd host record and service are pinned to the interface holding that address, so a Wi-Fi-only browser never saw them)
   - Reimplemented `AdvertisedAddressPicker.report()` with real scoring:
     - Wi-Fi/Ethernet ports (`en*`, `eth*`, `wl*`, Windows `Wi-Fi`/`Ethernet`/`WLAN`) score high
     - cellular, VPN tunnels and bridges/container NICs (`utun`, `tun`, `tap`, `bridge`, `docker`, `vmnet`, …) are demoted and flagged `isVirtual`
     - `169.254/16` and `192.0.0/24` never win; CGNAT (`100.64/10`) is demoted; RFC 1918 gets a small bonus
     - ties prefer a real port, then the first enumerated
   - `ipsec`/vendor `vgate` NICs stay non-virtual (a real VPN rides on them; the VPN row reports it, not the two-networks warning)
   - Regression test: `test/services/network_self_test/advertised_address_picker_test.dart`

5. **iOS mDNS backend — publish through the dns_sd bridge by default**
   - `prop_public/lib/mdns/service_advertiser.dart`: `ServiceAdvertiser.platformDefault()` returned the OS-responder stub whose `register()` throws `UnimplementedError`; on iOS it now returns the real `DnsSdServiceAdvertiser`
   - `prop_public/lib/mdns/dnssd_service_advertiser.dart`: the dns_sd MethodChannel bridge (register host A record + service, conflict fallback label, host cleanup on failure) over `ios/Runner/DnsSdAdvertiser.swift`

6. **MyWhoosh Link — dual-stack TCP server**
   - `prop_public/lib/utils/resilient_tcp_server.dart` reimplemented on `dart:io`'s `ServerSocket`: dual-stack bind (`anyIPv6`, `v6Only: false`), port fallback, owner supersede, IPv4-mapped probe normalization, client-gone handling
   - `lib/utils/core.dart`: no longer silently disables MyWhoosh Link when OBP mDNS is enabled — separate ports, so they coexist

### Signing + device

- Team ID `5695M74Z7G` set project-wide (from your Apple ID: `Apple Development: dowein@gmail.com (7593WBLX82)`)
- `flutter build ios --release` produces signed `build/ios/iphoneos/Runner.app`
- `xcrun devicectl device install app --device 00008130-000A741E3C02001C build/ios/iphoneos/Runner.app` deploys to iPhone DIP15
- On-device: trust Apple Development profile in **Settings → General → VPN & Device Management** if first launch

#### Free Apple ID → the profile expires every 7 days (re-push cadence)

The signing is a **free Apple ID personal team**, so the embedded provisioning
profile is short-lived. The installed app:

```
iOS Team Provisioning Profile: de.dominicwein.bikecontrol
ExpirationDate: 2026-10-21T09:18:58Z   ← 7 days after the 2026-10-15 build
get-task-allow: true                    ← a development build
```

When the profile expires iOS refuses to launch the app ("Unable to verify
app"). Nothing is lost — a fresh **rebuild + reinstall** clears it:

```sh
flutter build ios --release
xcrun devicectl device install app --device 00008130-000A741E3C02001C build/ios/iphoneos/Runner.app
```

- **Re-push at least every 7 days** (by **2026-10-21** for the current build).
  Once a year if the paid Apple Developer Program ($99/yr) is enrolled.
- Installing over the same bundle ID **keeps settings**; deleting the app wipes them.
- Xcode's Run button re-signs and refreshes the profile automatically each run.
- Check the current expiry on the phone: **Settings → General → VPN & Device
  Management** → tap the profile.

Other dev-build limits: no TestFlight/App Store distribution; free team allows
only 3 devices and ~10 App IDs per 7 days; keep **Developer Mode** on and the
**Local Network** permission granted; `devicectl` over Wi-Fi can drop, so prefer
the USB cable for installs.

### Verified so far

- **Zwift Ride BLE pairing works** — controller detected, buttons decoded
- **MyWhoosh Link server opens port 21587** — previously failed with "unimplemented" (the stub); now actually listens
- **Network self-test is green on iPhone** (build 2026-10-15): advertised address is the Wi-Fi `en0` address, *Advertised address* and *Advertisement visible on the network* both pass; the trainer app connects over the network method (verified on device)

---

## Known limitations / gaps (not blocking for our use case)

- `prop` private submodule not cloned (`git@github.com:OpenBikeControl/prop.git` requires SSH access we don't have) — `prop_public/` stubs are sufficient for compilation; the full implementation (MDNS responder, sensor GATT dispatch, etc.) is in `prop` and not needed for Zwift Ride → MyWhoosh Link
- Full test suite (~50 failures/hangs) in stubbed non-essential features (virtual-shifting physics, Erg mode, trainer actions, RevenueCat paywall tests, etc.) — those don't affect the Zwift Ride → MyWhoosh Link path
- `accessibility/` codegen input (`pigeon`) and `media_key_detector/test` are broken stubs — not in the app build
- iPad must stay foregrounded for the bridge (BLE + Link sockets suspended in background) → topology: **iPhone does BLE + Link foreground**, **MyWhoosh runs on iPad** — iPhone must not lock during the ride
- RevenueCat still initialises at startup (offline-safe, no-op when `unlockAllPro`) — can be stubbed out entirely later if you want faster launch
- Shorebird `shorebird.yaml` in repo root is leftover config (not used here)

---

## Next steps (not yet done)

1. **Verify MyWhoosh Link end-to-end**: launch app on iPhone, enable MyWhoosh Link, from MyWhoosh on iPad connect to `<iPhone-IP>:21587`, send a gear-up/down and confirm it reaches MyWhoosh
2. **Gear layout + remapping** (Phase 3 scope): `lib/models/shifting_config.dart`, `lib/services/shifting_configs_controller.dart`, `lib/pages/proxy_device_details/front_shift_card.dart`, `shifting_config_picker.dart`, `lib/pages/proxy_device_details/virtual_shifting_pro_notice.dart` — configuration surface for gear count/ratio presets and button/gesture remapping
3. **macOS target** (on roadmap, not yet built): same-machine MyWhoosh + bridge on a Mac (MyWhoosh has no native ARM build today — runs via Rosetta on M-series); would enable the same-machine scenario and fall back to Accessibility input injection path
4. Optionally strip RevenueCat + Supabase entirely for a faster, network-free launch if desired

---

## Files touched (summary)

- `ios/Runner.xcodeproj/project.pbxproj` — signing config (team, bundle IDs, automatic signing)
- `ios/Runner/Runner.entitlements`, `ios/TrainerActivityExtension.entitlements` — stripped paid-only entitlements
- `pubspec.yaml` — `dependency_overrides` for vendored RevenueCat plugins
- `vendor/` — vendored `purchases_flutter` + `purchases_ui_flutter` with bumped hybrid-common
- `lib/utils/iap/iap_manager.dart` — `unlockAllPro`, isUsingRevenueCat
- `lib/utils/iap/revenuecat_service.dart` — early return when unlocked, added missing import
- `lib/widgets/iap_status_widget.dart` — `Purchases.appUserID` guarded under `unlockAllPro`
- `prop_public/lib/utils/resilient_tcp_server.dart` — **real** dual-stack TCP server (MyWhoosh Link)
- `prop_public/lib/utils/network_address.dart` — **real** advertised-address picker (LAN scoring; the "No Wi-Fi" fix)
- `prop_public/lib/mdns/dnssd_service_advertiser.dart` — iOS dns_sd bridge advertiser
- `prop_public/lib/mdns/service_advertiser.dart` — `platformDefault()` returns DnsSd on iOS, `hostLabel` on the responder
- `lib/utils/core.dart` — OBP mDNS and MyWhoosh Link coexist (no silent disable)
- `test/services/network_self_test/advertised_address_picker_test.dart` — picker regression test
- `prop_public/lib/mdns/mdns_responder.dart` — `MdnsQueryLogEntry` stub
- `prop_public/lib/emulators/definitions/sensor_definition.dart` — `SensorDefinition` stub
- `prop_public/lib/utils/csc_measurement.dart` — CSC parse/build stubs
- `prop_public/lib/utils/cps_measurement.dart` — CPS parse/build stubs
- `prop_public/lib/utils/serialized_lifecycle.dart` — `SerializedLifecycle` stub
- `prop_public/lib/emulators/definitions/fitness_bike_definition.dart` — extended with control-protocol enum/types/metrics
- `prop_public/lib/emulators/dircon_emulator.dart` — extended with port constant, override hooks, `hasNothingToServe`, owner support
- `prop_public/lib/mdns/service_advertiser.dart` — `advertisedAddress`, `untrackedAddress`, `NsdServiceAdvertiser`
- `prop_public/lib/utils/shared.dart` — `Logger.trace`
- `prop_public/lib/devices/click_logic.dart` — keep-awake state
- `prop_public/lib/services/bridge_usage_tracker.dart` — `remainingToday`
- `prop_public/lib/utils/constants.dart` — `tacxProductId`
