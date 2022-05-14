--!strict
-- Bogie
-- Yuuwa0519
-- 2022-05-05

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Modules
local Packages = ReplicatedStorage:FindFirstChild("Packages")
local Trove = require(Packages.Trove)

local Railways = require(script.Parent.Railways)

-- Var
local DEBUG = false

-- Main
local Bogie = {}
Bogie.__index = Bogie

function Bogie.new()
	local self = setmetatable({}, Bogie)

	self.Position = Vector3.new()
	self.NextNodeId = 0
	self.PreviouNodeId = 0

	self.AssociatedBogies = {
		Previous = {
			Bogie = nil,
			Distance = nil,
		},
		Next = {
			Bogie = nil,
			Distance = nil,
		},
	}

	self.Trove = Trove.new()

	if DEBUG then
		self.DebugPart = self.Trove:Add(Instance.new("Part")) :: Part
		self.DebugPart.Size = Vector3.new(1, 1, 1)
		self.DebugPart.Anchored = true
		self.DebugPart.CanCollide = false
		self.DebugPart.CanTouch = false
		self.DebugPart.CanQuery = false
		self.DebugPart.Color = Color3.new(0.984313, 1, 0)
		self.DebugPart.Material = Enum.Material.Neon
		self.DebugPart.Name = "BogieDebugPart"
		self.DebugPart.Parent = workspace

		self.Trove:AttachToInstance(self.DebugPart)
	end

	return self
end

function Bogie:SetPosition(position: Vector3)
	self.Position = position

	if DEBUG then
		self.DebugPart.Position = self.Position
	end
end

function Bogie:SetNodes(previousNodeId: number, nextNodeId: number)
	self.PreviousNodeId = previousNodeId
	self.NextNodeId = nextNodeId
end

function Bogie:Destroy()
	self.Trove:Destroy()
end

type AssociatedBogie = {
	Bogie: Class?,
	Distance: number?,
}
export type Class = typeof(setmetatable(
	{} :: {
		Position: Vector3,
		NextNodeId: number,
		PreviousNodeId: number,
		AssociatedBogies: {
			Previous: AssociatedBogie,
			Next: AssociatedBogie,
		},
		DebugPart: Part?,
		Trove: any,
	},
	Bogie
))

return Bogie
