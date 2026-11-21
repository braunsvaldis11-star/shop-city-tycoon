--!strict
-- Icons (client): uploaded image icons made with Forge GUI.
-- Anything missing here falls back to the emoji in its definition, so icons can be
-- added one at a time: generate, upload, then paste the rbxassetid below.
-- Container: ReplicatedStorage.Client

local Icons = {}

Icons.Business = {
	Pizza = "rbxassetid://128791916674135",
	Bakery = "rbxassetid://137957152548560",
	Coffee = "rbxassetid://137092528024134",
	Bookstore = "rbxassetid://103005427698961",
	IceCream = "rbxassetid://86784801957056",
} :: { [string]: string }

-- Menu / HUD icons from the Check-UI icon registry (outlined cartoon style).
Icons.Menu = {
	Businesses = "rbxassetid://81391800986893", -- Golden_Shopping_Bag_1st_Outline
	Map = "rbxassetid://125727545883099", -- Location_Pin_1st_Outline
	Prestige = "rbxassetid://79642633995767", -- Rebirth_1st_Outline
	Achievements = "rbxassetid://85191169051998", -- Golden_Trophy_1st_Outline
	Settings = "rbxassetid://75107759162473", -- Settings_1_1st_Outline
	Store = "rbxassetid://103657634848918", -- Golden_Robux_1st_Outline
	Cash = "rbxassetid://88694661500877", -- Green_Cash_1st_Outline
	Population = "rbxassetid://84565274576236", -- Player_1st_Outline
	City = "rbxassetid://107107586946828", -- Blue_House_1st_Outline
	Lock = "rbxassetid://99673707827333", -- Lock_1st_Outline
	Star = "rbxassetid://105103627769338", -- Golden_Star_1st_Outline
	Check = "rbxassetid://75340450258025", -- Checkmark_1st_Outline
	Rocket = "rbxassetid://102027666188634", -- Rocket_1st_Outline
	Coin = "rbxassetid://71607982301142", -- Blue_Coin_1st_Outline
} :: { [string]: string }

function Icons.business(id: string): string?
	return Icons.Business[id]
end

function Icons.menu(id: string): string?
	return Icons.Menu[id]
end

return Icons
