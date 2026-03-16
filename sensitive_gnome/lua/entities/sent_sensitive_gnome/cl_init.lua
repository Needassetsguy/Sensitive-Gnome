include("shared.lua")

function ENT:Draw()       self:DrawModel() end
function ENT:DrawTranslucent() self:Draw() end

-- ============================================================
--  Skybox change
-- ============================================================
net.Receive("gnome_skychange", function()
	RunConsoleCommand("r_skybox", "sky_day01_07")
end)

-- ============================================================
--  Giant map-wide tornado fog cloud
-- ============================================================
local tornadoActive = false
local tornadoCenter = Vector(0,0,0)
local tornadoAngle  = 0

net.Receive("gnome_tornado_pos", function()
	tornadoCenter = net.ReadVector()
	tornadoActive = net.ReadBool()
end)

local fogMat   = Material("particle/smokesprites_0001")
local glowMat  = Material("sprites/light_glow02_add")

hook.Add("PostDrawOpaqueRenderables", "SensitiveGnome_Tornado", function()
	if not tornadoActive then return end

	tornadoAngle = (tornadoAngle + FrameTime() * 45) % 360

	render.SetMaterial(fogMat)

	-- Giant fog column — 30 layers, very wide at base, fills the sky
	-- Radius at ground: 4000 units. Narrows to 800 at top.
	local LAYERS      = 30
	local BASE_RADIUS = 4000
	local TOP_RADIUS  = 800
	local LAYER_HEIGHT = 400
	local SPRITES_PER_LAYER = 8

	for i = 1, LAYERS do
		local frac   = (i-1) / (LAYERS-1)
		local radius = BASE_RADIUS + (TOP_RADIUS - BASE_RADIUS) * frac
		local height = (i-1) * LAYER_HEIGHT
		local alpha  = math.Clamp(160 - frac * 80, 30, 160)
		local spin   = tornadoAngle + frac * 720  -- more spin at top

		for j = 0, SPRITES_PER_LAYER - 1 do
			local a  = math.rad(spin + j * (360 / SPRITES_PER_LAYER))
			local ox = math.cos(a) * radius
			local oy = math.sin(a) * radius
			local pos = tornadoCenter + Vector(ox, oy, height)
			local sz  = radius * 0.55
			render.DrawSprite(pos, sz, sz, Color(210, 225, 255, alpha))
		end
	end

	-- Bright center glow core
	render.SetMaterial(glowMat)
	render.DrawSprite(tornadoCenter + Vector(0,0,200), 600, 600, Color(180, 210, 255, 120))
	render.DrawSprite(tornadoCenter + Vector(0,0,800), 400, 400, Color(200, 230, 255, 90))
end)
