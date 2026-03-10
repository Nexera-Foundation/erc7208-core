# Sovereign Frontiers: An example of ERC-7208 architecture with callbacks

**Sovereign Frontiers** is a decentralized strategy game designed to showcase the power of the **ERC-7208 (On-Chain Data Containers)** standard. It leverages a decoupled architecture where data storage is separated from game logic, utilizing the `CallbackProcessorDataObject` extension to enable reactive, autonomous on-chain behavior.

---

## 🏗 Architecture Overview

The game is split into three distinct layers:

1. **Data Layer (`SovereignRegistry`)**: A `DataObject` that acts as the "source of truth." It stores the state of every territory (DataPoint) and manages reactive callbacks.
2. **Logic Layer (`WarEngine`)**: The "Game Master" `DataManager`. It handles the complex math of combat, resource costs, and initiates state changes and notifications.
3. **Interaction Layer (`CommandCenter`)**: The player-facing `DataManager`. It provides the interface for players to issue commands, manage their territories, and assign automation scripts.

---

## 📊 Data Structure

Each territory is identified by a unique `bytes32 DataPoint`. The state stored within the `SovereignRegistry` includes:

| Field | Type | Description |
| --- | --- | --- |
| `militaryPower` | `uint256` | Mobile units available for attack or reinforcement. When the army is sent elsewhere, the WarEngine sets this to zero in the registry; it can still increase from energy allocation. |
| `garrison` | `uint256` | Static defense units (multiplied by a global `DEFENCE_MULTIPLIER`). |
| `energyYield` | `uint256` | Base energy production per epoch. |
| `lastUpdate` | `uint256` | The block number of the last resource settlement. |
| `allocation` | `(uint256, uint256, uint256)` | Tuple `(Offense, Defense, Economy)` — percentage of energy distributed to each direction. Each value is in 1e18 scale (1e18 = 100%). Sum must equal 1e18. |

---

## 🕹 Core Mechanics

### 1. Lazy Energy Settlement

To optimize gas costs, energy is not accumulated every block. Instead, it is calculated only when a DataPoint is interacted with.

* **Formula:** `AccumulatedEnergy = energyYield * (currentBlock - lastUpdate)`.
* Upon any action (attacking, responding to a support request, or manual settlement), the `WarEngine` calculates this energy and distributes it according to the territory's `allocation` tuple (Offense, Defense, Economy).

### 2. Energy Allocation (Offense / Defense / Economy)

Each territory has an allocation tuple `(Offense, Defense, Economy)` stored on-chain. When energy is settled, the `WarEngine` distributes the new energy according to these percentages:

* **Offense:** Fraction of energy that increases `militaryPower`.
* **Defense:** Fraction of energy that increases `garrison`.
* **Economy:** Fraction of energy that increases `energyYield`.

Values are in 1e18 scale (1e18 = 100%). The three components must sum to 1e18.

### 3. Reactive Callbacks (The "Force Echo")

By using the `CallbackProcessor` territories can react to external events within the same transaction:

* **Task `0x1` (Under Attack):** Triggered when an enemy targets the DataPoint.
* **Task `0x2` (Request for Aid):** Triggered when an allied DataPoint calls for reinforcements. The territory may respond by sending support (subject to its diplomacy thresholds)—no manual "send army to defend" action; defence is purely reactive.

### 4. Army sent to another location

There is no `deployment` field. When a territory sends its army (to attack or to support an ally), the **WarEngine** decreases that territory's `militaryPower` to zero in the registry and tracks the army in transit internally. The source territory's `militaryPower` can still increase from energy allocation while the army is away.

---

## 🛠 Contract Roles

### **SovereignRegistry (DataObject)**

* Stores the `bytes32` state for all participants.
* Filters and executes callbacks based on bitmasks (e.g., a "Fortress" strategy might only listen to `0x1` attack tasks).

### **WarEngine (GameMaster DM)**

* Defines global constants: `DEFENCE_MULTIPLIER`, `UPGRADE_COSTS`, `TRAVEL_TIME` and `EPOCH_TIME`.
* When sending an army to another location (attack or support), decreases the source territory's `militaryPower` to zero in the registry and tracks the army in transit; the source can still accrue `militaryPower` from energy allocation.
* Executes combat logic: calculating losses based on `militaryPower` vs. `garrison * DEF_COEFF`.
* Updates the `SovereignRegistry` and triggers the appropriate callback tasks.
* Triggers tasks initiated by other players.

### **CommandCenter (Player DM)**

* Entry point for users to issue high-level commands (e.g. `attack()`). Defence is not manual: armies are sent to allied territories only in reaction to support requests (Task `0x2`), according to diplomacy settings.
* Manages **diplomacy settings** for a territory:
  * Stores a preferred allied `DataPoint` it can automatically call for support when under attack.
  * Stores a mapping from allied `DataPoint` → **attack force threshold** that defines when it is willing to send support in response to a Request for Aid.

For example, if the diplomacy mapping is:

* `A => 1000`
* `B => 5000`

Then:

* If `A` is attacked with force `500`, it will send support (500 ≤ 1000).
* If `A` is attacked with force `2000`, it will not send support (2000 > 1000).
* If `B` is attacked with force `2000`, it will send support (2000 ≤ 5000).

