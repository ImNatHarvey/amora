# The device run

One sitting, phone in hand. Everything the app has built since 12 August has
been seen only by widget tests; this is the pass that clears it.

**Three of the bugs this project has shipped were invisible to every widget test
and obvious in the first ten seconds on the phone.** Budget an hour and do it in
one go — the value is in seeing the screens next to each other.

On this page: connect · build and install · the checklist · what I expect to
break.

---

## 1. Connect the phone

Samsung Galaxy S25 Ultra (SM-S938B), Android 16 / API 36, over **wireless
debugging** — the USB cable is charge-only. Stable id:
`adb-R5CY224851B-4mLefi._adb-tls-connect._tcp` (use the mDNS form; the
IP-and-port form changes on reboot).

**The emulator is abandoned** — unstable across several sessions. Do not suggest
it. Full rationale and the flagship-flatters-us caveat: `00-architecture.md` §3.

### The ladder, after a reboot

Samsung turns **Wireless debugging off on every reboot**, so this is a recurring
chore, not a fault. Work down the list; stop as soon as `flutter devices` sees
the phone.

1. **Phone:** Settings → Developer options → **Wireless debugging → ON**.
2. **Same Wi-Fi, and not a guest network.** Client isolation (common on guest
   SSIDs and some mesh setups) blocks both mDNS and the direct connection, and
   looks exactly like the phone being off.
3. **Try the saved name first:**
   `adb connect adb-R5CY224851B-4mLefi._adb-tls-connect._tcp`
4. **If that prints `cannot resolve host` — re-pair from scratch.** The name only
   resolves while the phone is advertising it over mDNS, and the pairing is
   dropped by a factory-level toggle or an OS update.
   - Phone: Wireless debugging → **Pair device with pairing code**. It shows an
     `IP:PORT` *and* a six-digit code. This port is **not** the same as the one
     on the main Wireless debugging screen.
   - `adb pair <ip>:<pairing-port>` — paste the code when prompted.
   - `adb connect <ip>:<connect-port>` — the port from the **main** screen.
5. **If mDNS is the specific problem** (pairing works, the name never resolves):
   - `adb mdns check` reports whether the discovery backend is running at all.
   - `adb mdns services` lists what it can currently see.
   - `adb kill-server && adb start-server`, then retry step 3.
   - Still dead: **use the `IP:PORT` form and move on.** It works identically;
     it just changes on reboot, which is the only reason the mDNS name is
     preferred. Do not spend a session fixing mDNS.
6. **"more than one device"** — two connections to the same phone.
   `adb devices` then `adb disconnect <the stale one>`.
7. Confirm with `flutter devices`, then `flutter run`.

If the phone appears in `adb devices` as `unauthorized`, the trust prompt is
waiting on the phone screen — unlock it and accept.

---

## 2. Build and install

Everything runs from `apps/mobile/`, never the repo root.

```bash
cd apps/mobile
flutter run                        # hot reload while you work
```

Or install a standalone APK you can keep on the phone:

```bash
cd apps/mobile
flutter build apk --debug --target-platform android-arm64
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

**Pass `--target-platform android-arm64`.** Without it the APK carries every
architecture: 227 MB against 161 MB, for no benefit on one known phone.

It should appear on the home screen as **Amora** with a pink monogram icon, and
open with **no debug banner**.

---

## 3. The checklist

**Do the whole thing twice: once in light, once in dark. Then once more at 1.3×
font scale** (Settings → Display → Font size, one notch above default). That is
where this app breaks.

The data is 15 generated demo places across 11 barangays — see
`supabase/seed/DEMO-DATA.md`. Prices and hours are invented, so judge the
*layout and behaviour*, never the facts.

### Start

- [ ] **Splash** — mascot fades and rises, under 500 ms, never blocks startup.
- [ ] **Sign in** — logo above "Welcome back". Submit with a wrong password: the
      button shows a spinner, then an error message appears in place.
- [ ] **Sign up** → **profile setup** → **resource picker**. Finishing with
      nothing selected must be allowed.

### Plan

- [ ] **Intake** (`/`) — starter chips render unnumbered. Tap "Tonight, under
      ₱200"; constraint chips appear and are editable.
- [ ] ⚠️ **The intake app bar has three actions** — two icons plus "Use the
      form". **This is the crowding risk.** At 1.3× it is the most likely thing
      on this list to overflow.
- [ ] **Budget sheet** — tap the amount, keypad opens, type a custom value. It
      must read **"For the whole date, not each."**
- [ ] **Ideas** — works on activities alone. Try ₱0.
- [ ] **Plan request** ("Use the form") — "Build a plan" and "Generate with AI"
      side by side, one tap apart on identical input.
- [ ] Run **₱0 from Poblacion**: expect 2 stops, total ₱0, every leg a walk.
- [ ] Run **₱400 from Poblacion**: expect 3 stops, ~₱250, all on the food line.
- [ ] Run **anything from Lolomboy, Taal, Tambobong or Wakas**: these are the
      origins that produce **real tricycle fares**. Poblacion produces none, and
      that is correct — every leg there is under the 800 m walk threshold.

### A saved plan

- [ ] **Map above the timeline.** Numbered pins match the timeline numbers
      exactly. Dashed lines for walking, solid for paid transit.
- [ ] **Long-press a pin and move it.** A count and "Reset" appear beneath.
      Panning the map with a finger that starts on a pin must move the *map*,
      not the pin.
- [ ] **Drag-to-reorder** the stops. This is Phase 5's acceptance criterion and
      has never been seen on hardware.
- [ ] The clock, the ✕, and **"Add a stop"**.
- [ ] **Price breakdown** — five lines (fares, materials, food, gifts,
      activities) summing to the total.
- [ ] Edit until the plan goes **over budget**: the warning should *grow in*,
      not snap.

### Finishing

- [ ] **"We did this"** through to a photo and a spend figure.
- [ ] ⚠️ **Record the compressed photo's actual byte size.** This is the one
      fact no test can supply — `image_picker` compresses in native code that
      `flutter test` never runs. It is an open row in the ledger.
- [ ] **Memories**.
- [ ] **Report a closure** on a place.

### The rest

- [ ] **Profile** → **preferences**. Companion type must offer **only
      "Partner"**. Interests are seven categories, not twelve.
- [ ] **Nav bar** — exactly three destinations: Plan · Memories · Profile. No
      "Feed".
- [ ] Switch tabs mid-conversation and come back: **the intake must not reset**.
- [ ] **`/dev/tokens`** — the token gallery.

---

## 4. What I expect to break

Written down in advance so it is caught in one pass rather than three.

**Most likely**

1. **The intake app bar at 1.3×.** Three actions, two of them icons, plus a text
   button. Already flagged before this session. If it breaks, "Use the form"
   keeps its words — it is the extraction fallback.
2. **CARTO map tiles over mobile data.** Nothing in any test has ever fetched a
   tile. Expect the first load to be slow; a grey grid means the tile request
   failed, not that the map is broken.

**Worth watching**

3. **Fares reading as per-person when they are not.** The ₱100 Poblacion→Igulot
   fare is a special trip — charged **once for the vehicle**, not per passenger.
   If any screen puts "each" beside it, that is the §9 confusion this project
   has already fixed once.
4. **Opening hours.** Turo Night Food Park opens at 17:00, La Casa is closed
   Monday and Tuesday, El Manzano is Friday to Sunday only. A midday plan that
   includes any of them means `is_open_at` is wrong.
5. **Budget filtering.** Ligo-Ligo Retreat is ₱750 per person. A ₱200 request
   must never surface it.
6. **The map in dark mode** should switch to dark tiles, not stay a bright slab.

**Should be fine, but new**

7. The **launcher icon** on a round-mask launcher — the monogram is drawn at 72%
   inside the safe zone, but this is the first time it has been on a home screen.
8. The **over-budget warning's** grow-in, and its instant render under reduced
   motion.

---

## Afterwards

**Strike rows in `HANDOFF.md`'s ledger only for what you actually saw.** Add a
row rather than quietly passing a phase. Phase 0 and Phase 2 stay open
regardless — the data is generated, and no amount of device time makes an
invented price a verified one.
