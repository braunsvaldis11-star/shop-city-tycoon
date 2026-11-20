# To do

Snapshot taken 2026-11-20, in the middle of the mini-game update.

## In progress: mini games and customer payments

Requested: replace "Serve Customer" with a mini game for every business, lower the counter,
make shop customers buy something inside, and have attractions charge an entry fee.

Done (in Studio and in this repo):
- [x] Counter lowered to waist height (counter, registers, pickup trays, prep counters)
- [x] `MiniGames` shared module: 26 games in 5 kinds, order generation, checking, grades
- [x] `MiniGameService` on the server (orders, checks, anti-speed, rewards); added to `Main`
- [x] `MiniGameController` window on the client; added to `ClientMain`
- [x] Counter prompt is now the business's mini game ("Make a Pizza", "Count the Cash"...)
- [x] Old `HelpServe` remote, `BusinessService.helpServe` and `Config.HELP_SERVE_*` removed
- [x] `Businesses.entryFee` for Gym, Arcade, Cinema, Aquarium, Spa, Hotel
- [x] Server pays shops 6 s after the customer reaches the door (`Config.SHOP_VISIT_SECONDS`)
- [x] Interior: customers walk in when their street walker reaches the door; attraction
      visitors pay at the door (🎟️), then sit or watch, then leave
- [x] Every script compiles

Still to do:
- [ ] **Playtest every mini-game kind** (recipe, pick, cash, timing, memory) and check the
      console for errors. Needs a test account that owns a shop: never buy businesses or
      grant money on the published game for testing.
- [ ] `AmbientController` (street walkers):
  - shops: no popup when the customer goes in; after `SHOP_VISIT_SECONDS` they come out
    carrying the product (`InteriorBuilder.product`) and the "🛍️ +$" popup shows then
  - attractions: keep the popup on entering, but show "🎟️ +$"
  - drop the carried item a few nodes later; clear it when a walker is recycled
- [ ] `UIPanels` help text: "F to serve" → "F plays the mini game", "Y serves" → "Y plays the mini game"
- [ ] `UIPanels` business tip: "Every customer pays when they're served" → explain shops pay on the
      way out and attractions at the door
- [ ] `Goals`: "Serve 100 customers yourself" → "Complete 100 mini games" (same for 1,000)
- [ ] Save the place, then publish (File > Publish to Roblox) once it is tested

## Ideas and requests

- [ ] **Museum** business with an entry fee (asked for; there is no museum yet)
- [ ] AI thumbnails and icon for the game page (Forge GUI ran out of credits: 3 thumbnails
      needed 1,600, the account had 1,064)
- [ ] Rename the place from "wwww" to the chosen title, Shop City Tycoon

## Recently finished (before this snapshot)

- Grand Opening crowd walks away and is cleaned up instead of standing forever
- Prestige needs shops, not cash: 1, 3, 5, 8, then 11 shops; 5 prestiges max
- Interior chairs face their tables
