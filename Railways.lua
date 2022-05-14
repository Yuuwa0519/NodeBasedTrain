--!strict
-- Railways
-- Yuuwa0519
-- 2022-05-01

-- Services
local CollectionService = game:GetService("CollectionService")

-- Var
local railways: { [string]: { [string]: TrackNode } } = {}

local DEBUG = false

-- Funcs
local function collectNodes(railwayFolder: Folder)
	local railwayName: string = railwayFolder.Name

	local trackNodes: { [string]: TrackNode } = {}

	-- Register Nodes
	trackNodes["DEFAULT"] = {
		Id = "DEFAULT",
		TrackType = "Track" :: TrackType,
		Railway = railwayName,

		Position = Vector3.new(0, 1000000, 0),

		RootNodeId = nil,
		BranchNodeId = nil,
		NeighbourIds = {},

		Reference = nil,
	}

	for _, node: Folder in ipairs(railwayFolder:GetChildren()) do
		trackNodes[node:GetAttribute("NodeId")] = {
			Id = node:GetAttribute("NodeId") :: string,
			TrackType = "Track" :: TrackType,
			Railway = railwayName,

			Position = node:GetAttribute("NodePosition") :: Vector3,

			RootNodeId = nil,
			BranchNodeId = nil,
			NeighbourIds = {},

			Reference = node,
		}

		if DEBUG then
			local debugPart = Instance.new("Part")
			debugPart.Position = trackNodes[node:GetAttribute("NodeId")].Position
			debugPart.Size = Vector3.new(1, 1, 1)
			debugPart.Anchored = true
			debugPart.CanCollide = false
			debugPart.CanTouch = false
			debugPart.CanQuery = false
			debugPart.Color = Color3.new(0, 0.466666, 1)
			debugPart.Material = Enum.Material.Neon
			debugPart.Name = "RailDebugPart"
			debugPart.Parent = workspace
		end
	end

	-- Connect Nodes
	for thisNodeId, trackNode: TrackNode in pairs(trackNodes) do
		if trackNode.Reference then
			-- Also work on determining rail type
			local linksRaw: string = trackNode.Reference:GetAttribute("NodeLinks")
			local links: { string } = string.split(linksRaw, ",")

			for _, neighbourId: string in ipairs(links) do
				local neighbourNode: TrackNode = trackNodes[neighbourId]

				table.insert(trackNode.NeighbourIds, neighbourNode.Id)
				-- table.insert(neighbourNode.NeighbourIds, trackNode.Id)
			end
		else
			print("Lost Reference")
		end
	end

	for _, trackNode in pairs(trackNodes) do
		if #trackNode.NeighbourIds > 2 then
			--[[
				If the train comes from definite node, that means it can branch out into other nodes
				If the trian comes from node other than definite node, it will always branch out into the definite node
			]]

			local closestDist: number, closestNode: TrackNode? = math.huge, nil

			for _, neighbourNodeId: string in ipairs(trackNode.NeighbourIds) do
				local otherTrackNode = trackNodes[neighbourNodeId]

				local dist: number = (trackNode.Position - otherTrackNode.Position).Magnitude

				if dist < closestDist then
					closestDist = dist
					closestNode = otherTrackNode
				end
			end

			trackNode.TrackType = "SwitchTrack" :: TrackType
			trackNode.RootNodeId = closestNode.Id

			-- Also reorder the connecting node, from left to right
			local lookVector: Vector3 = (trackNode.Position - closestNode.Position).Unit
			local rightVector: Vector3 = lookVector:Cross(-Vector3.new(0, -1, 0))
			local upVector: Vector3 = lookVector:Cross(rightVector)
			local baseLookCFrame: CFrame = CFrame.fromMatrix(trackNode.Position, rightVector, upVector, lookVector)

			table.sort(trackNode.NeighbourIds, function(otherNodeAId: string, otherNodeBId: string)
				local otherNodeA: TrackNode = trackNodes[otherNodeAId]
				local otherNodeB: TrackNode = trackNodes[otherNodeBId]

				local leftnessOfNodeAFromBase: Vector3 = baseLookCFrame:PointToObjectSpace(otherNodeA.Position)
				local leftnessOfNodeBFromBase: Vector3 = baseLookCFrame:PointToObjectSpace(otherNodeB.Position)

				return leftnessOfNodeAFromBase.X < leftnessOfNodeBFromBase.X
			end)

			local rootNodeIndex: number? = table.find(trackNode.NeighbourIds, closestNode.Id)

			if rootNodeIndex then
				table.remove(trackNode.NeighbourIds, rootNodeIndex)
				table.insert(trackNode.NeighbourIds, 1, closestNode.Id)
			else
				warn("Root Node is Lost!")
			end

			for _, neighbourId: string in ipairs(trackNode.NeighbourIds) do
				local sameCount: number = 0
				for _, otherNeighbourId: string in ipairs(trackNode.NeighbourIds) do
					if neighbourId == otherNeighbourId then
						sameCount += 1
					end
				end

				if sameCount > 1 then
					print(trackNode.NeighbourIds)
					error("Duplicated Neighbour Id")
				end
			end

			trackNode.BranchNodeId = trackNode.NeighbourIds[2]

			print("Branch", trackNode.Id, trackNode.BranchNodeId)
		else
			-- Just assign random defininte node, its not important for non switchtrack tracks.
			trackNode.RootNodeId = trackNode.NeighbourIds[1]
		end

		if DEBUG then
			for _, neighbourNodeId: string in ipairs(trackNode.NeighbourIds) do
				local neighborNode: TrackNode = trackNodes[neighbourNodeId]

				local direction: Vector3 = (neighborNode.Position - trackNode.Position).Unit

				local debugPart = Instance.new("Part")
				debugPart.Position = trackNode.Position + direction * 0.7
				debugPart.Size = Vector3.new(0.1, 0.1, 0.1)
				debugPart.Anchored = true
				debugPart.CanCollide = false
				debugPart.CanTouch = false
				debugPart.CanQuery = false
				debugPart.Color = if trackNode.TrackType == "SwitchTrack"
						and trackNode.RootNodeId == neighbourNodeId
					then Color3.new(0.764705, 0, 1)
					else Color3.new(0.168627, 1, 0)
				debugPart.Material = Enum.Material.Neon
				debugPart.Name = "RailDebugPart"
				debugPart.Parent = workspace
			end
		end
	end

	railways[railwayFolder.Name] = trackNodes
end

-- Main
for _, trackFolder in ipairs(CollectionService:GetTagged("TrackComponent")) do
	collectNodes(trackFolder :: Folder)
end

export type TrackType = "Track" | "SwitchTrack"

export type TrackNode = {
	Id: string,
	TrackType: TrackType,
	Railway: string,

	Position: Vector3,

	RootNodeId: string,
	BranchNodeId: string?,
	NeighbourIds: { string },

	Reference: Folder,
}

return railways
