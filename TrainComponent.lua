--!strict
-- TrainComponent
-- Yuuwa0519
-- 2022-05-01

-- Services
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Modules
local Packages = ReplicatedStorage:WaitForChild("Packages")

local Component = require(Packages.Component)
local Trove = require(Packages.Trove)
local TableUtil = require(Packages.TableUtil)

local Railways = require(script.Parent.Railways)
local Bogie = require(script.Parent.Bogie)

-- Main
local TrainComponent = Component.new({
	Tag = "TrainComponent",
})

function TrainComponent:Construct()
	self.Acceleration = 1
	self.Deceleration = 0
	self.Velocity = 0

	self.CarDistance = 3
	self.VerticalOffset = 4
	self.MaxVelocity = 50

	self.VirtualTrack = {}
	self.VirtualIds = 0
	self.VirtualIdNodeIndex = {}

	self.TrainCars = {}
	self.Bogies = {}
	self.TrainLength = 0

	self.PreferredTrack = 0

	self.TrainReady = false
	self.TrainConfigured = false
	self.TrainConfigs = {}

	self.Processing = false
	self.LastUpdate = time()

	self.Trove = Trove.new()
end

function TrainComponent:GetRailwayNodes()
	local railwayName: string = self.TrainConfigs.Railway

	if not Railways[railwayName] then
		repeat
			task.wait()
		until Railways[railwayName]
	end

	return Railways[railwayName]
end

function TrainComponent:FindClosestNode(position: Vector3): (Railways.TrackNode | nil)
	local closestDist: number, closestNode: Railways.TrackNode? = math.huge, nil

	for _, node: Railways.TrackNode in pairs(self:GetRailwayNodes()) do
		local dist = (position - node.Position).Magnitude

		if dist < closestDist then
			closestDist = dist
			closestNode = node
		end
	end

	return closestNode
end

function TrainComponent:RegisterTrainConfigs(trainConfigs: TrainCongifs)
	self.TrainConfigs = trainConfigs

	local closestFront: Railways.TrackNode = self:FindClosestNode(self.TrainConfigs.Spawn.Front)
	local potentialPreviousNodeId: string
	do
		local backPosition: Vector3 = self.TrainConfigs.Spawn.Back

		local closestDist: number, closestNodeId: string = math.huge, nil
		for _, neighbourId: string in ipairs(closestFront.NeighbourIds) do
			local corresNode: Railways.TrackNode = self:GetRailwayNodes()[neighbourId]
			local dist = (backPosition - corresNode.Position).Magnitude

			if dist < closestDist then
				closestDist = dist
				closestNodeId = corresNode.Id
			end
		end

		potentialPreviousNodeId = closestNodeId
	end

	self:AddVirtualNode(closestFront.Id, false)
	self:AddVirtualNode(potentialPreviousNodeId, false)

	for i: number, trainCar: Model in ipairs(trainConfigs.Cars) do
		-- Setup
		for _, part: BasePart in ipairs(trainCar:GetDescendants()) do
			if part:IsA("BasePart") then
				if part ~= trainCar.PrimaryPart then
					local weldConstraint = Instance.new("WeldConstraint")
					weldConstraint.Part0 = part
					weldConstraint.Part1 = trainCar.PrimaryPart
					weldConstraint.Parent = trainCar.PrimaryPart

					part.Anchored = false
				end

				part.Massless = true
				PhysicsService:SetPartCollisionGroup(part, "Train")
			end
		end

		local attachment0 = Instance.new("Attachment")
		local alignPosition, alignOrientation = Instance.new("AlignPosition"), Instance.new("AlignOrientation")

		attachment0.Parent = trainCar.PrimaryPart

		alignPosition.Attachment0 = attachment0
		alignPosition.Mode = Enum.PositionAlignmentMode.OneAttachment
		alignPosition.RigidityEnabled = true
		alignPosition.ApplyAtCenterOfMass = true

		alignOrientation.Attachment0 = attachment0
		alignOrientation.Mode = Enum.OrientationAlignmentMode.OneAttachment
		alignOrientation.RigidityEnabled = true

		alignPosition.Position = trainCar.PrimaryPart.Position
		alignOrientation.CFrame = trainCar:GetPivot()

		alignPosition.Parent = trainCar.PrimaryPart
		alignOrientation.Parent = trainCar.PrimaryPart

		trainCar.PrimaryPart.Anchored = false
		trainCar.PrimaryPart.Name = "TrainPlatform"
		for _, part: BasePart in ipairs(trainCar:GetDescendants()) do
			if part:IsA("BasePart") then
				part:SetNetworkOwner(nil)
			end
		end

		table.insert(self.TrainCars, {
			Car = trainCar,
			AlignPosition = alignPosition,
			AlignOrientation = alignOrientation,
		})

		-- FrontBogie
		if i == 1 then
			local newBogie = Bogie.new()

			newBogie:SetNodes(self.VirtualTrack[2], self.VirtualTrack[1])
			newBogie:SetPosition(
				self:GetRailwayNodes()[self:GetNodeFromVirtualId(newBogie.NextNodeId)].Position + Vector3.new(0, 1, 0)
			)

			if newBogie.DebugPart then
				newBogie.DebugPart.Color = Color3.new(1, 0, 0)
			end

			table.insert(self.Bogies, newBogie)
		else
			local distFromBogieToEdgePrevious: number
			do
				local previousCar = self.TrainCars[i - 1].Car
				local previousCarBase = previousCar.PrimaryPart :: BasePart
				local previousBogie = previousCar:FindFirstChild("BogieBack") :: BasePart

				local displacementOfBogie = previousCarBase.CFrame:ToObjectSpace(previousBogie.CFrame)
				distFromBogieToEdgePrevious = previousCarBase.Size.Z / 2 - math.abs(displacementOfBogie.Z)
			end

			local distFromBogieToEdgeThis: number
			do
				local thisCar = self.TrainCars[i].Car
				local thisCarBase = thisCar.PrimaryPart :: BasePart
				local thisBogie = thisCar:FindFirstChild("BogieFront") :: BasePart

				local displacementOfBogie = thisCarBase.CFrame:ToObjectSpace(thisBogie.CFrame)
				distFromBogieToEdgeThis = thisCarBase.Size.Z / 2 - math.abs(displacementOfBogie.Z)
			end

			local newBogie = Bogie.new()
			newBogie:SetNodes(self.VirtualTrack[2], self.VirtualTrack[1])

			newBogie.AssociatedBogies.Previous = {
				Bogie = self.Bogies[#self.Bogies],
				Distance = distFromBogieToEdgePrevious + distFromBogieToEdgeThis + self.CarDistance,
			}

			self.Bogies[#self.Bogies].AssociatedBogies.Next = {
				Bogie = newBogie,
				Distance = distFromBogieToEdgePrevious + distFromBogieToEdgeThis,
			}

			self.TrainLength += distFromBogieToEdgePrevious + distFromBogieToEdgeThis + self.CarDistance

			table.insert(self.Bogies, newBogie)
		end

		-- Back Bogie
		local thisCar = self.TrainCars[i].Car :: Model
		local thisBogie = thisCar:FindFirstChild("BogieBack") :: BasePart
		local previousBogie = thisCar:FindFirstChild("BogieFront") :: BasePart

		local newBogie = Bogie.new()
		newBogie:SetNodes(self.VirtualTrack[2], self.VirtualTrack[1])

		newBogie.AssociatedBogies.Previous = {
			Bogie = self.Bogies[#self.Bogies],
			Distance = (previousBogie.Position - thisBogie.Position).Magnitude,
		}

		self.Bogies[#self.Bogies].AssociatedBogies.Next = {
			Bogie = newBogie,
			Distance = (previousBogie.Position - thisBogie.Position).Magnitude,
		}

		self.TrainLength = (previousBogie.Position - thisBogie.Position).Magnitude

		table.insert(self.Bogies, newBogie)
	end

	print("Length: ", self.TrainLength)

	self.TrainConfigured = true

	self:MoveBogies(0)
	self.TrainReady = true
end

function TrainComponent:MoveBogies(movingDistRaw: number)
	if not self.TrainConfigured then
		return
	end

	local movingDist: number = math.abs(movingDistRaw)
	local movingDirNormal: boolean = movingDistRaw >= 0

	local startIndex: number, endIndex: number =
		if movingDirNormal then 1 else #self.Bogies, if movingDirNormal then #self.Bogies else 1
	local increment: number = if movingDirNormal then 1 else -1

	for i = startIndex, endIndex, increment do
		local thisBogie = self.Bogies[i] :: Bogie.Class

		if i == startIndex then
			local nextNodeVirtualId: number = if movingDirNormal then thisBogie.NextNodeId else thisBogie.PreviousNodeId
			local nextNode: Railways.TrackNode = self:GetRailwayNodes()[self:GetNodeFromVirtualId(nextNodeVirtualId)]

			-- Move the bogie according to the velocity (move as much as velocity)
			local distTillNextNode: number = (nextNode.Position - thisBogie.Position).Magnitude

			if movingDist > distTillNextNode then
				local currentNodeIndex: number = self:GetVirtualIdIndexInVirtualTrack(nextNodeVirtualId)

				local prePosition: Vector3 = thisBogie.Position

				repeat
					if self.VirtualTrack[currentNodeIndex - increment] == nil then
						-- Allocate more nodes if necessary
						self:AllocateVirtualTrack(movingDist, movingDirNormal)
						currentNodeIndex = self:GetVirtualIdIndexInVirtualTrack(nextNodeVirtualId)
					end

					local nextNextNodeVirtualId = self.VirtualTrack[currentNodeIndex - increment]
					local nextNextNode: Railways.TrackNode = self:GetRailwayNodes()[self:GetNodeFromVirtualId(
						nextNextNodeVirtualId
					)]

					if nextNextNode then
						distTillNextNode = (nextNextNode.Position - nextNode.Position).Magnitude
						thisBogie:SetNodes(
							if movingDirNormal then nextNodeVirtualId else nextNextNodeVirtualId,
							if movingDirNormal then nextNextNodeVirtualId else nextNodeVirtualId
						)

						movingDist -= (nextNode.Position - prePosition).Magnitude

						prePosition = nextNode.Position
						nextNodeVirtualId = nextNextNodeVirtualId
						nextNode = nextNextNode

						currentNodeIndex = self:GetVirtualIdIndexInVirtualTrack(nextNodeVirtualId)
					else
						warn("Not enough virtual track allocated")
						break
					end
				until movingDist < distTillNextNode
			end

			-- print(nextNode.Id)
			local direction: Vector3 = (nextNode.Position - thisBogie.Position).Unit
			local nextPosition: Vector3 = thisBogie.Position + direction * movingDist

			thisBogie:SetPosition(nextPosition)
		else
			-- Move the bogie according to the position of the previous bogie; maintain the offset
			local nextBogie: Bogie.Class = self.Bogies[i - increment]
			local nextIndex: string = if movingDirNormal then "Next" else "Previous"
			local distanceToMaintain: number = nextBogie.AssociatedBogies[nextIndex].Distance

			local previousNodeVirtualId: number = if movingDirNormal
				then nextBogie.PreviousNodeId
				else nextBogie.NextNodeId
			local nextNodeVirtualId: number = if movingDirNormal then nextBogie.NextNodeId else nextBogie.PreviousNodeId

			local previousNode: Railways.TrackNode = self:GetRailwayNodes()[self:GetNodeFromVirtualId(
				previousNodeVirtualId
			)]
			local nextNode: Railways.TrackNode = self:GetRailwayNodes()[self:GetNodeFromVirtualId(nextNodeVirtualId)]

			local lastPosition: Vector3 = nextBogie.Position

			if distanceToMaintain > (lastPosition - previousNode.Position).Magnitude then
				local previousNodeIndex: number = self:GetVirtualIdIndexInVirtualTrack(previousNodeVirtualId)

				repeat
					if self.VirtualTrack[previousNodeIndex + increment] == nil then
						-- Allocate more nodes if necessary
						self:AllocateVirtualTrack(distanceToMaintain, not movingDirNormal)
						previousNodeIndex = self:GetVirtualIdIndexInVirtualTrack(previousNodeVirtualId)
					end

					local previousPreviousNodeVirtualId: number = self.VirtualTrack[previousNodeIndex + increment]
					local previousPreviousNode: Railways.TrackNode = self:GetRailwayNodes()[self:GetNodeFromVirtualId(
						previousPreviousNodeVirtualId
					)]

					if previousPreviousNode then
						distanceToMaintain -= (lastPosition - previousNode.Position).Magnitude

						lastPosition = previousNode.Position

						nextNodeVirtualId = previousNodeVirtualId
						nextNode = previousNode
						previousNodeVirtualId = previousPreviousNodeVirtualId
						previousNode = previousPreviousNode

						previousNodeIndex = self:GetVirtualIdIndexInVirtualTrack(previousNodeVirtualId)
					else
						print("Not enough virtual track allocated.")
						break
					end
				until distanceToMaintain < (lastPosition - previousNode.Position).Magnitude
			end

			thisBogie:SetNodes(
				if movingDirNormal then previousNodeVirtualId else nextNodeVirtualId,
				if movingDirNormal then nextNodeVirtualId else previousNodeVirtualId
			)
			thisBogie:SetPosition(lastPosition + (previousNode.Position - lastPosition).Unit * distanceToMaintain)
		end
	end
end

function TrainComponent:MoveCars()
	for i = 2, #self.Bogies, 2 do
		local frontBogie: Bogie.Class = self.Bogies[i - 1]
		local backBogie: Bogie.Class = self.Bogies[i]
		local carDictionary: { Car: Model, AlignPosition: AlignPosition, AlignOrientation: AlignOrientation } =
			self.TrainCars[i / 2]

		if carDictionary then
			local middlePosition: Vector3 = frontBogie.Position:Lerp(backBogie.Position, 0.5)
				+ Vector3.new(0, self.VerticalOffset, 0)
			local middleCFrame: CFrame = CFrame.lookAt(
				middlePosition,
				frontBogie.Position + Vector3.new(0, self.VerticalOffset, 0)
			)

			local dist: number = (carDictionary.Car:GetPivot().Position - middlePosition).Magnitude

			if dist > self.MaxVelocity + 50 then
				carDictionary.Car:PivotTo(middleCFrame)
			end

			carDictionary.AlignPosition.Position = middlePosition
			carDictionary.AlignOrientation.CFrame = middleCFrame
		end
	end
end

function TrainComponent:GetVirtualIdIndexInVirtualTrack(queryingVirtualId: number): number
	return table.find(self.VirtualTrack, queryingVirtualId)
end

function TrainComponent:AddVirtualNode(nodeId: string, allocateForward: boolean)
	self.VirtualIds += 1
	local virtualId: number = self.VirtualIds

	self.VirtualIdNodeIndex[virtualId] = nodeId

	if allocateForward then
		table.insert(self.VirtualTrack, 1, virtualId)
	else
		table.insert(self.VirtualTrack, virtualId)
	end
end

function TrainComponent:GetNodeFromVirtualId(virtualId: number)
	return self.VirtualIdNodeIndex[virtualId]
end

function TrainComponent:RemoveVirtualNodeFromVirtualId(virtualId: number, index: number)
	if self.VirtualIdNodeIndex[virtualId] then
		self.VirtualIdNodeIndex[virtualId] = nil
	end

	table.remove(self.VirtualTrack, index)
end

function TrainComponent:AllocateVirtualTrack(distBeyondFrontNode: number, allocateForward: boolean)
	repeat
		local firstIndex: number, secondIndex: number =
			if allocateForward then 1 else #self.VirtualTrack, if allocateForward then 2 else #self.VirtualTrack - 1

		local frontmostNodeId: string = self:GetNodeFromVirtualId(self.VirtualTrack[firstIndex])
		local secondFrontNodeId: string = self:GetNodeFromVirtualId(self.VirtualTrack[secondIndex])

		local frontmostNode: Railways.TrackNode = self:GetRailwayNodes()[frontmostNodeId]
		local secondFrontNode: Railways.TrackNode = self:GetRailwayNodes()[secondFrontNodeId]

		local finalId: string

		if frontmostNode.TrackType == "Track" then
			for _, thisNodeId: string in pairs(frontmostNode.NeighbourIds) do
				if thisNodeId ~= secondFrontNode.Id then
					-- Other side of the track :P
					finalId = thisNodeId
					break
				end
			end
		elseif frontmostNode.TrackType == "SwitchTrack" then
			if secondFrontNode.Id == frontmostNode.RootNodeId then
				-- Branch out from the root track
				-- print("Came from root", secondFrontNode.Id)
				if self.PreferredTrack ~= 0 then
					-- Check if preffered track exists
					-- print("Try custom branch")
					local corresNeighbourNodeId = frontmostNode.NeighbourIds[self.PreferredTrack + 1]

					if corresNeighbourNodeId then
						-- print("To custom branch", corresNeighbourNodeId)
						finalId = corresNeighbourNodeId
					else
						-- print("To rail branch", frontmostNode.BranchNodeId)
						finalId = frontmostNode.BranchNodeId
					end
				else
					-- print("To rail branch", frontmostNode.BranchNodeId)
					-- print(frontmostNode.NeighbourIds)
					finalId = frontmostNode.BranchNodeId
				end
			else
				-- Came from branch track, funnel into the root track
				-- print("Came from branch")
				finalId = frontmostNode.RootNodeId
			end
		end
		if not finalId then
			finalId = "DEFAULT"
		end

		distBeyondFrontNode -= (frontmostNode.Position - self:GetRailwayNodes()[finalId].Position).Magnitude

		self:AddVirtualNode(finalId, allocateForward)
	until distBeyondFrontNode <= 0

	-- print(self.VirtualTrack)
end

function TrainComponent:TrimVirtualtrack()
	if #self.VirtualTrack <= 3 then
		return
	end

	local movingDirNormal: boolean = self.Velocity >= 0

	local thirdIndex: number, lastIndex: number =
		if movingDirNormal then 3 else #self.VirtualTrack - 2, if movingDirNormal then #self.VirtualTrack else 1
	local increment: number = if movingDirNormal then 1 else -1
	local accumulatedDist: number = 0

	for i = thirdIndex, lastIndex, increment do
		local thisNode: Railways.TrackNode = self:GetRailwayNodes()[self:GetNodeFromVirtualId(self.VirtualTrack[i])]
		local nextNode: Railways.TrackNode = self:GetRailwayNodes()[self:GetNodeFromVirtualId(
			self.VirtualTrack[i - increment]
		)]

		local distance: number = (thisNode.Position - nextNode.Position).Magnitude

		accumulatedDist += distance

		if accumulatedDist > self.TrainLength + self.MaxVelocity then
			for _ = i, lastIndex, increment do
				self:RemoveVirtualNodeFromVirtualId(self.VirtualTrack[lastIndex], lastIndex)
			end

			break
		end
	end
end

function TrainComponent:HeartbeatUpdate()
	if self.Processing or not self.TrainReady then
		return
	end
	self.Processing = true

	local currTim: number = time()
	local dt: number = currTim - self.LastUpdate
	self.LastUpdate = currTim

	local acceleratedVelocity: number = self.Velocity + (self.Acceleration * dt)

	self.Velocity = math.clamp(
		acceleratedVelocity - math.sign(acceleratedVelocity) * (math.max(self.Deceleration, 0) * dt),
		-self.MaxVelocity,
		self.MaxVelocity
	)

	-- debug.profilebegin("MoveBogies")
	self:MoveBogies(self.Velocity * dt)
	-- debug.profileend()

	self:MoveCars()

	-- debug.profilebegin("TrimVirtualTrack")
	self:TrimVirtualtrack()
	-- debug.profileend()

	self.Processing = false
end

function TrainComponent:Stop()
	self.Trove:Destroy()
end

export type TrainCongifs = {
	Cars: { Model },
	DistanceBetweenCars: number,
	Railway: string,
	Spawn: { [string]: Vector3 },
}

return TrainComponent
