# To do

Last updated 2026-11-21.

## Next: publish the mini-game update

Everything below is built, saved in Studio and playtested. The live game still runs the old
version until someone publishes (File > Publish to Roblox).

- [ ] **Publish the place** (File > Publish to Roblox)
- [ ] After publishing, join the live game once and check a shop and its mini game work

## Done in the mini-game update

Requested: replace "Serve Customer" with a mini game for every business, lower the counter,
make shop customers buy something inside, and have attractions charge an entry fee.

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
- [x] Street walkers (`AmbientController`): shoppers come back out carrying what they bought
      and "🛍️ +$" pops up then; attraction visitors show "🎟️ +$" as they go in
- [x] Help text, business tip and the two "serve" achievements now talk about mini games
- [x] Pick-game shelf fits the window (5 × 2; it used to spill a third row out of the window)
- [x] "Start over" button in the Bank game showed a missing symbol; now 🔄
- [x] **Studio test mode** (`Config.STUDIO_TEST_MODE`): Studio playtests never open the
      DataStore and start with $1B test cash, so shops can be bought and tested safely
- [x] Playtested 2026-11-21 in test mode, every kind: recipe (Pizza, PERFECT ×2), pick
      (Bookstore, GREAT ×1.5), memory (Arcade, GREAT with a replay after a wrong pad), cash
      (Bank, PERFECT, Next and Close), timing (Gym, GOOD after 3 misses). No script errors.

## Known quirks

- Visitors wait at a door while a player stands in the doorway (walkers step around
  players), so they pile up there until the player moves.

## Ideas and requests

- [ ] **Museum** business with an entry fee (asked for; there is no museum yet)
- [ ] **Game page:** name, description, icon and 5 thumbnails are ready in
      [marketing/](../marketing/game-page.md); they still need to be put on the page (the
      experience is still called "wwww" with no description or images)

## Recently finished (before the mini-game update)

- Grand Opening crowd walks away and is cleaned up instead of standing forever
- Prestige needs shops, not cash: 1, 3, 5, 8, then 11 shops; 5 prestiges max
- Interior chairs face their tables
