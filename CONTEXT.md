# Faraday Context

Faraday is a local-first macOS focus enforcement product that keeps a phone-attached beacon physically away during strict focus work.

## Language

**Open-source app**:
The full Faraday macOS software product whose source code is public under an open-source license.
_Avoid_: Open core, source-available app

**Compatibility list**:
A public list of tested BLE beacons and recommended settings for Faraday.
_Avoid_: Required hardware, official-only hardware

**Future beacon kit**:
A possible later paid bundle containing a compatible BLE beacon, setup materials, and convenience onboarding for Faraday.
_Avoid_: Current MVP requirement, proprietary dongle

**Paid convenience**:
Productized non-software help around Faraday, such as a preconfigured beacon, setup materials, onboarding, support, and warranties.
_Avoid_: Paywalled software features, subscription requirement, paid calibration presets

**Bring-your-own beacon**:
A user-supplied compatible iBeacon that Faraday supports as a first-class setup path.
_Avoid_: Unsupported beacon, unofficial beacon

**Apache-2.0 license**:
The open-source license for the Faraday software, chosen for permissive reuse with explicit patent terms.
_Avoid_: Proprietary license, source-available license

**Product strategy**:
The separate commercialization plan for selling a beacon kit and paid convenience around the open-source app.
_Avoid_: MVP requirements, hardware design spec

## Relationships

- The **Open-source app** is released under the **Apache-2.0 license**.
- The **Open-source app** supports a **Bring-your-own beacon** as a first-class path.
- The **Open-source app** documents compatible hardware through a **Compatibility list** first.
- A **Future beacon kit** can later package **Paid convenience** but is not required to use the **Open-source app**.
- **Paid convenience** must not paywall any software feature.
- All software features in the **Open-source app** stay free.
- **Product strategy** belongs in `docs/PRODUCT.md`, while software behavior belongs in `docs/PRD.md`.

## Example dialogue

> **Dev:** "Does Faraday require buying the **Beacon kit**?"
> **Domain expert:** "No — the **Open-source app** should work well with a **Bring-your-own beacon**, while the **Beacon kit** is the paid easy path."

## Flagged ambiguities

- "Open source and product to sell later" resolved as: full software is an **Open-source app**; near-term hardware strategy is a **Compatibility list**, and later monetization may come from an optional **Future beacon kit** and **Paid convenience**.
- "Official beacon" rejected as primary framing; resolved: **Bring-your-own beacon** is first-class, not merely tolerated.
- "Product to sell later" resolved as **Product strategy**, not core MVP scope.
