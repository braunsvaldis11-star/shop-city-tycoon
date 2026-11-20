--!strict
-- MiniGames (shared): the hands-on mini game of every business, played by the owner
-- inside their own shop (the F prompt at the counter). The server builds every order
-- from these tables with its own random numbers and checks the answer; the client uses
-- the same tables to draw the game. Five kinds of game:
--  * recipe: add the ingredients in the ticket's order (pizza, burgers, coffee, cakes...)
--  * pick:   find everything on the customer's list (shops)
--  * cash:   hand over the exact amount in bills (bank)
--  * timing: tap when the marker is in the green zone (gym, spa, cinema, aquarium)
--  * memory: repeat the flashing sequence (arcade, tech company)
-- Container: ReplicatedStorage.Shared

local MiniGames = {}

export type Item = { id: string, name: string, emoji: string, color: Color3 }
export type Step = { fixed: string?, pool: { string }?, min: number?, max: number? }
export type Game = {
	kind: string,
	action: string, -- prompt text, e.g. "Make a Pizza"
	emoji: string,
	hint: string,
	look: string?, -- recipe: "round" (pizza) or "stack"
	items: { Item },
	steps: { Step }?, -- recipe
	pick: number?, -- pick: items on each list
	rounds: number?, -- timing
	length: number?, -- memory
	verb: string?, -- timing: text on the tap button
	line: string?, -- what the customer says ("%s" is the order)
}
export type Order = {
	kind: string,
	list: { string }?, -- recipe / pick / memory
	target: number?, -- cash
	zones: { { number } }?, -- timing: { centre, width, seconds per sweep } for each round
}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

-- Compact item lists: { id, name, emoji, colour }.
local function items(list: { { any } }): { Item }
	local out = {}
	for _, entry in list do
		table.insert(out, { id = entry[1], name = entry[2], emoji = entry[3], color = entry[4] })
	end
	return out
end
local function fixed(id: string): Step
	return { fixed = id }
end
local function pool(ids: { string }, min: number, max: number): Step
	return { pool = ids, min = min, max = max }
end

MiniGames.BILLS = { 1, 5, 10, 20, 50, 100 }
MiniGames.MAX_BILLS = 40

-- Grades: mistakes (or missed taps) decide the multiplier on one sale's value.
MiniGames.GRADES = {
	{ name = "PERFECT!", stars = 3, multiplier = 2, color = rgb(255, 205, 0) },
	{ name = "GREAT!", stars = 2, multiplier = 1.5, color = rgb(120, 230, 255) },
	{ name = "GOOD", stars = 1, multiplier = 1, color = rgb(150, 255, 90) },
}

local RECIPE_HINT = "Add the ingredients in the order on the ticket!"
local PICK_HINT = "Tap everything on the customer's list!"
local TIMING_HINT = "Tap when the marker is inside the green zone!"
local MEMORY_HINT = "Watch the lights, then press them in the same order!"

local GAMES: { [string]: Game } = {
	----- Recipes -----
	Pizza = {
		kind = "recipe", action = "Make a Pizza", emoji = "🍕", look = "round", hint = RECIPE_HINT,
		line = "A pizza with %s, please!",
		items = items({
			{ "dough", "Dough", "🍞", rgb(240, 205, 145) },
			{ "sauce", "Sauce", "🍅", rgb(215, 45, 35) },
			{ "cheese", "Cheese", "🧀", rgb(255, 210, 70) },
			{ "pepperoni", "Pepperoni", "🔴", rgb(185, 40, 40) },
			{ "mushroom", "Mushrooms", "🍄", rgb(205, 175, 145) },
			{ "olive", "Olives", "⚫", rgb(55, 60, 50) },
			{ "pepper", "Peppers", "🌶️", rgb(70, 170, 60) },
			{ "pineapple", "Pineapple", "🍍", rgb(255, 220, 60) },
			{ "basil", "Basil", "🌿", rgb(40, 150, 60) },
			{ "ham", "Ham", "🥓", rgb(240, 140, 140) },
		}),
		steps = { fixed("dough"), fixed("sauce"), fixed("cheese"), pool({ "pepperoni", "mushroom", "olive", "pepper", "pineapple", "basil", "ham" }, 1, 2) },
	},
	Bakery = {
		kind = "recipe", action = "Decorate a Cake", emoji = "🎂", look = "stack", hint = RECIPE_HINT,
		line = "A cake with %s, please!",
		items = items({
			{ "sponge", "Sponge", "🍰", rgb(235, 190, 120) },
			{ "cream", "Cream", "🥛", rgb(255, 250, 235) },
			{ "strawberry", "Strawberries", "🍓", rgb(230, 40, 60) },
			{ "chocolate", "Chocolate", "🍫", rgb(110, 60, 30) },
			{ "blueberry", "Blueberries", "🔵", rgb(70, 80, 200) },
			{ "cherry", "Cherries", "🍒", rgb(200, 20, 40) },
			{ "sprinkles", "Sprinkles", "🌈", rgb(255, 140, 200) },
			{ "candle", "Candle", "🕯️", rgb(255, 235, 170) },
		}),
		steps = { fixed("sponge"), fixed("cream"), pool({ "strawberry", "chocolate", "blueberry", "cherry", "sprinkles" }, 1, 2), fixed("candle") },
	},
	Coffee = {
		kind = "recipe", action = "Brew a Coffee", emoji = "☕", look = "stack", hint = RECIPE_HINT,
		line = "A coffee with %s, please!",
		items = items({
			{ "cup", "Cup", "🥤", rgb(250, 250, 250) },
			{ "espresso", "Espresso", "☕", rgb(95, 55, 30) },
			{ "milk", "Milk", "🥛", rgb(250, 245, 230) },
			{ "caramel", "Caramel", "🍯", rgb(215, 140, 50) },
			{ "chocolate", "Chocolate", "🍫", rgb(110, 60, 30) },
			{ "vanilla", "Vanilla", "🌼", rgb(250, 230, 160) },
			{ "ice", "Ice", "🧊", rgb(180, 225, 255) },
			{ "cinnamon", "Cinnamon", "🍂", rgb(170, 95, 45) },
			{ "foam", "Foam", "☁️", rgb(245, 240, 230) },
		}),
		steps = { fixed("cup"), fixed("espresso"), pool({ "milk", "caramel", "chocolate", "vanilla", "ice", "cinnamon" }, 1, 2), fixed("foam") },
	},
	IceCream = {
		kind = "recipe", action = "Scoop a Cone", emoji = "🍦", look = "stack", hint = RECIPE_HINT,
		line = "A cone with %s, please!",
		items = items({
			{ "cone", "Cone", "🍦", rgb(215, 160, 90) },
			{ "vanilla", "Vanilla", "🍨", rgb(255, 245, 210) },
			{ "strawberry", "Strawberry", "🍓", rgb(255, 140, 165) },
			{ "chocolate", "Chocolate", "🍫", rgb(125, 75, 45) },
			{ "mint", "Mint", "🌿", rgb(150, 230, 180) },
			{ "mango", "Mango", "🥭", rgb(255, 185, 60) },
			{ "sprinkles", "Sprinkles", "🌈", rgb(255, 120, 200) },
			{ "cherry", "Cherry", "🍒", rgb(200, 20, 40) },
			{ "syrup", "Syrup", "🍯", rgb(200, 120, 40) },
		}),
		steps = { fixed("cone"), pool({ "vanilla", "strawberry", "chocolate", "mint", "mango" }, 2, 3), pool({ "sprinkles", "cherry", "syrup" }, 1, 1) },
	},
	Burger = {
		kind = "recipe", action = "Build a Burger", emoji = "🍔", look = "stack", hint = RECIPE_HINT,
		line = "A burger with %s, please!",
		items = items({
			{ "bottom", "Bottom Bun", "🍞", rgb(225, 165, 85) },
			{ "patty", "Patty", "🥩", rgb(115, 60, 35) },
			{ "cheese", "Cheese", "🧀", rgb(255, 200, 50) },
			{ "lettuce", "Lettuce", "🥬", rgb(110, 200, 80) },
			{ "tomato", "Tomato", "🍅", rgb(225, 60, 50) },
			{ "onion", "Onion", "🧅", rgb(235, 215, 235) },
			{ "pickles", "Pickles", "🥒", rgb(120, 170, 60) },
			{ "bacon", "Bacon", "🥓", rgb(200, 90, 80) },
			{ "top", "Top Bun", "🥯", rgb(235, 175, 90) },
		}),
		steps = { fixed("bottom"), fixed("patty"), pool({ "cheese", "lettuce", "tomato", "onion", "pickles", "bacon" }, 2, 3), fixed("top") },
	},
	Sushi = {
		kind = "recipe", action = "Roll Sushi", emoji = "🍣", look = "stack", hint = RECIPE_HINT,
		line = "Sushi with %s, please!",
		items = items({
			{ "seaweed", "Seaweed", "🟩", rgb(35, 70, 40) },
			{ "rice", "Rice", "🍚", rgb(250, 250, 245) },
			{ "salmon", "Salmon", "🍣", rgb(250, 135, 90) },
			{ "tuna", "Tuna", "🐟", rgb(205, 50, 70) },
			{ "cucumber", "Cucumber", "🥒", rgb(120, 190, 90) },
			{ "avocado", "Avocado", "🥑", rgb(165, 205, 90) },
			{ "crab", "Crab", "🦀", rgb(240, 100, 80) },
			{ "egg", "Egg", "🥚", rgb(255, 220, 100) },
			{ "shrimp", "Shrimp", "🍤", rgb(255, 150, 100) },
		}),
		steps = { fixed("seaweed"), fixed("rice"), pool({ "salmon", "tuna", "cucumber", "avocado", "crab", "egg", "shrimp" }, 2, 2) },
	},
	Seafood = {
		kind = "recipe", action = "Plate a Feast", emoji = "🦞", look = "stack", hint = RECIPE_HINT,
		line = "A plate with %s, please!",
		items = items({
			{ "plate", "Plate", "🍽️", rgb(240, 240, 245) },
			{ "lobster", "Lobster", "🦞", rgb(220, 60, 40) },
			{ "shrimp", "Shrimp", "🍤", rgb(255, 150, 100) },
			{ "fish", "Fish", "🐟", rgb(150, 180, 210) },
			{ "crab", "Crab", "🦀", rgb(240, 100, 80) },
			{ "oyster", "Oysters", "🦪", rgb(205, 195, 185) },
			{ "fries", "Fries", "🍟", rgb(255, 210, 80) },
			{ "salad", "Salad", "🥗", rgb(120, 200, 90) },
			{ "lemon", "Lemon", "🍋", rgb(255, 235, 60) },
		}),
		steps = { fixed("plate"), pool({ "lobster", "shrimp", "fish", "crab", "oyster" }, 1, 2), pool({ "fries", "salad" }, 1, 1), fixed("lemon") },
	},

	----- Shopping lists -----
	Bookstore = {
		kind = "pick", action = "Find the Books", emoji = "📚", pick = 3, hint = PICK_HINT,
		line = "Looking for: %s!",
		items = items({
			{ "comic", "Comic", "🦸", rgb(255, 90, 90) },
			{ "novel", "Novel", "📕", rgb(220, 60, 60) },
			{ "cookbook", "Cookbook", "🍳", rgb(255, 190, 60) },
			{ "atlas", "Atlas", "🗺️", rgb(90, 170, 230) },
			{ "poems", "Poems", "📜", rgb(230, 210, 160) },
			{ "mystery", "Mystery", "🔍", rgb(120, 110, 200) },
			{ "space", "Space Book", "🚀", rgb(60, 80, 160) },
			{ "kids", "Kids' Book", "🧸", rgb(255, 170, 120) },
			{ "dictionary", "Dictionary", "📘", rgb(60, 130, 220) },
			{ "magazine", "Magazine", "📰", rgb(180, 180, 190) },
		}),
	},
	Clothing = {
		kind = "pick", action = "Pick the Outfit", emoji = "👕", pick = 3, hint = PICK_HINT,
		line = "I'd like: %s!",
		items = items({
			{ "tshirt", "T-Shirt", "👕", rgb(80, 160, 240) },
			{ "jeans", "Jeans", "👖", rgb(60, 90, 170) },
			{ "dress", "Dress", "👗", rgb(240, 90, 170) },
			{ "coat", "Coat", "🧥", rgb(160, 110, 70) },
			{ "cap", "Cap", "🧢", rgb(60, 120, 220) },
			{ "sneakers", "Sneakers", "👟", rgb(235, 235, 240) },
			{ "scarf", "Scarf", "🧣", rgb(220, 60, 60) },
			{ "socks", "Socks", "🧦", rgb(255, 150, 200) },
			{ "gloves", "Gloves", "🧤", rgb(90, 200, 120) },
			{ "heels", "Heels", "👠", rgb(220, 30, 60) },
		}),
	},
	SurfShop = {
		kind = "pick", action = "Pack the Beach Bag", emoji = "🏄", pick = 3, hint = PICK_HINT,
		line = "Beach day! I need: %s!",
		items = items({
			{ "board", "Surfboard", "🏄", rgb(60, 200, 230) },
			{ "swimsuit", "Swimsuit", "🩱", rgb(255, 110, 150) },
			{ "shades", "Sunglasses", "🕶️", rgb(70, 70, 85) },
			{ "sandals", "Sandals", "👡", rgb(230, 170, 90) },
			{ "sunscreen", "Sunscreen", "🧴", rgb(255, 220, 90) },
			{ "ball", "Beach Ball", "🏐", rgb(255, 140, 60) },
			{ "shorts", "Shorts", "🩳", rgb(90, 150, 240) },
			{ "goggles", "Goggles", "🤿", rgb(60, 190, 170) },
			{ "hat", "Sun Hat", "👒", rgb(245, 215, 140) },
			{ "shell", "Shell", "🐚", rgb(255, 200, 190) },
		}),
	},
	ToyStore = {
		kind = "pick", action = "Wrap the Toys", emoji = "🧸", pick = 3, hint = PICK_HINT,
		line = "I want: %s!",
		items = items({
			{ "teddy", "Teddy", "🧸", rgb(190, 130, 80) },
			{ "robot", "Robot", "🤖", rgb(160, 170, 190) },
			{ "ball", "Ball", "⚽", rgb(235, 235, 240) },
			{ "yoyo", "Yo-Yo", "🪀", rgb(230, 60, 80) },
			{ "kite", "Kite", "🪁", rgb(90, 170, 240) },
			{ "blocks", "Blocks", "🧱", rgb(230, 110, 70) },
			{ "car", "Toy Car", "🚗", rgb(230, 50, 50) },
			{ "balloon", "Balloon", "🎈", rgb(255, 80, 110) },
			{ "puzzle", "Puzzle", "🧩", rgb(90, 200, 110) },
			{ "dino", "Dino", "🦖", rgb(90, 190, 90) },
		}),
	},
	Supermarket = {
		kind = "pick", action = "Pack the Groceries", emoji = "🛒", pick = 4, hint = PICK_HINT,
		line = "My list: %s.",
		items = items({
			{ "apple", "Apples", "🍎", rgb(220, 40, 40) },
			{ "bread", "Bread", "🍞", rgb(225, 170, 90) },
			{ "milk", "Milk", "🥛", rgb(245, 245, 245) },
			{ "eggs", "Eggs", "🥚", rgb(250, 235, 200) },
			{ "cheese", "Cheese", "🧀", rgb(255, 205, 60) },
			{ "carrot", "Carrots", "🥕", rgb(255, 140, 40) },
			{ "banana", "Bananas", "🍌", rgb(255, 225, 60) },
			{ "juice", "Juice", "🧃", rgb(255, 170, 60) },
			{ "rice", "Rice", "🍚", rgb(240, 240, 235) },
			{ "tomato", "Tomatoes", "🍅", rgb(225, 60, 50) },
		}),
	},
	PetShop = {
		kind = "pick", action = "Pack the Pet Order", emoji = "🐶", pick = 3, hint = PICK_HINT,
		line = "For my pet: %s!",
		items = items({
			{ "bone", "Dog Bone", "🦴", rgb(240, 230, 210) },
			{ "yarn", "Cat Toy", "🧶", rgb(230, 80, 120) },
			{ "leash", "Leash", "🦮", rgb(200, 120, 60) },
			{ "fishfood", "Fish Food", "🐠", rgb(255, 150, 60) },
			{ "seeds", "Bird Seed", "🐦", rgb(120, 190, 240) },
			{ "bed", "Pet Bed", "🛏️", rgb(150, 110, 200) },
			{ "collar", "Collar", "📿", rgb(220, 60, 60) },
			{ "wheel", "Hamster Wheel", "🐹", rgb(240, 180, 120) },
			{ "shampoo", "Shampoo", "🧴", rgb(110, 200, 230) },
			{ "basket", "Basket", "🧺", rgb(200, 150, 90) },
		}),
	},
	FishMarket = {
		kind = "pick", action = "Pack the Catch", emoji = "🐟", pick = 3, hint = PICK_HINT,
		line = "I'll take: %s!",
		items = items({
			{ "salmon", "Salmon", "🍣", rgb(250, 135, 90) },
			{ "tuna", "Tuna", "🐟", rgb(90, 130, 190) },
			{ "shrimp", "Shrimp", "🦐", rgb(255, 150, 110) },
			{ "crab", "Crab", "🦀", rgb(230, 80, 60) },
			{ "lobster", "Lobster", "🦞", rgb(210, 50, 40) },
			{ "octopus", "Octopus", "🐙", rgb(230, 110, 170) },
			{ "squid", "Squid", "🦑", rgb(240, 170, 190) },
			{ "oyster", "Oysters", "🦪", rgb(205, 195, 185) },
			{ "puffer", "Pufferfish", "🐡", rgb(240, 210, 90) },
			{ "clams", "Clams", "🐚", rgb(240, 200, 180) },
		}),
	},
	Electronics = {
		kind = "pick", action = "Ring Up the Gadgets", emoji = "📱", pick = 3, hint = PICK_HINT,
		line = "I'm after: %s!",
		items = items({
			{ "phone", "Phone", "📱", rgb(60, 70, 90) },
			{ "laptop", "Laptop", "💻", rgb(170, 180, 195) },
			{ "headphones", "Headphones", "🎧", rgb(230, 60, 90) },
			{ "tv", "TV", "📺", rgb(70, 80, 100) },
			{ "camera", "Camera", "📷", rgb(90, 90, 100) },
			{ "console", "Console", "🎮", rgb(120, 90, 220) },
			{ "watch", "Smartwatch", "⌚", rgb(60, 170, 230) },
			{ "speaker", "Speaker", "🔊", rgb(255, 150, 60) },
			{ "charger", "Charger", "🔌", rgb(235, 235, 240) },
			{ "keyboard", "Keyboard", "⌨️", rgb(150, 160, 175) },
		}),
	},
	Jewelry = {
		kind = "pick", action = "Fill the Gift Box", emoji = "💍", pick = 3, hint = PICK_HINT,
		line = "I'd love: %s!",
		items = items({
			{ "ring", "Ring", "💍", rgb(255, 210, 90) },
			{ "diamond", "Diamond", "💎", rgb(120, 220, 255) },
			{ "crown", "Crown", "👑", rgb(255, 200, 40) },
			{ "necklace", "Necklace", "📿", rgb(240, 240, 255) },
			{ "watch", "Gold Watch", "⌚", rgb(255, 195, 60) },
			{ "earrings", "Earrings", "✨", rgb(255, 230, 120) },
			{ "brooch", "Brooch", "🌸", rgb(255, 170, 210) },
			{ "tiara", "Tiara", "👸", rgb(240, 200, 255) },
			{ "gift", "Gift Box", "🎁", rgb(230, 60, 90) },
			{ "coins", "Gold Coins", "💰", rgb(255, 190, 40) },
		}),
	},
	Mall = {
		kind = "pick", action = "Fill the Shopping Bag", emoji = "🛍️", pick = 3, hint = PICK_HINT,
		line = "Shopping for: %s!",
		items = items({
			{ "shoes", "Shoes", "👟", rgb(235, 235, 240) },
			{ "handbag", "Handbag", "👜", rgb(200, 90, 60) },
			{ "shades", "Sunglasses", "🕶️", rgb(70, 70, 85) },
			{ "tophat", "Top Hat", "🎩", rgb(60, 60, 70) },
			{ "lipstick", "Lipstick", "💄", rgb(220, 40, 90) },
			{ "teddy", "Teddy", "🧸", rgb(190, 130, 80) },
			{ "books", "Books", "📚", rgb(90, 140, 220) },
			{ "candy", "Candy", "🍬", rgb(255, 120, 200) },
			{ "headphones", "Headphones", "🎧", rgb(230, 60, 90) },
			{ "perfume", "Perfume", "🌸", rgb(255, 170, 210) },
		}),
	},
	CarDealership = {
		kind = "pick", action = "Prep the Car", emoji = "🚗", pick = 3, hint = PICK_HINT,
		line = "My car needs: %s!",
		items = items({
			{ "keys", "Car Keys", "🔑", rgb(255, 205, 60) },
			{ "wash", "Car Wash", "🧽", rgb(255, 230, 90) },
			{ "fuel", "Full Tank", "⛽", rgb(230, 60, 60) },
			{ "gps", "GPS", "🧭", rgb(90, 170, 230) },
			{ "freshener", "Air Freshener", "🌲", rgb(60, 170, 90) },
			{ "paint", "New Paint", "🎨", rgb(220, 120, 230) },
			{ "bow", "Big Bow", "🎀", rgb(240, 60, 110) },
			{ "toolbox", "Toolbox", "🧰", rgb(220, 60, 50) },
			{ "tuneup", "Tune-Up", "🔧", rgb(150, 160, 175) },
			{ "lights", "New Lights", "💡", rgb(255, 235, 120) },
		}),
	},
	Hotel = {
		kind = "pick", action = "Prepare the Room", emoji = "🏨", pick = 3, hint = PICK_HINT,
		line = "For my room: %s, please!",
		items = items({
			{ "sheets", "Fresh Sheets", "🛏️", rgb(240, 240, 250) },
			{ "key", "Room Key", "🗝️", rgb(255, 205, 60) },
			{ "mints", "Mints", "🍬", rgb(150, 230, 200) },
			{ "robe", "Robe", "🥋", rgb(250, 250, 250) },
			{ "slippers", "Slippers", "🥿", rgb(255, 190, 200) },
			{ "flowers", "Flowers", "💐", rgb(255, 120, 170) },
			{ "fruit", "Fruit Bowl", "🍇", rgb(150, 80, 190) },
			{ "soap", "Soap", "🧼", rgb(140, 210, 255) },
			{ "lamp", "Lamp", "💡", rgb(255, 230, 120) },
			{ "towels", "Towels", "🧺", rgb(200, 160, 110) },
		}),
	},

	----- Cash -----
	Bank = {
		kind = "cash", action = "Count the Cash", emoji = "🏦",
		hint = "Hand over the exact amount, not a dollar more!",
		line = "I'd like to take out %s, please.",
		items = items({
			{ "1", "$1", "💵", rgb(130, 200, 120) },
			{ "5", "$5", "💵", rgb(90, 185, 120) },
			{ "10", "$10", "💵", rgb(60, 170, 140) },
			{ "20", "$20", "💵", rgb(60, 150, 175) },
			{ "50", "$50", "💵", rgb(80, 120, 205) },
			{ "100", "$100", "💵", rgb(125, 90, 215) },
		}),
	},

	----- Timing -----
	Gym = { kind = "timing", action = "Lift Weights", emoji = "🏋️", verb = "LIFT!", rounds = 3, hint = TIMING_HINT, items = {} },
	Spa = { kind = "timing", action = "Give a Massage", emoji = "💆", verb = "RELAX!", rounds = 3, hint = TIMING_HINT, items = {} },
	Cinema = { kind = "timing", action = "Pop the Popcorn", emoji = "🍿", verb = "POP!", rounds = 3, hint = TIMING_HINT, items = {} },
	Aquarium = { kind = "timing", action = "Feed the Fish", emoji = "🐠", verb = "FEED!", rounds = 3, hint = TIMING_HINT, items = {} },

	----- Memory -----
	Arcade = {
		kind = "memory", action = "Beat the High Score", emoji = "🕹️", length = 5, hint = MEMORY_HINT,
		items = items({
			{ "red", "Red", "🔴", rgb(235, 60, 70) },
			{ "blue", "Blue", "🔵", rgb(60, 140, 240) },
			{ "green", "Green", "🟢", rgb(70, 200, 90) },
			{ "yellow", "Yellow", "🟡", rgb(255, 205, 40) },
		}),
	},
	TechCompany = {
		kind = "memory", action = "Debug the Code", emoji = "💻", length = 4,
		hint = "Watch the fix, then repeat it in the same order!",
		items = items({
			{ "bug", "Bug", "🐞", rgb(230, 70, 70) },
			{ "save", "Save", "💾", rgb(70, 130, 230) },
			{ "click", "Click", "🖱️", rgb(90, 200, 120) },
			{ "type", "Type", "⌨️", rgb(255, 190, 50) },
		}),
	},
}
MiniGames.Games = GAMES

function MiniGames.get(businessId: string): Game
	return GAMES[businessId] or GAMES.Supermarket
end

local lookup: { [Game]: { [string]: Item } } = {}
function MiniGames.item(game: Game, id: string): Item?
	local map = lookup[game]
	if not map then
		map = {}
		for _, item in game.items do
			map[item.id] = item
		end
		lookup[game] = map
	end
	return map[id]
end

local function shuffled(list: { string }, rng: Random): { string }
	local copy = table.clone(list)
	for i = #copy, 2, -1 do
		local j = rng:NextInteger(1, i)
		copy[i], copy[j] = copy[j], copy[i]
	end
	return copy
end

local function itemIds(game: Game): { string }
	local out = {}
	for _, item in game.items do
		table.insert(out, item.id)
	end
	return out
end

-- Server: a fresh random order for one round of the game.
function MiniGames.makeOrder(game: Game, rng: Random): Order
	local kind = game.kind
	if kind == "recipe" then
		local list = {}
		for _, step in game.steps or {} do
			if step.fixed then
				table.insert(list, step.fixed)
			elseif step.pool then
				local picks = shuffled(step.pool, rng)
				for i = 1, math.min(rng:NextInteger(step.min or 1, step.max or 1), #picks) do
					table.insert(list, picks[i])
				end
			end
		end
		return { kind = kind, list = list }
	elseif kind == "pick" then
		local picks = shuffled(itemIds(game), rng)
		local list = {}
		for i = 1, math.min(game.pick or 3, #picks) do
			table.insert(list, picks[i])
		end
		return { kind = kind, list = list }
	elseif kind == "cash" then
		return { kind = kind, target = rng:NextInteger(12, 199) }
	elseif kind == "timing" then
		local zones = {}
		for round = 1, game.rounds or 3 do
			local width = math.max(0.12, 0.24 - (round - 1) * 0.05)
			local sweep = math.max(0.7, 1.3 - (round - 1) * 0.2)
			table.insert(zones, { rng:NextNumber(0.2, 0.8), width, sweep })
		end
		return { kind = kind, zones = zones }
	end
	-- memory: never the same pad three times in a row
	local pads = itemIds(game)
	local list = {}
	for i = 1, game.length or 4 do
		local id = pads[rng:NextInteger(1, #pads)]
		while i > 2 and id == list[i - 1] and id == list[i - 2] do
			id = pads[rng:NextInteger(1, #pads)]
		end
		table.insert(list, id)
	end
	return { kind = "memory", list = list }
end

-- Server: is this answer right? Returns ok plus the hits for timing games.
-- recipe / memory: the exact sequence; pick: the same items in any order;
-- cash: real bills that add up to the target; timing: the number of hits.
function MiniGames.check(order: Order, answer: any): (boolean, number)
	local kind = order.kind
	if kind == "timing" then
		if type(answer) ~= "number" or answer ~= answer then
			return false, 0
		end
		return true, math.clamp(math.floor(answer), 0, #(order.zones or {}))
	end
	if type(answer) ~= "table" then
		return false, 0
	end
	if kind == "cash" then
		local count = #answer
		if count < 1 or count > MiniGames.MAX_BILLS then
			return false, 0
		end
		local total = 0
		for i = 1, count do
			local bill = answer[i]
			if type(bill) ~= "number" or not table.find(MiniGames.BILLS, bill) then
				return false, 0
			end
			total += bill
		end
		return total == order.target, 0
	end
	local list = order.list or {}
	if #answer ~= #list then
		return false, 0
	end
	if kind == "pick" then
		local seen = {}
		for i = 1, #answer do
			local id = answer[i]
			if type(id) ~= "string" or seen[id] or not table.find(list, id) then
				return false, 0
			end
			seen[id] = true
		end
		return true, 0
	end
	for i = 1, #list do
		if answer[i] ~= list[i] then
			return false, 0
		end
	end
	return true, 0
end

-- Server: the fastest a real player could finish (anything quicker is a script).
function MiniGames.minSeconds(order: Order, answer: any): number
	local kind = order.kind
	if kind == "timing" then
		return 0.3 * #(order.zones or {})
	elseif kind == "cash" then
		return 0.5 + 0.15 * (if type(answer) == "table" then #answer else 0)
	elseif kind == "memory" then
		return 0.6 * #(order.list or {}) -- the sequence has to be shown first
	end
	return 0.3 + 0.25 * #(order.list or {})
end

-- Index into GRADES: 1 PERFECT, 2 GREAT, 3 GOOD.
function MiniGames.grade(order: Order, mistakes: number, hits: number): number
	if order.kind == "timing" then
		local missed = #(order.zones or {}) - hits
		return if missed <= 0 then 1 elseif missed == 1 then 2 else 3
	end
	return if mistakes <= 0 then 1 elseif mistakes <= 2 then 2 else 3
end

local function joined(names: { string }): string
	if #names <= 1 then
		return names[1] or ""
	end
	return table.concat(names, ", ", 1, #names - 1) .. " and " .. names[#names]
end

-- What the customer at the till asks for (nil when the game has no customer line).
function MiniGames.describe(game: Game, order: Order): string?
	local line = game.line
	if not line then
		return nil
	end
	if order.kind == "cash" then
		return string.format(line, "$" .. tostring(order.target))
	end
	local skip = {}
	if order.kind == "recipe" then
		-- The base (dough, bun, cup...) goes without saying: name the extras.
		for _, step in game.steps or {} do
			if step.fixed then
				skip[step.fixed] = true
			end
		end
	end
	local names = {}
	for _, id in order.list or {} do
		local item = MiniGames.item(game, id)
		if item and not skip[id] then
			-- Recipes read as a sentence ("with peppers"); shopping lists keep the names.
			table.insert(names, if order.kind == "recipe" then string.lower(item.name) else item.name)
		end
	end
	return string.format(line, joined(names))
end

return MiniGames
