---
marp: true
theme: default
paginate: true
---

# Whear
### Smart Closet Inventory — Final Demo

**Team 4** — Jefferson Ding · Dimitris Deliakidis · Carly Googel

ESE 3500

---

## System Block Diagram

```
 Tagged garments ──UHF──►  6 dBi patch antenna ──►  YRM100 (Impinj R2000)
                                                            │ USART1 @ 115200
                                                            ▼
                                   ┌─────────────────────────────────────┐
                                   │ STM32F411RE (Nucleo, bare-metal C)  │
                                   │  YRM100 driver · TTL tag table      │
                                   └──────────────────┬──────────────────┘
                                                      │ USART6 framer + READY pin
                                                      ▼
                                   ┌─────────────────────────────────────┐
                                   │ ESP32 Feather HUZZAH32 V2           │
                                   │  UART reader · Firestore reconciler │
                                   └──────────────────┬──────────────────┘
                                                      │ HTTPS
                                                      ▼
                               Google Firestore  →  SwiftUI iOS app
```

---

## Hardware Implementation

- **RFID front end:** YRM100 UHF module + 6 dBi SMA patch antenna, US region, 26 dBm TX
- **MCU:** STM32F411RE (Nucleo-64) — 3 USARTs in use
  - USART1 PA9/PA10 → YRM100
  - USART2 PA2/PA3 → ST-Link VCOM debug
  - USART6 PC6/PC7 → ESP32 bridge
  - PA8 → READY input from ESP32
- **Wi-Fi bridge:** Adafruit Feather HUZZAH32 V2 (ESP32), UART2 on GPIO14/32, READY on GPIO27
- **Power:** 5 V USB per board, on-board 3.3 V LDOs
- **Case:** 3D-printed closet-rail mount with integrated hook + external SMA antenna

---

## Firmware — Application Logic

**STM32 bare-metal (`main.c`)**
- Bring-up: HSI clock, SysTick 1 kHz, GPIO AF config, three USARTs
- Wait for ESP32 READY high → start YRM100 multi-inventory (`0xFFFF` rounds)
- Main loop polls YRM100 notices → `find_or_add_tag` into 20-slot table
- Every 5 s: `prune_stale_tags` (TTL = 10 s) → frame set to ESP32

**ESP32 Arduino (`wifi/src/main.cpp`)**
- Associate Wi-Fi → drive READY high
- Parse `0xAA | count | {len,EPC}×N | 0x55` frames from STM32
- `firestore_full_replace`: GET list → DELETE stale → PATCH current

---

## Critical Drivers We Wrote

- **YRM100 driver (`lib/yrm100/`)** — hand-written from the Impinj R2000 manual
  - Frame parser: `0xBB` header / type / CMD / len / payload / checksum / `0x7E`
  - Commands: `SET_REGION`, `SET_TX_POWER`, `START_MULTI_INVENTORY`, `STOP`
  - Callback-based UART backend → portable across MCUs
- **STM32 bare-metal runtime** — no HAL, no CubeMX
  - Hand-rolled register map, `startup.c` vector table, `stm32f411re.ld`
  - 3× USART init + `millis()` timeout RX
- **STM32 ↔ ESP32 framer** — delimited protocol + GPIO ready-pin handshake
- **Firestore reconciler** — upsert/delete against collection snapshot, no auth

---

## Demo

Live on the closet rail:

1. Hang 5 tagged garments → iOS app fills in within one scan cycle
2. Pull one garment out → it disappears within ~10 s (TTL)
3. Put it back → reappears next cycle
4. Walk Wi-Fi out of range → STM32 keeps scanning; ESP32 auto-reconnects and Firestore re-converges

*(video linked in README)*

---

## SRS Results — All Met

| ID  | Requirement | Outcome |
| --- | --- | --- |
| SRS-01 | New EPC into table < 100 ms | ✅ `[NEW]` prints instantly on serial |
| SRS-02 | De-dup, ≥ 20 concurrent tags | ✅ 20-slot `seen_tags` table |
| SRS-03 | Drop tag not seen in 10 s | ✅ `prune_stale_tags` logs `[stale]` |
| SRS-04 | 5 s UART frame to ESP32 | ✅ `[UART] sending N tags` every 5 s |
| SRS-05 | Wi-Fi associate + auto-reconnect | ✅ READY pin toggles with link |
| SRS-06 | Firestore PATCH/DELETE reconcile | ✅ `firestore_full_replace` on each frame |

**Data collection:** ST-Link VCOM logs (`[NEW]`, `[stale]`, `[UART]`, `[poll]` counters) + ESP32 serial (`[firestore] PATCH … → 200`) + live Firestore console.

---

## HRS Results — All Met

| ID  | Requirement | Outcome |
| --- | --- | --- |
| HRS-01 | ≥ 1.5 m read through fabric | ✅ reliably past 1.5 m on hung garments |
| HRS-02 | US region, ≥ 23 dBm | ✅ `REGION_US` + `POWER_2600` (26 dBm) |
| HRS-03 | 2.4 GHz 802.11 b/g/n uplink | ✅ ESP32 Feather to AirPennNet-Device |
| HRS-04 | STM32↔ESP32 UART + READY pin | ✅ 115200 baud + PA8/GPIO27 handshake |
| HRS-05 | Single 5 V USB per board | ✅ Nucleo via ST-Link, Feather via USB-C |
| HRS-06 | Presence change visible < 10 s | ✅ 5 s scan + 10 s TTL + fast Firestore |

**Data collection:** measured range with a tape + tagged shirt; UART captured on logic analyzer; Firestore round-trip timed end-to-end from serial timestamps.

---

## Completing the Product

- **Casework:** 3D-printed closet-rail box with hook; external SMA antenna mount; Nucleo + Feather standoffs. Onshape CAD linked in README.
- **iOS app (`carlygoogel/Whear`):** SwiftUI live list from Firestore, present/missing states, per-garment labels.
- **Cloud:** Firestore project `whear-fb2ac`, collection `scanner`, no auth required for demo.
- **Config surface:** Wi-Fi + Firestore set via `wifi/include/config.h`; scan cadence + TTL via `#define` in `main.c`.

---

## Riskiest Remaining Part

**Last-minute platform swap: nRF5340 + nRF7002 → STM32 + ESP32**

- Through Sprint #2 we had invested in a dual-core nRF5340 stack (bare-metal net core + Zephyr app core + IPC ring + WebSocket).
- Wi-Fi on the nRF7002 was flaky and build/flash turnaround was slow.
- Right before demo, we re-implemented the datapath on STM32 + ESP32, which is what shipped.

**Residual risks on the shipped system**

- Firestore REST reconciliation is chatty — one GET + N PATCH/DELETE per 5 s cycle.
- READY-pin handshake doesn't recover if the ESP32 reboots mid-frame.
- Large wardrobes (> 20 tags) overflow `MAX_TAGS`.

---

## De-risking Plan

- **Cloud path:** batch Firestore writes (single `commit` with multiple document ops) instead of N HTTP calls per cycle → lower latency, fewer network errors.
- **Framer robustness:** add a length-prefixed CRC to the STM32↔ESP32 frame; resync on marker if CRC fails, instead of relying on ordering.
- **Scale:** move `seen_tags` to a small hash table on the STM32, grow `MAX_TAGS` to ~128 (plenty of RAM on F411RE).
- **Standby:** use STM32 Stop mode between scans to cut idle current on battery.
- **Platform lesson:** for any future redesign, prototype the RF + Wi-Fi path end-to-end on the final silicon before committing the application layer.

---

## Questions for the Teaching Team

- Is Firestore (HTTPS REST) an acceptable cloud layer for the grading rubric, or should we add a self-hosted WebSocket server for the demo?
- For the "networking" requirement, does our STM32↔ESP32 UART framer count, or do we need the STM32 itself on the network?
- Any recommendations on an ESE-blessed way to measure RFID read range (reference tag, distance protocol)?
- For the report: should we document both the nRF5340 attempt and the shipped STM32 path, or only the shipped system?

---

# Thanks!

Questions?

**Repo:** github.com/upenn-embedded/final-project-whear
**iOS:** github.com/carlygoogel/Whear
