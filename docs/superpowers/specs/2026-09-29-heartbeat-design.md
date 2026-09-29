# Heartbeat — macOS menu bar work-check reminder

## Problem

User pengen habit "cek kerjaan tiap N waktu" jadi otomatis, buat orang yang
belum punya habit itu. Aplikasi macOS menu bar yang kasih notif+suara tiap
interval tertentu, biar gak ada follow-up kerjaan yang kelewat.

## Scope

- macOS menu bar app (no dock icon, no window)
- Reminder generic (bukan integrasi ke task tool manapun)
- Opensource, distribusi mandiri (GitHub Releases / web sendiri), bukan Mac
  App Store di awal

## Requirements

### Reminder & mode

- Dua mode: **Normal** dan **Urgent**, toggle manual (segmented control di menu)
- Tiap mode punya interval sendiri, configurable (menit), tanpa preset tetap
- Notif **replace**, bukan numpuk — notif baru gantiin notif lama kalau belum
  di-dismiss

### Active hours

- App cuma aktif fire notif dalam jam kerja configurable (default 08:00–17:00)
- Di luar jam itu: timer skip, icon menu bar nunjukin status "paused"

### Notifikasi

- Isi pesan default preset, user bisa custom teks-nya sendiri
- Suara: pilih dari system sound (macOS built-in) ATAU upload file sendiri
  - Custom sound harus `.aiff/.wav/.caf`, ≤30 detik (constraint native
    `UNNotificationSound`)
  - File non-caf (mis. `.mp3`) di-convert otomatis via `afconvert`
    (macOS built-in, no extra dependency)
- Notif sistem + suara (`UNUserNotificationCenter`), bukan silent

### Startup & lifecycle

- Autostart di login, default ON pas first-launch, bisa di-toggle
  (`SMAppService`)
- Gak ada "stop/pause" — ganti mode Normal/Urgent aja
- Menu ada Quit buat matiin app total

### Menu bar icon

3 state pakai SF Symbol (no custom asset dibutuhin buat fungsi):
- Active/Normal: `waveform.path.ecg`
- Active/Urgent: varian warna beda / filled
- Paused (luar active hours): outline/abu-abu

### Menu layout

```
● Active (Normal)
─────────────────
Mode:  ( Normal ) ( Urgent )
─────────────────
Normal interval:   [30 min ▾]
Urgent interval:   [10 min ▾]
─────────────────
Active hours: [08:00]-[17:00]
─────────────────
Message: [Waktunya cek kerjaanmu! ]
─────────────────
Sound: [System: Glass ▾]
       [Choose custom file…]
─────────────────
Launch at Login        [ ✓ ]
Quit
```

## Architecture

Pure Swift, AppKit + SwiftUI hybrid. `LSUIElement = true` (no dock icon). No
third-party dependency — semua fungsi (timer, notif, autostart, sound
convert) tersedia native.

### Components

- **`AppDelegate`** — setup `NSStatusItem`, bangun `NSMenu`, wiring semua
  action ke `SettingsStore` / `ReminderScheduler`.
- **`ReminderScheduler`** — core timer (`DispatchSourceTimer`, bukan `Timer`
  biasa, lebih akurat di background). Tiap tick: cek active-hours window →
  kalau di luar, skip + update icon paused; kalau di dalam, fire notif sesuai
  mode aktif. Re-sync di `NSWorkspace.didWakeNotification` (antisipasi drift
  abis sleep).
- **`NotificationManager`** — wrap `UNUserNotificationCenter`. Fire request
  pakai `identifier` tetap (`"heartbeat-reminder"`) biar request baru replace
  yang lama otomatis, gak numpuk.
- **`SoundConverter`** — convert file custom non-caf ke `.caf` via
  `afconvert` (`Process`), validasi durasi ≤30s dulu, simpan ke
  `~/Library/Application Support/Heartbeat/sounds/`.
- **`SettingsStore`** — wrapper `UserDefaults`: mode, normalInterval,
  urgentInterval, activeHoursStart/End, messageText, soundChoice,
  launchAtLogin.
- **`LoginItemManager`** — wrap `SMAppService.mainApp`, register pas
  first-launch (default ON), toggle via checkbox.

### Data flow

```
Launch → LoginItemManager.registerIfFirstLaunch()
       → SettingsStore.load() (default kalau belum ada)
       → ReminderScheduler.start(settings)

Setting berubah → SettingsStore.save() → ReminderScheduler.reconfigure()

Timer tick → di luar active hours? → icon "paused", skip
           → di dalam active hours → NotificationManager.fire(
               message, sound, identifier tetap
             ) → update icon sesuai mode
```

## Error handling

- Notif permission ditolak → status di menu ("Notifications disabled — enable
  in System Settings"), gak retry-spam.
- `afconvert` gagal / format tak didukung → fallback ke system sound default
  + alert singkat, gak crash.
- Sleep/wake → scheduler re-sync via `NSWorkspace.didWakeNotification`.

## Testing

- Unit test `ReminderScheduler` pakai fake clock — assert fire/skip tepat
  sesuai active-hours window & interval per mode (branch logic paling
  krusial).
- Manual test: notif replace behavior, sound convert (mp3→caf), login item
  toggle (native side-effect, susah di-unit-test).

## Distribution

- Unsigned build via GitHub Releases dulu (gratis), README kasih instruksi
  Gatekeeper "Open Anyway".
- Notarize (Apple Developer Program, $99/tahun) opsional belakangan kalau mau
  hilangin warning Gatekeeper — tetep distribusi mandiri, bukan App Store.

## Out of scope (v1)

- Integrasi task tool (Jira/Trello/Notion/dll)
- Snooze button di notif
- Mac App Store submission
- Cross-platform (Windows/Linux) — dipertimbangkan lagi kalau proyek jalan
