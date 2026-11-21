# Architecture

Shop City Tycoon is a server-authoritative Roblox game. The server decides every number that
matters (money, customers, purchases, rewards); the client draws the world and sends requests.

## Boot order

**Server** (`ServerScriptService/Main.server.luau`)
- Registry: `Net, Data, Economy, Business, Interior, Progression, Sync, Job, MiniGame`
- `init(registry)` runs for: Data, Economy, Business, Interior, Progression, Sync, Job, MiniGame
- `start()` runs for: Economy, Business, Interior, Progression, Sync, Job, MiniGame, then **Data
  last** so every `onLoaded` callback is registered before any player's data finishes loading.
- A new service must be added to the registry **and** to both lists.

**Client** (`StarterPlayerScripts/ClientMain.client.luau`)
- Order: Store, Sound, UI, Interior, City, Ambient, DayNight, Job, MiniGame, Opening, Life
- Each controller gets `init(registry)` (no yielding), then `start()` in its own thread.

## Networking

- `Services/Net` creates RemoteEvents in `ReplicatedStorage.Remotes` on demand.
- `Net.on(name, ratePerSecond, handler)` wraps every client request in a token bucket and a
  `pcall`, so no remote can be spammed or crash the server loop. Handlers still validate types.
- `Net.declare(name)` creates a server-to-client remote up front so clients can wait for it.
- Clients send with `controllers.Store.send(name, ...)` and listen with `Store.remote(name)`.
- `SyncService` pushes a read-only snapshot of the player's state (batched); clients never
  send state back.

## Economy model

- Every owned business gets customers at its sales rate (`Formulas`: throughput per minute)
  and each one pays the average sale, so long-run income equals `stats.income` per second.
- The server tells the owner's client about each customer `Config.CUSTOMER_LEAD` (12 s)
  before they reach the door, so a pedestrian can walk there in time.
- **Shops** pay `Config.SHOP_VISIT_SECONDS` (6 s) after reaching the door: the customer goes in,
  picks up their item and pays on the way out.
- **Attractions** (`entryFee = true` in `Businesses`: Gym, Arcade, Cinema, Aquarium, Spa, Hotel)
  are paid at the door.
- On the street (`AmbientController`) a shop customer goes in, comes back out
  `SHOP_VISIT_SECONDS` later carrying the product (`InteriorBuilder.product`) and the
  "🛍️ +$" popup shows then; they put the item away a few sidewalk stops later. Attraction
  visitors show "🎟️ +$" as they go in.
- Offline earnings are capped at 2 hours. Prestige multiplies income by +0.5 per level.

## Scripts

### Shared (`src/ReplicatedStorage/Shared`) — used by server and client
| Script | What it does |
|---|---|
| `Businesses` | The 26 business templates and the one upgrade system they all share |
| `CityLayout` | The street plan, defined once for the builder, traffic and map |
| `Config` | Global tuning (economy, prestige, sounds...) |
| `Format` | Number and money formatting |
| `Formulas` | Pure business-simulation maths (the server pays with it, the UI previews with it) |
| `Goals` | Achievements (data only) |
| `MiniGames` | Every business's mini game: definitions, order generation, answer checking, grades |
| `Props` | Low-poly prop factory (parts only, no uploaded assets) |

### Client building blocks (`src/ReplicatedStorage/Client`)
| Script | What it does |
|---|---|
| `Bubble` | Speech bubbles over NPC heads |
| `CityPaths` | Sidewalk network pedestrians walk, with every door spliced in |
| `Icons` | Uploaded image icons (falls back to emoji) |
| `InteriorBuilder` | Builds a business interior from its upgrade levels |
| `NpcRig` | Cheap anchored NPCs moved with one `BulkMoveTo` per frame |
| `UIKit` | Check-UI style building blocks (panels, cards, beveled buttons, headers) |

### Server services (`src/ServerScriptService/Services`)
| Script | What it does |
|---|---|
| `Net` | Remotes, rate limiting, error isolation |
| `DataService` | Load, session-lock, autosave and release player data (`UpdateAsync` everywhere). In a Studio playtest with `Config.STUDIO_TEST_MODE` it never opens the DataStore and starts players with `STUDIO_TEST_MONEY` |
| `EconomyService` | The only code that changes money; customers, offline earnings, stat cache |
| `BusinessService` | Buying, upgrading and levelling businesses |
| `InteriorService` | Entrances and private per-player interiors |
| `ProgressionService` | Ranks, achievements and prestige |
| `SyncService` | Batched state snapshots to each player |
| `JobService` | Optional paper-route side job (off unless `Config.PAPER_ROUTE_ENABLED`) |
| `MiniGameService` | Makes mini-game orders, checks answers, pays rewards |

### Client controllers (`src/StarterPlayer/StarterPlayerScripts/Controllers`)
| Script | What it does |
|---|---|
| `Store` | Read-only copy of the player's state; `onChange`, `send`, `remote` |
| `SoundController` | UI sounds, music playlist, city ambience |
| `UIController` | HUD, menu window, toasts, cash popups, screen fade (PC, mobile, console) |
| `UIPanels` | Contents of every menu page |
| `InteriorController` | Builds your private interior; runs staff, customers and visitors |
| `CityController` | Restyles the shared city from your own state (doors, signs, flags) |
| `AmbientController` | Traffic and pedestrians; sends street customers to doors |
| `DayNightController` | 12-minute day/night cycle on server time |
| `JobController` | Paper-route job visuals |
| `MiniGameController` | The mini-game window (draws the order, reports the answer) |
| `OpeningController` | "Grand Opening" cinematic when you buy a business |
| `LifeController` | Small life touches: chatter, gulls, busker... |

### Dev tools (`src/ServerStorage/DevTools`) — edit time only
| Script | What it does |
|---|---|
| `CityBuilder` | Generates the whole low-poly city from `CityLayout` |
| `PaperRouteBuilder` | Builds the News Stand and mailboxes for the paper route |

## Interior coordinates (InteriorBuilder)

Room 80 x 64 studs, open-topped. Local −Z is the kitchen, +Z is the exit door.
Counter at z = −12 (top surface at y = 3, waist height), registers at x = ±6, ±16,
stations at z = −28, tables at z = 4 and 18, aisle at z = 11.
