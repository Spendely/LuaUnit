--!strict
--[[
	Fake MarketplaceService for testing purchases.

		local market = Fakes.MarketplaceService.new({
			gamePasses = { [userId] = { passId, ... } },
			assets     = { [userId] = { assetId, ... } },
			products   = { [productId] = { Name = "100 Coins", PriceInRobux = 25 } },
		})
		market.ProcessReceipt = YourShop.processReceipt
		local decision, receipt = market:simulatePurchase(player, productId)
		Assert.equals(decision, Enum.ProductPurchaseDecision.PurchaseGranted)

	Roblox retries ProcessReceipt until it returns PurchaseGranted, using the
	same PurchaseId. Test that your handler doesn't grant twice with:
		market:simulatePurchase(player, productId, { purchaseId = receipt.PurchaseId })
]]

local Mock = require(script.Parent.Parent.Mock)
local Signal = require(script.Parent.Signal)

local Market = {}
Market.__index = Market

local function toSet(map: { [any]: { number } }?): { [any]: { [number]: boolean } }
	local result = {}
	for userId, ids in map or {} do
		result[userId] = {}
		for _, id in ids do
			result[userId][id] = true
		end
	end
	return result
end

function Market.new(options: { gamePasses: any?, assets: any?, products: any?, placeId: number? }?)
	local opts = options or {}
	local self = setmetatable({
		ProcessReceipt = nil :: ((any) -> Enum.ProductPurchaseDecision)?,
		PromptProductPurchaseFinished = Signal.new(),
		PromptGamePassPurchaseFinished = Signal.new(),
		PromptPurchaseFinished = Signal.new(),
		-- Prompts are spies: Assert.calledWith(market.PromptProductPurchase, market, player, id)
		PromptProductPurchase = Mock.spy(),
		PromptGamePassPurchase = Mock.spy(),
		PromptPurchase = Mock.spy(),
		receipts = {}, -- every receipt sent to ProcessReceipt
		_gamePasses = toSet(opts.gamePasses),
		_assets = toSet(opts.assets),
		_products = opts.products or {},
		_placeId = opts.placeId or game.PlaceId,
		_purchaseCount = 0,
		_failures = {},
	}, Market)
	return self
end

function Market:_begin(method: string)
	for i, failure in self._failures do
		if failure.method == nil or failure.method == method then
			table.remove(self._failures, i)
			error(failure.message, 0)
		end
	end
end

function Market:failNext(method: string?, message: string?)
	table.insert(self._failures, { method = method, message = message or "HTTP 500 (simulated)" })
end

function Market:UserOwnsGamePassAsync(userId: number, gamePassId: number): boolean
	self:_begin("UserOwnsGamePassAsync")
	local owned = self._gamePasses[userId]
	return owned ~= nil and owned[gamePassId] == true
end

function Market:PlayerOwnsAsset(player: any, assetId: number): boolean
	self:_begin("PlayerOwnsAsset")
	local owned = self._assets[player.UserId]
	return owned ~= nil and owned[assetId] == true
end

function Market:GetProductInfo(id: number, _infoType: Enum.InfoType?)
	self:_begin("GetProductInfo")
	local info = self._products[id]
	if not info then
		error(`no product info for {id}`, 0)
	end
	local result = table.clone(info)
	result.ProductId = result.ProductId or id
	return result
end

function Market:grantGamePass(userId: number, gamePassId: number)
	self._gamePasses[userId] = self._gamePasses[userId] or {}
	self._gamePasses[userId][gamePassId] = true
end

-- Simulates a player completing a game pass purchase prompt.
function Market:simulateGamePassPurchase(player: any, gamePassId: number, purchased: boolean?)
	local didPurchase = purchased ~= false
	if didPurchase then
		self:grantGamePass(player.UserId, gamePassId)
	end
	self.PromptGamePassPurchaseFinished:Fire(player, gamePassId, didPurchase)
end

-- Simulates a developer product purchase. Calls ProcessReceipt like Roblox
-- does and returns its decision plus the receipt that was sent.
function Market:simulatePurchase(player: any, productId: number, options: { purchaseId: string?, currencySpent: number? }?)
	local handler = self.ProcessReceipt
	if not handler then
		error("ProcessReceipt is not set", 0)
	end
	local opts = options or {}
	self._purchaseCount += 1
	local product = self._products[productId]
	local receipt = {
		PlayerId = player.UserId,
		ProductId = productId,
		PurchaseId = opts.purchaseId or `fake-purchase-{self._purchaseCount}`,
		CurrencySpent = opts.currencySpent or (product and product.PriceInRobux) or 0,
		CurrencyType = Enum.CurrencyType.Robux,
		PlaceIdWherePurchased = self._placeId,
	}
	table.insert(self.receipts, receipt)
	local decision = handler(table.clone(receipt))
	self.PromptProductPurchaseFinished:Fire(player.UserId, productId, true)
	return decision, receipt
end

return Market
