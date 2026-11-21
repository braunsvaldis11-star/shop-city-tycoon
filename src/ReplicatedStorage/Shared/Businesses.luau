--!strict
-- Businesses: reusable business templates.
-- Every business shares ONE upgrade system (Upgrades below). A template only supplies
-- numbers, colours, a lot in the city and the words used in its labels, so adding a
-- new business is a single table entry. Each business's own upgrade names (guest rooms
-- for the hotel, brick ovens for the pizzeria) live in UpgradeFlavor.
-- Container: ReplicatedStorage.Shared

local CityLayout = require(script.Parent.CityLayout)
local UpgradeFlavor = require(script.Parent.UpgradeFlavor)

local Businesses = {}

export type Upgrade = {
	id: string,
	category: string,
	max: number,
	costFactor: number, -- first level costs price * costFactor
	growth: number, -- each further level multiplies the cost
	emoji: string,
	levelReq: { number }?, -- optional business level needed for each upgrade level
	tiers: { string }?, -- optional visual tier names (index = level + 1)
	name: string, -- label template
	desc: string, -- description template (generic fallback)
	effect: string, -- what it does to the numbers, shown after every business's own flavour text
}

export type Words = {
	station: string,
	stations: string,
	worker: string,
	workers: string,
	product: string,
	products: string,
	table: string,
	tables: string,
	menu: string,
	area: string,
}

export type Definition = {
	id: string,
	name: string,
	emoji: string,
	order: number,
	district: string,
	price: number,
	base: { customers: number, spend: number, serve: number, produce: number },
	stationStyle: string, -- which prop InteriorBuilder uses for production stations
	productStyle: string, -- what customers carry out
	words: Words,
	theme: { primary: Color3, secondary: Color3, accent: Color3, roof: Color3 },
	lot: { position: Vector3, yaw: number, size: Vector3 },
	roofStyle: string?, -- landmark prop on the roof (defaults to stationStyle)
	entryFee: boolean?, -- attractions: visitors pay at the door instead of buying something to take away
}

----- Upgrade categories (tab order in the Manage menu) -----
Businesses.Categories = {
	{ id = "Kitchen", name = "Production", emoji = "🔥" },
	{ id = "Employees", name = "Employees", emoji = "👥" },
	{ id = "Dining", name = "Seating", emoji = "🪑" },
	{ id = "Decoration", name = "Decoration", emoji = "🎨" },
	{ id = "Marketing", name = "Marketing", emoji = "📣" },
}

----- Shared upgrade list -----
Businesses.Upgrades = {
	-- Production
	{ id = "equipment", category = "Kitchen", max = 4, costFactor = 0.05, growth = 2.2, emoji = "⭐",
		tiers = { "Basic", "Stone", "Deluxe", "Turbo", "Golden" },
		name = "Better {stations}", desc = "Upgraded {stations} make {products} faster.", effect = "+35% production." },
	{ id = "stations", category = "Kitchen", max = 4, costFactor = 0.08, growth = 1.9, emoji = "➕",
		name = "Extra {stations}", desc = "Installs another {station}.", effect = "+1 production line." },
	{ id = "prep", category = "Kitchen", max = 3, costFactor = 0.04, growth = 1.9, emoji = "🔪",
		name = "Prep Stations", desc = "Extra preparation counters.", effect = "+15% production." },
	-- Employees
	{ id = "cashiers", category = "Employees", max = 3, costFactor = 0.06, growth = 2.0, emoji = "💵",
		name = "Hire Cashier", desc = "Opens another register.", effect = "+1 service line." },
	{ id = "workers", category = "Employees", max = 4, costFactor = 0.05, growth = 1.9, emoji = "🧑‍🍳",
		name = "Hire {worker}", desc = "A new {worker} joins the team.", effect = "+20% production." },
	{ id = "cleaners", category = "Employees", max = 2, costFactor = 0.04, growth = 2.2, emoji = "🧹",
		name = "Hire Cleaner", desc = "Keeps the place spotless.", effect = "+Reputation." },
	{ id = "training", category = "Employees", max = 5, costFactor = 0.04, growth = 1.8, emoji = "⚡",
		name = "Staff Training", desc = "Every employee works faster.", effect = "+20% service speed." },
	-- Seating / capacity
	{ id = "tables", category = "Dining", max = 6, costFactor = 0.03, growth = 1.55, emoji = "🍽️",
		name = "More {tables}", desc = "Adds another {table} with seats.", effect = "+8 customer capacity." },
	{ id = "seating", category = "Dining", max = 3, costFactor = 0.05, growth = 2.0, emoji = "🛋️",
		tiers = { "Plastic Chairs", "Wooden Chairs", "Cushioned Chairs", "Velvet Booths" },
		name = "Better Chairs", desc = "Comfy customers spend more.", effect = "+10% spending." },
	-- Decoration
	{ id = "floor", category = "Decoration", max = 3, costFactor = 0.03, growth = 2.2, emoji = "🟫",
		tiers = { "Plain Tiles", "Checkered Tiles", "Polished Wood", "Marble" },
		name = "Floor Style", desc = "A nicer floor.", effect = "+3% spending, +Reputation." },
	{ id = "walls", category = "Decoration", max = 3, costFactor = 0.03, growth = 2.2, emoji = "🧱",
		tiers = { "Plain Paint", "Brick", "Wood Panels", "Luxury Wallpaper" },
		name = "Wall Style", desc = "Fresh walls.", effect = "+3% spending, +Reputation." },
	{ id = "lighting", category = "Decoration", max = 3, costFactor = 0.035, growth = 2.1, emoji = "💡",
		tiers = { "Basic Bulbs", "Pendant Lamps", "Warm Glow", "Neon Signs" },
		name = "Lighting", desc = "Better lights, better mood.", effect = "+3% spending, +Reputation." },
	{ id = "furniture", category = "Decoration", max = 3, costFactor = 0.04, growth = 2.0, emoji = "🪴",
		tiers = { "Bare", "Potted Plants", "Art & Decor", "Lounge Corner" },
		name = "Furniture & Plants", desc = "Plants, art and cosy corners.", effect = "+3% spending, +Reputation." },
	{ id = "premium", category = "Decoration", max = 2, costFactor = 0.5, growth = 3.0, emoji = "💎",
		levelReq = { 4, 7 }, tiers = { "None", "Golden Statue", "Grand Fountain" },
		name = "Premium Décor", desc = "A show-stopping centerpiece.", effect = "Big reputation boost." },
	-- Marketing
	{ id = "ads", category = "Marketing", max = 5, costFactor = 0.04, growth = 1.85, emoji = "📰",
		name = "Flyers & Ads", desc = "Spread the word.", effect = "+25% customers." },
	{ id = "reputation", category = "Marketing", max = 5, costFactor = 0.05, growth = 1.9, emoji = "⭐",
		name = "Online Reviews", desc = "Great reviews.", effect = "+Reputation, more customers." },
	{ id = "pricing", category = "Marketing", max = 5, costFactor = 0.06, growth = 2.0, emoji = "💰",
		name = "Gourmet {menu}", desc = "Premium {products}.", effect = "+20% spending per customer." },
} :: { Upgrade }

local upgradeById: { [string]: Upgrade } = {}
for _, upgrade in Businesses.Upgrades do
	upgradeById[upgrade.id] = upgrade
end

----- Business templates -----
local function words(station, stations, worker, workers, product, products, tableWord, tablesWord, menu, area): Words
	return {
		station = station, stations = stations, worker = worker, workers = workers,
		product = product, products = products, table = tableWord, tables = tablesWord,
		menu = menu, area = area,
	}
end

local function base()
	-- Same customer/service/production shape for every business. Spending per customer is
	-- filled in below, once the list is in price order.
	return { customers = 12, spend = 0, serve = 8, produce = 8 }
end

-- Balance: a customer spends BASE_SPEND_RATE of the business's price, and every later
-- business a bit less (SPEND_DECAY per step up the ladder). So each new business pays
-- back more slowly than the one before it: early shops come quickly, the big ones are
-- long-term goals, and income never snowballs past the prices.
local BASE_SPEND_RATE = 0.03
local SPEND_DECAY = 0.78

Businesses.List = {
	{
		id = "Pizza", name = "Pizza Restaurant", emoji = "🍕", order = 1, district = "Starter", price = 1_000,
		base = base(), stationStyle = "oven", productStyle = "pizza",
		words = words("Oven", "Ovens", "Cook", "Cooks", "Pizza", "Pizzas", "Table", "Tables", "Menu", "Kitchen"),
		theme = { primary = Color3.fromRGB(230, 70, 60), secondary = Color3.fromRGB(255, 240, 215), accent = Color3.fromRGB(70, 170, 80), roof = Color3.fromRGB(180, 50, 45) },
		lot = { position = Vector3.new(0, 0, 122), yaw = 0, size = Vector3.new(56, 26, 44) },
	},
	{
		id = "Coffee", name = "Coffee Shop", emoji = "☕", order = 3, district = "Starter", price = 6_000,
		base = base(), stationStyle = "espresso", productStyle = "cup",
		words = words("Espresso Machine", "Espresso Machines", "Barista", "Baristas", "Coffee", "Coffees", "Table", "Tables", "Roasts", "Coffee Bar"),
		theme = { primary = Color3.fromRGB(140, 90, 60), secondary = Color3.fromRGB(245, 225, 200), accent = Color3.fromRGB(90, 60, 40), roof = Color3.fromRGB(100, 65, 45) },
		lot = { position = Vector3.new(-122, 0, 0), yaw = -90, size = Vector3.new(44, 22, 40) },
	},
	{
		id = "Clothing", name = "Clothing Store", emoji = "👕", order = 6, district = "Starter", price = 60_000,
		base = base(), stationStyle = "rack", productStyle = "bag",
		words = words("Clothing Rack", "Clothing Racks", "Stylist", "Stylists", "Outfit", "Outfits", "Fitting Room", "Fitting Rooms", "Collection", "Showroom"),
		theme = { primary = Color3.fromRGB(255, 120, 180), secondary = Color3.fromRGB(255, 235, 245), accent = Color3.fromRGB(120, 80, 200), roof = Color3.fromRGB(200, 80, 140) },
		lot = { position = Vector3.new(124, 0, 0), yaw = 90, size = Vector3.new(48, 24, 44) },
	},
	{
		id = "Supermarket", name = "Supermarket", emoji = "🛒", order = 9, district = "Starter", price = 350_000,
		base = base(), stationStyle = "shelf", productStyle = "bag",
		words = words("Shelf", "Shelves", "Stocker", "Stockers", "Grocery", "Groceries", "Snack Bar", "Snack Bars", "Selection", "Aisles"),
		theme = { primary = Color3.fromRGB(240, 60, 60), secondary = Color3.fromRGB(250, 250, 245), accent = Color3.fromRGB(60, 160, 230), roof = Color3.fromRGB(60, 140, 220) },
		lot = { position = Vector3.new(0, 0, -124), yaw = 180, size = Vector3.new(70, 24, 48) },
	},
	{
		id = "Gym", name = "Gym", emoji = "🏋️", order = 13, district = "Downtown", price = 2_500_000,
		base = base(), stationStyle = "treadmill", productStyle = "bottle",
		words = words("Treadmill", "Treadmills", "Trainer", "Trainers", "Workout", "Workouts", "Bench", "Benches", "Memberships", "Gym Floor"),
		theme = { primary = Color3.fromRGB(130, 80, 230), secondary = Color3.fromRGB(60, 60, 75), accent = Color3.fromRGB(80, 230, 255), roof = Color3.fromRGB(70, 60, 110) },
		lot = { position = Vector3.new(-136, 0, -300), yaw = -90, size = Vector3.new(60, 28, 50) },
	},
	{
		id = "CarDealership", name = "Car Dealership", emoji = "🚗", order = 17, district = "Downtown", price = 14_000_000,
		base = base(), stationStyle = "car", productStyle = "key",
		words = words("Showroom Car", "Showroom Cars", "Salesperson", "Salespeople", "Car", "Cars", "Lounge Table", "Lounge Tables", "Models", "Showroom"),
		theme = { primary = Color3.fromRGB(40, 120, 220), secondary = Color3.fromRGB(235, 240, 250), accent = Color3.fromRGB(255, 200, 40), roof = Color3.fromRGB(40, 60, 100) },
		lot = { position = Vector3.new(10, 0, -300), yaw = 90, size = Vector3.new(80, 24, 56) },
	},
	{
		id = "Hotel", name = "Hotel", emoji = "🏨", order = 21, district = "Uptown", price = 72_000_000,
		base = base(), stationStyle = "desk", productStyle = "key",
		words = words("Reception Desk", "Reception Desks", "Concierge", "Concierges", "Stay", "Stays", "Lounge Table", "Lounge Tables", "Suites", "Lobby"),
		theme = { primary = Color3.fromRGB(200, 160, 70), secondary = Color3.fromRGB(250, 245, 230), accent = Color3.fromRGB(150, 40, 60), roof = Color3.fromRGB(120, 30, 50) },
		lot = { position = Vector3.new(300, 0, 140), yaw = 0, size = Vector3.new(80, 70, 50) },
	},
	{
		id = "Mall", name = "Shopping Mall", emoji = "🏬", order = 24, district = "Uptown", price = 250_000_000,
		base = base(), stationStyle = "kiosk", productStyle = "bag",
		words = words("Store Kiosk", "Store Kiosks", "Shop Assistant", "Shop Assistants", "Purchase", "Purchases", "Food Court Table", "Food Court Tables", "Brands", "Stores"),
		theme = { primary = Color3.fromRGB(40, 200, 170), secondary = Color3.fromRGB(240, 250, 250), accent = Color3.fromRGB(255, 120, 60), roof = Color3.fromRGB(30, 150, 130) },
		lot = { position = Vector3.new(300, 0, 0), yaw = 180, size = Vector3.new(110, 40, 70) },
	},
	-- Old Town: Main Street neighbours of the pizza place
	{
		id = "Bakery", name = "Bakery", emoji = "🥐", order = 2, district = "Starter", price = 2_500,
		base = base(), stationStyle = "oven", productStyle = "box", roofStyle = "cake",
		words = words("Bread Oven", "Bread Ovens", "Baker", "Bakers", "Pastry", "Pastries", "Café Table", "Café Tables", "Recipes", "Bakehouse"),
		theme = { primary = Color3.fromRGB(245, 165, 70), secondary = Color3.fromRGB(255, 245, 225), accent = Color3.fromRGB(190, 105, 60), roof = Color3.fromRGB(185, 115, 60) },
		lot = { position = Vector3.new(-141, 0, 118), yaw = 0, size = Vector3.new(40, 20, 36) },
	},
	{
		id = "IceCream", name = "Ice Cream Parlor", emoji = "🍦", order = 5, district = "Starter", price = 30_000,
		base = base(), stationStyle = "freezer", productStyle = "cone", roofStyle = "cone",
		words = words("Ice Cream Freezer", "Ice Cream Freezers", "Scooper", "Scoopers", "Ice Cream", "Ice Creams", "Booth", "Booths", "Flavors", "Parlor"),
		theme = { primary = Color3.fromRGB(255, 130, 185), secondary = Color3.fromRGB(255, 250, 240), accent = Color3.fromRGB(100, 210, 230), roof = Color3.fromRGB(235, 100, 155) },
		lot = { position = Vector3.new(141, 0, 118), yaw = 0, size = Vector3.new(40, 20, 36) },
	},
	-- Maple Hills
	{
		id = "PetShop", name = "Pet Shop", emoji = "🐶", order = 10, district = "Maple", price = 600_000,
		base = base(), stationStyle = "shelf", productStyle = "bag", roofStyle = "bone",
		words = words("Supply Shelf", "Supply Shelves", "Pet Groomer", "Pet Groomers", "Pet Treat", "Pet Treats", "Play Pen", "Play Pens", "Pet Food", "Pet Center"),
		theme = { primary = Color3.fromRGB(80, 175, 240), secondary = Color3.fromRGB(250, 245, 230), accent = Color3.fromRGB(250, 190, 60), roof = Color3.fromRGB(55, 125, 200) },
		lot = { position = Vector3.new(-130, 0, 300), yaw = -90, size = Vector3.new(44, 22, 40) },
	},
	{
		id = "Burger", name = "Burger Diner", emoji = "🍔", order = 12, district = "Maple", price = 1_600_000,
		base = base(), stationStyle = "grill", productStyle = "box", roofStyle = "burger",
		words = words("Grill", "Grills", "Line Cook", "Line Cooks", "Burger", "Burgers", "Booth", "Booths", "Combos", "Grill Line"),
		theme = { primary = Color3.fromRGB(240, 185, 45), secondary = Color3.fromRGB(255, 250, 240), accent = Color3.fromRGB(220, 60, 50), roof = Color3.fromRGB(200, 50, 45) },
		lot = { position = Vector3.new(130, 0, 300), yaw = 90, size = Vector3.new(48, 20, 40) },
	},
	-- Downtown
	{
		id = "Electronics", name = "Electronics Store", emoji = "📱", order = 15, district = "Downtown", price = 6_000_000,
		base = base(), stationStyle = "screen", productStyle = "box", roofStyle = "phone",
		words = words("Display Stand", "Display Stands", "Tech Expert", "Tech Experts", "Gadget", "Gadgets", "Demo Table", "Demo Tables", "Brands", "Sales Floor"),
		theme = { primary = Color3.fromRGB(55, 195, 255), secondary = Color3.fromRGB(235, 240, 250), accent = Color3.fromRGB(255, 85, 160), roof = Color3.fromRGB(40, 60, 95) },
		lot = { position = Vector3.new(130, 0, -300), yaw = 90, size = Vector3.new(56, 28, 44) },
	},
	-- Harbor Bay
	{
		id = "Seafood", name = "Seafood Restaurant", emoji = "🦞", order = 18, district = "Harbor", price = 21_000_000,
		base = base(), stationStyle = "grill", productStyle = "box", roofStyle = "fish",
		words = words("Seafood Grill", "Seafood Grills", "Chef", "Chefs", "Dish", "Dishes", "Table", "Tables", "Catch of the Day", "Kitchen"),
		theme = { primary = Color3.fromRGB(40, 140, 205), secondary = Color3.fromRGB(250, 245, 230), accent = Color3.fromRGB(240, 95, 60), roof = Color3.fromRGB(30, 100, 160) },
		lot = { position = Vector3.new(-300, 0, 118), yaw = 0, size = Vector3.new(60, 22, 40) },
	},
	{
		id = "Aquarium", name = "Aquarium", emoji = "🐠", order = 20, district = "Harbor", price = 48_000_000,
		base = base(), stationStyle = "tank", productStyle = "bag", roofStyle = "aquadome",
		words = words("Fish Tank", "Fish Tanks", "Marine Keeper", "Marine Keepers", "Ticket", "Tickets", "Viewing Bench", "Viewing Benches", "Exhibits", "Exhibit Hall"),
		theme = { primary = Color3.fromRGB(35, 185, 220), secondary = Color3.fromRGB(230, 248, 255), accent = Color3.fromRGB(255, 200, 60), roof = Color3.fromRGB(20, 115, 165) },
		lot = { position = Vector3.new(-300, 0, -124), yaw = 180, size = Vector3.new(80, 32, 50) },
	},
	-- Financial District
	{
		id = "TechCompany", name = "Tech Company", emoji = "💻", order = 25, district = "Financial", price = 375_000_000,
		base = base(), stationStyle = "screen", productStyle = "box", roofStyle = "satellite",
		words = words("Server Rack", "Server Racks", "Engineer", "Engineers", "App", "Apps", "Desk Pod", "Desk Pods", "Products", "Data Center"),
		theme = { primary = Color3.fromRGB(115, 90, 240), secondary = Color3.fromRGB(235, 235, 250), accent = Color3.fromRGB(60, 230, 180), roof = Color3.fromRGB(60, 50, 140) },
		lot = { position = Vector3.new(300, 0, -300), yaw = -90, size = Vector3.new(80, 90, 60) },
	},
	-- Arts Quarter
	{
		id = "Bookstore", name = "Bookstore", emoji = "📚", order = 4, district = "Arts", price = 14_000,
		base = base(), stationStyle = "shelf", productStyle = "bag", roofStyle = "book",
		words = words("Bookshelf", "Bookshelves", "Bookseller", "Booksellers", "Book", "Books", "Reading Table", "Reading Tables", "Catalog", "Library"),
		theme = { primary = Color3.fromRGB(70, 120, 200), secondary = Color3.fromRGB(250, 245, 230), accent = Color3.fromRGB(230, 170, 60), roof = Color3.fromRGB(50, 80, 150) },
		lot = { position = Vector3.new(703, 0, 255), yaw = 0, size = Vector3.new(44, 22, 38) },
	},
	{
		id = "Cinema", name = "Cinema", emoji = "🎬", order = 19, district = "Arts", price = 32_000_000,
		base = base(), stationStyle = "screen", productStyle = "cup", roofStyle = "popcorn",
		words = words("Projector", "Projectors", "Usher", "Ushers", "Ticket", "Tickets", "Seat Row", "Seat Rows", "Movies", "Theater"),
		theme = { primary = Color3.fromRGB(200, 40, 50), secondary = Color3.fromRGB(250, 240, 225), accent = Color3.fromRGB(255, 200, 60), roof = Color3.fromRGB(120, 25, 35) },
		lot = { position = Vector3.new(855, 0, 303), yaw = 90, size = Vector3.new(70, 34, 50) },
	},
	-- Seaside Village
	{
		id = "SurfShop", name = "Surf Shop", emoji = "🏄", order = 7, district = "Seaside", price = 110_000,
		base = base(), stationStyle = "rack", productStyle = "bag", roofStyle = "surfboard",
		words = words("Board Rack", "Board Racks", "Surf Instructor", "Surf Instructors", "Surfboard", "Surfboards", "Bench", "Benches", "Gear", "Surf Shop"),
		theme = { primary = Color3.fromRGB(40, 190, 210), secondary = Color3.fromRGB(255, 245, 215), accent = Color3.fromRGB(255, 140, 60), roof = Color3.fromRGB(30, 140, 170) },
		lot = { position = Vector3.new(-303, 0, 255), yaw = 0, size = Vector3.new(44, 20, 38) },
	},
	{
		id = "Sushi", name = "Sushi Bar", emoji = "🍣", order = 14, district = "Seaside", price = 4_000_000,
		base = base(), stationStyle = "grill", productStyle = "box", roofStyle = "sushi",
		words = words("Sushi Counter", "Sushi Counters", "Sushi Chef", "Sushi Chefs", "Roll", "Rolls", "Table", "Tables", "Omakase", "Sushi Bar"),
		theme = { primary = Color3.fromRGB(220, 60, 60), secondary = Color3.fromRGB(250, 245, 235), accent = Color3.fromRGB(40, 40, 45), roof = Color3.fromRGB(170, 40, 40) },
		lot = { position = Vector3.new(-303, 0, 449), yaw = 0, size = Vector3.new(44, 22, 38) },
	},
	-- The Dockyards
	{
		id = "FishMarket", name = "Fish Market", emoji = "🐟", order = 11, district = "Dockyards", price = 1_000_000,
		base = base(), stationStyle = "freezer", productStyle = "bag", roofStyle = "fish",
		words = words("Ice Counter", "Ice Counters", "Fishmonger", "Fishmongers", "Fish", "Fish", "Tasting Table", "Tasting Tables", "Daily Catch", "Market Hall"),
		theme = { primary = Color3.fromRGB(70, 150, 200), secondary = Color3.fromRGB(240, 245, 250), accent = Color3.fromRGB(250, 120, 80), roof = Color3.fromRGB(50, 90, 130) },
		lot = { position = Vector3.new(-303, 0, -256), yaw = 180, size = Vector3.new(52, 20, 40) },
	},
	-- Sunset Hills
	{
		id = "Spa", name = "Day Spa", emoji = "💆", order = 22, district = "Sunset", price = 110_000_000,
		base = base(), stationStyle = "desk", productStyle = "bottle", roofStyle = "spa",
		words = words("Treatment Bed", "Treatment Beds", "Therapist", "Therapists", "Treatment", "Treatments", "Lounge Chair", "Lounge Chairs", "Rituals", "Spa Floor"),
		theme = { primary = Color3.fromRGB(120, 200, 170), secondary = Color3.fromRGB(250, 250, 245), accent = Color3.fromRGB(230, 150, 190), roof = Color3.fromRGB(70, 150, 120) },
		lot = { position = Vector3.new(303, 0, 258), yaw = 0, size = Vector3.new(60, 24, 44) },
	},
	{
		id = "Jewelry", name = "Jewelry Boutique", emoji = "💍", order = 23, district = "Sunset", price = 165_000_000,
		base = base(), stationStyle = "desk", productStyle = "bag", roofStyle = "diamond",
		words = words("Display Case", "Display Cases", "Jeweler", "Jewelers", "Ring", "Rings", "Viewing Table", "Viewing Tables", "Collection", "Boutique"),
		theme = { primary = Color3.fromRGB(60, 60, 80), secondary = Color3.fromRGB(245, 245, 250), accent = Color3.fromRGB(120, 220, 255), roof = Color3.fromRGB(40, 40, 60) },
		lot = { position = Vector3.new(503, 0, 255), yaw = 0, size = Vector3.new(48, 24, 38) },
	},
	-- Funland
	{
		id = "ToyStore", name = "Toy Store", emoji = "🧸", order = 8, district = "Funland", price = 200_000,
		base = base(), stationStyle = "shelf", productStyle = "box", roofStyle = "toy",
		words = words("Toy Shelf", "Toy Shelves", "Toy Expert", "Toy Experts", "Toy", "Toys", "Play Table", "Play Tables", "Toy Lines", "Toy Floor"),
		theme = { primary = Color3.fromRGB(255, 90, 90), secondary = Color3.fromRGB(255, 250, 235), accent = Color3.fromRGB(70, 160, 255), roof = Color3.fromRGB(240, 190, 40) },
		lot = { position = Vector3.new(703, 0, 120), yaw = 0, size = Vector3.new(48, 22, 40) },
	},
	{
		id = "Arcade", name = "Arcade", emoji = "🕹️", order = 16, district = "Funland", price = 9_000_000,
		base = base(), stationStyle = "screen", productStyle = "box", roofStyle = "joystick",
		words = words("Arcade Cabinet", "Arcade Cabinets", "Game Host", "Game Hosts", "Token", "Tokens", "Prize Counter", "Prize Counters", "Games", "Game Floor"),
		theme = { primary = Color3.fromRGB(140, 60, 230), secondary = Color3.fromRGB(40, 35, 60), accent = Color3.fromRGB(60, 240, 200), roof = Color3.fromRGB(90, 40, 160) },
		lot = { position = Vector3.new(703, 0, 18), yaw = 180, size = Vector3.new(60, 26, 44) },
	},
	-- Business Park
	{
		id = "Bank", name = "City Bank", emoji = "🏦", order = 26, district = "BizPark", price = 560_000_000,
		base = base(), stationStyle = "desk", productStyle = "key", roofStyle = "coin",
		words = words("Teller Desk", "Teller Desks", "Banker", "Bankers", "Account", "Accounts", "Waiting Bench", "Waiting Benches", "Services", "Banking Hall"),
		theme = { primary = Color3.fromRGB(40, 140, 90), secondary = Color3.fromRGB(245, 245, 235), accent = Color3.fromRGB(240, 200, 70), roof = Color3.fromRGB(30, 90, 60) },
		lot = { position = Vector3.new(703, 0, -264), yaw = 180, size = Vector3.new(80, 50, 56) },
	},
} :: { Definition }

-- Lots above are in plan units, like CityLayout: scale positions and buildings to studs.
for _, definition in Businesses.List do
	local lot = definition.lot
	lot.position = Vector3.new(lot.position.X * CityLayout.SCALE, 0, lot.position.Z * CityLayout.SCALE)
	lot.size *= CityLayout.SCALE
end

-- Keep the list in price/unlock order for every menu that iterates it.
table.sort(Businesses.List, function(a, b)
	return a.order < b.order
end)

for index, definition in Businesses.List do
	definition.base.spend = definition.price * BASE_SPEND_RATE * SPEND_DECAY ^ (index - 1)
end

-- Attractions charge an entry fee as visitors walk in. Every other business sells
-- something that customers carry out, and they pay on the way out.
local ENTRY_FEE = { Gym = true, Arcade = true, Cinema = true, Aquarium = true, Spa = true, Hotel = true }
for _, definition in Businesses.List do
	(definition :: any).entryFee = ENTRY_FEE[definition.id] == true
end

local byId: { [string]: Definition } = {}
for _, definition in Businesses.List do
	byId[definition.id] = definition
end

function Businesses.get(id: string): Definition?
	return byId[id]
end

function Businesses.getUpgrade(id: string): Upgrade?
	return upgradeById[id]
end

-- Replace {station}, {workers} ... placeholders with the business's own words.
function Businesses.label(definition: Definition, template: string): string
	return (template:gsub("{(%w+)}", function(key: string)
		return (definition.words :: any)[key] or key
	end))
end

-- What the Manage menu shows for one upgrade at this business: its own name, flavour
-- text (with the real effect added), emoji and tier names. Falls back to the shared
-- wording for upgrades a business has no flavour for (cleaners, decor, reviews ...).
function Businesses.upgradeText(definition: Definition, upgrade: Upgrade): (string, string, string, { string }?)
	local flavor = UpgradeFlavor[definition.id]
	local entry = flavor and flavor[upgrade.id]
	if entry then
		return entry[1], entry[2] .. " " .. upgrade.effect, entry[3] or upgrade.emoji, entry[4] or upgrade.tiers
	end
	local name = Businesses.label(definition, upgrade.name)
	local desc = Businesses.label(definition, upgrade.desc) .. " " .. upgrade.effect
	return name, desc, upgrade.emoji, upgrade.tiers
end

function Businesses.categoryName(definition: Definition, categoryId: string): string
	if categoryId == "Kitchen" then
		return definition.words.area
	end
	local flavor = UpgradeFlavor[definition.id]
	if flavor and flavor[categoryId] then
		return flavor[categoryId]
	end
	for _, category in Businesses.Categories do
		if category.id == categoryId then
			return category.name
		end
	end
	return categoryId
end

return Businesses
