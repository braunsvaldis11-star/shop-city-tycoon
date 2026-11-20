# Mini games

Inside a business you own, walk up to the counter and press **F** (gamepad **Y**, or tap the
prompt). This replaced the old "Serve Customer" button, which paid for a single key press.

Definitions live in `src/ReplicatedStorage/Shared/MiniGames.luau`, the server side in
`Services/MiniGameService.luau` and the window in `Controllers/MiniGameController.luau`.

## The five kinds

| Kind | How it plays | Businesses |
|---|---|---|
| **Recipe** | Add the ingredients in the ticket's order; the dish builds up as you go | Pizza (Make a Pizza), Bakery (Decorate a Cake), Coffee (Brew a Coffee), Ice Cream (Scoop a Cone), Burger (Build a Burger), Sushi (Roll Sushi), Seafood (Plate a Feast) |
| **Pick** | Find everything on the customer's list on a shuffled shelf | Bookstore, Clothing, Surf Shop, Toy Store, Supermarket (4 items), Pet Shop, Fish Market, Electronics, Jewelry, Mall, Car Dealership, Hotel |
| **Cash** | Hand over the exact amount with $1–$100 bills; going over starts again | Bank |
| **Timing** | 3 rounds: tap when the sliding marker is in the green zone (Space / A also tap) | Gym (Lift Weights), Spa (Give a Massage), Cinema (Pop the Popcorn), Aquarium (Feed the Fish) |
| **Memory** | Watch the pads flash, then repeat the sequence | Arcade (5 steps), Tech Company (4 steps) |

The pizza is drawn as a round pizza (dough, sauce, cheese, scattered toppings); the other
recipes stack layer by layer on a plate. The customer at the front of the line says the
order in a speech bubble, and gets served when you finish.

## Pay

Reward = **one sale of that business** × grade (minimum $10):

| Grade | When | Multiplier |
|---|---|---|
| ⭐⭐⭐ PERFECT! | no mistakes (timing: every round hit) | ×2 |
| ⭐⭐ GREAT! | 1–2 mistakes (timing: one miss) | ×1.5 |
| ⭐ GOOD | more mistakes | ×1 |

Each finished game also counts toward the "served" stat used by achievements.

## Anti-cheat

- The server makes every order with its own random numbers and keeps it under a one-time token.
- Only the player who owns the business, standing inside it, can start or finish a game.
- The answer must match the order exactly (pick lists in any order; cash must add up with
  real bills), and a game finished faster than a person could (`MiniGames.minSeconds`) is
  refused. Mistakes are reported by the client, but they can only lower the pay.
- `MiniGameStart` and `MiniGameSubmit` are rate-limited by `Net` (3 per second) and a new
  order needs a 0.4 s gap.

## Adding a mini game for a new business

Add an entry to `GAMES` in `MiniGames.luau` keyed by the business id, using one of the five
kinds. Recipes need `items` + `steps` (`fixed(id)` or `pool(ids, min, max)`); pick games need
`items` + `pick`; timing games need `rounds` + `verb`; memory games need 4 `items` + `length`.
A business without an entry falls back to the Supermarket game.
