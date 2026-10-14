--!strict
--[[
	Fake Player. Real Player instances can't be created by scripts, so code
	that takes a player can be tested with this instead.

		local player = Fakes.Player.new({ Name = "Bob", UserId = 42 })
		Kick and Destroy are spies: Assert.called(player.Kick)
		player.leaderstats is a real Folder (destroyed by player:Destroy()).
]]

local Mock = require(script.Parent.Parent.Mock)
local Signal = require(script.Parent.Signal)

local Player = {}

local nextUserId = 1

function Player.new(props: { [string]: any }?)
	local p = props or {}
	local userId = p.UserId or nextUserId
	nextUserId += 1

	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"

	local player: { [string]: any } = {
		Name = p.Name or `Player{userId}`,
		DisplayName = p.DisplayName or p.Name or `Player{userId}`,
		UserId = userId,
		ClassName = "Player",
		AccountAge = p.AccountAge or 365,
		MembershipType = p.MembershipType or Enum.MembershipType.None,
		Team = p.Team,
		Character = p.Character,
		leaderstats = leaderstats,
		CharacterAdded = Signal.new(),
		CharacterRemoving = Signal.new(),
		Kick = Mock.spy(),
		_attributes = {},
	}

	function player:IsA(className: string): boolean
		return className == "Player" or className == "Instance"
	end
	function player:GetAttribute(name: string)
		return self._attributes[name]
	end
	function player:SetAttribute(name: string, value: any)
		self._attributes[name] = value
	end
	function player:FindFirstChild(name: string)
		return if name == "leaderstats" then self.leaderstats else nil
	end
	function player:WaitForChild(name: string)
		return self:FindFirstChild(name)
	end
	player.Destroy = Mock.spy(function()
		leaderstats:Destroy()
		player.CharacterAdded:DisconnectAll()
		player.CharacterRemoving:DisconnectAll()
	end)

	for k, v in p do
		if player[k] == nil then
			player[k] = v
		end
	end
	return player
end

return Player
