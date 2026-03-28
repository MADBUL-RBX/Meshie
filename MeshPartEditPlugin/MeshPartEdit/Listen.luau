local Listen = {}

local muted = setmetatable({}, { __mode = "k" })

function Listen.SetMuted(instance, isMuted)
	if isMuted then
		muted[instance] = true
	else
		muted[instance] = nil
	end
end

function Listen.Attach(proxy, callback)
	local lastCFrame = proxy.CFrame
	local lastSize = proxy.Size

	local function fire()
		if muted[proxy] then
			lastCFrame = proxy.CFrame
			lastSize = proxy.Size
			return
		end

		local newCFrame = proxy.CFrame
		local newSize = proxy.Size

		if newCFrame == lastCFrame and newSize == lastSize then
			return
		end

		local oldCFrame = lastCFrame
		local oldSize = lastSize
		lastCFrame = newCFrame
		lastSize = newSize
		callback(proxy, oldCFrame, oldSize, newCFrame, newSize)
	end

	local cframeConnection = proxy:GetPropertyChangedSignal("CFrame"):Connect(fire)
	local sizeConnection = proxy:GetPropertyChangedSignal("Size"):Connect(fire)
	return { cframeConnection, sizeConnection }
end

return Listen
