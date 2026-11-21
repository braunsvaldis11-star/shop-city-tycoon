# Game page

Name, description, icon and thumbnails for the Roblox game page. Everything here was made
on 2026-11-21 from screenshots of the game itself (Studio test mode), with titles added by
`make-images.ps1`. The untouched screenshots are in `raw/`.

## Where to put it

**Creator Dashboard:** create.roblox.com > Creations > the experience > Configure.

| What | Where |
|---|---|
| Name and description | Configure > Basic Info (or Studio: Home > Game Settings > Basic Info) |
| Icon | Configure > Basic Info > Icon: upload `icon.png` |
| Thumbnails | Configure > Thumbnails (or Places > Start Place > Thumbnails): upload in the order below |

## Name

Shop City Tycoon

## Description (paste as is)

🏙️ Build a business empire in a living pastel city!

🍕 Own 26 businesses, from a tiny Pizza Restaurant to the City Bank
🚶 Watch real customers walk in from the street and come out with their shopping
🎮 Play a mini game at every counter: make pizzas, find the books, count the cash, beat the high score!
⬆️ Upgrade, hire staff and watch your shop change inside
🎟️ Run attractions that charge an entry fee: Arcade, Cinema, Aquarium, Spa and more
🌟 Prestige for a permanent income boost
💤 Keep earning while you're offline (up to 2 hours)

Controls: E enter or buy · F mini game · B Shops · U Upgrades · M Map
Plays on PC, mobile and console.

## Images

| Order | File | Shows | Size |
|---|---|---|---|
| Icon | `icon.png` | Pizza Restaurant with customers, "SHOP CITY TYCOON" | 512 × 512 |
| 1 | `thumbnail-1-city.jpg` | Street view of the starter plaza, big title | 1280 × 720 |
| 2 | `thumbnail-2-minigame.jpg` | "Make a Pizza" mini game, "PLAY MINI GAMES!" | 1280 × 720 |
| 3 | `thumbnail-3-street.jpg` | Customers carrying pizza boxes out, "REAL CUSTOMERS!" | 1280 × 720 |
| 4 | `thumbnail-4-inside.jpg` | Upgraded restaurant interior, "UPGRADE YOUR SHOP!" | 1280 × 720 |
| 5 | `thumbnail-5-aerial.jpg` | Aerial view of the city, "26 BUSINESSES TO OWN!" | 1280 × 720 |

Owner name tags and the HUD were hidden for the screenshots, so no username appears.

## Remaking the images

1. In a Studio playtest (test mode), hide the HUD and the `OwnerTag` billboards on the client,
   then take screenshots (1369 × 720 from the Studio viewport) and save them in `raw/`.
2. Run `powershell -File marketing/make-images.ps1 -Marketing marketing` from the repo root.
   It crops to 1280 × 720 (and 512 × 512 for the icon) and draws the titles in Segoe UI Black.
