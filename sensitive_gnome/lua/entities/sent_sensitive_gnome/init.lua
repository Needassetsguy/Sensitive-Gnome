AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

util.PrecacheSound("sensitive_gnome/gnome_scream.mp3")

-- ============================================================
--  SAFE prop list — hand-picked folders, no junk, no effects
--  Props are cached once on first trigger so no repeated disk hits
-- ============================================================
local PROP_FOLDERS = {
	"props_c17", "props_combine", "props_debris", "props_doors",
	"props_junk", "props_lab", "props_office", "props_urban",
	"props_wasteland", "props_wood", "props_buildings",
	"props_ep1", "props_ep2", "props_farm", "props_forest",
	"props_crates", "props_cs_office", "props_cs_italy",
	"props_cs_dust", "props_cs_nuke", "props_downtown",
	"props_industrial", "props_phx",
}

-- Skip anything that looks like an effect, ragdoll, shader test, or debug model
local SKIP_PATTERNS = {
	"shadertest", "debug", "error", "test_", "_test", "dev_", "_dev",
	"toolmodel", "effects/", "particle", "ragdoll", "gibs", "gib_",
	"combine_ball", "antlion", "zombie", "kleiner", "alyx", "barney",
	"hunter", "strider", "advisor", "citizen", "mossman",
	"combine_soldier", "combine_super", "scanner",
}

local cachedProps = nil

local function IsSkipped(path)
	local p = path:lower()
	for _, pat in ipairs(SKIP_PATTERNS) do
		if p:find(pat, 1, true) then return true end
	end
	return false
end

local function GetAllProps()
	if cachedProps then return cachedProps end
	local props = {}
	local seen  = {}
	for _, folder in ipairs(PROP_FOLDERS) do
		local files = file.Find("models/" .. folder .. "/*.mdl", "GAME")
		if files then
			for _, f in ipairs(files) do
				local path = "models/" .. folder .. "/" .. f
				if not seen[path] and not IsSkipped(path) then
					seen[path] = true
					table.insert(props, path)
				end
			end
		end
	end
	if #props == 0 then
		props = { "models/props_c17/oildrum001.mdl", "models/props_junk/metalbucket01a.mdl" }
	end
	cachedProps = props
	return props
end

-- ============================================================
--  Map bounds
-- ============================================================
local function GetMapBounds()
	local D = 32768
	local function T(dir)
		local tr = util.TraceLine({ start = Vector(0,0,0), endpos = dir*D, mask = MASK_SOLID_BRUSHONLY })
		return tr.Hit and tr.HitPos or (dir*D)
	end
	local mins = Vector(T(Vector(-1,0,0)).x, T(Vector(0,-1,0)).y, T(Vector(0,0,-1)).z)
	local maxs = Vector(T(Vector( 1,0,0)).x, T(Vector(0, 1,0)).y, T(Vector(0,0, 1)).z)
	-- Inset
	mins = mins + Vector(128,128,64)
	maxs = maxs + Vector(-128,-128,-64)
	return mins, maxs
end

-- ============================================================
--  Initialize
-- ============================================================
function ENT:Initialize()
	self:SetModel("models/props_junk/gnome.mdl")
	self:PhysicsInit(SOLID_VPHYSICS)
	self:SetMoveType(MOVETYPE_VPHYSICS)
	self:SetSolid(SOLID_VPHYSICS)
	self:SetUseType(SIMPLE_USE)

	local phys = self:GetPhysicsObject()
	if IsValid(phys) then
		phys:Wake()
		phys:SetMass(5060)
		phys:SetMaterial("rubber")
	end

	self.triggered    = false
	self.spawnedProps = {}
	self.tornadoProps = {}
	self.timers       = {}
	self.mapMins      = nil
	self.mapMaxs      = nil
	self.gnomePos     = nil
end

function ENT:OnGravGunPickup(ply) return false end
function ENT:OnPhysgunPickup(ply) return false end

function ENT:Use(activator, caller)
	if not IsValid(activator) or not activator:IsPlayer() then return end
	if self.triggered then return end
	self:Trigger(activator)
end

-- ============================================================
--  Trigger
-- ============================================================
function ENT:Trigger(ply)
	if self.triggered then return end
	self.triggered = true

	local mins, maxs = GetMapBounds()
	self.mapMins = mins
	self.mapMaxs = maxs

	-- Beeps
	self:EmitSound("Grenade.Blip", 100, 100)
	local beepData = { {0.5,115}, {0.9,130}, {1.2,150} }
	for _, b in ipairs(beepData) do
		local t = "gnome_beep_" .. b[1] .. "_" .. self:EntIndex()
		timer.Create(t, b[1], 1, function()
			if IsValid(self) then self:EmitSound("Grenade.Blip", 100, b[2]) end
		end)
		table.insert(self.timers, t)
	end

	local tExplode = "gnome_explode_" .. self:EntIndex()
	timer.Create(tExplode, 1.6, 1, function()
		if not IsValid(self) then return end

		local epos = self:GetPos()
		self.gnomePos = epos

		-- Explosion sounds
		self:EmitSound("ambient/explosions/explode_4.wav", 145, 75)
		self:EmitSound("ambient/explosions/explode_3.wav", 145, 95)

		-- Clientside explosion effect only — NO env_explosion, NO util.BlastDamage
		-- Those are what cause the portal and the freeze
		local ed = EffectData()
		ed:SetOrigin(epos)
		ed:SetScale(4)
		util.Effect("Explosion", ed, true, true)

		-- Small physics push on nearby ents only — no sphere scan lag
		for _, ent in ipairs(ents.FindInSphere(epos, 300)) do
			if IsValid(ent) and ent ~= self and ent:GetClass() == "prop_physics" then
				local ph = ent:GetPhysicsObject()
				if IsValid(ph) then
					ph:ApplyForceCenter((ent:GetPos() - epos):GetNormalized() * 400000)
				end
			end
		end

		-- Hide gnome
		self:SetNoDraw(true)
		self:SetSolid(SOLID_NONE)
		local gp = self:GetPhysicsObject()
		if IsValid(gp) then gp:EnableMotion(false) end

		-- Gnome scream via info_target so server broadcasts it
		local snd = ents.Create("info_target")
		if IsValid(snd) then
			snd:SetPos(epos)
			snd:Spawn()
			snd:EmitSound("sensitive_gnome/gnome_scream.mp3", 145, 100, 1, CHAN_AUTO)
			timer.Simple(12, function() if IsValid(snd) then snd:Remove() end end)
		end

		self:StartShake()

		-- Skybox change — send to all clients via net message
		net.Start("gnome_skychange")
		net.Broadcast()

		local tRain = "gnome_rain_" .. self:EntIndex()
		timer.Create(tRain, 0.5, 1, function()
			if IsValid(self) then self:StartPropRain() end
		end)
		table.insert(self.timers, tRain)

		local tTornado = "gnome_tornado_" .. self:EntIndex()
		timer.Create(tTornado, 4.0, 1, function()
			if IsValid(self) then self:StartTornado() end
		end)
		table.insert(self.timers, tTornado)
	end)
	table.insert(self.timers, tExplode)
end

-- Net message pool
util.AddNetworkString("gnome_skychange")
util.AddNetworkString("gnome_tornado_pos")

-- ============================================================
--  Screenshake — util.ScreenShake is the correct serverside call
-- ============================================================
function ENT:StartShake()
	local t = "gnome_shake_" .. self:EntIndex()
	timer.Create(t, 0.2, 0, function()
		if not IsValid(self) then timer.Remove(t) return end
		util.ScreenShake(self.gnomePos, 8, 4, 0.25, 99999)
	end)
	table.insert(self.timers, t)
end

-- ============================================================
--  Prop rain — escalating waves, no auto-delete, live count check
-- ============================================================
function ENT:StartPropRain()
	local props = GetAllProps()
	local total = #props
	local LIMIT = 500   -- max prop_physics on map at once

	local mins   = self.mapMins
	local maxs   = self.mapMaxs
	local spawnZ = maxs.z - 80

	-- Shuffle
	for i = total, 2, -1 do
		local j = math.random(i)
		props[i], props[j] = props[j], props[i]
	end

	-- Wave 1: slow trickle (0-20s)   props 1-50   @ 0.4s each
	-- Wave 2: building    (20-29s)   props 51-140  @ 0.1s each
	-- Wave 3: hailstorm   (29s+)     props 141-600 @ 0.04s each
	-- Total: up to 600 attempts, skips if map is full
	local function Delay(i)
		if i <= 50  then return i * 0.4
		elseif i <= 140 then return 50*0.4 + (i-50)*0.1
		else return 50*0.4 + 90*0.1 + (i-140)*0.04
		end
	end

	for i = 1, 600 do
		local model = props[((i-1) % total) + 1]
		timer.Simple(Delay(i), function()
			if not IsValid(self) then return end
			if #ents.FindByClass("prop_physics") >= LIMIT then return end

			local prop = ents.Create("prop_physics")
			if not IsValid(prop) then return end

			prop:SetModel(model)
			prop:SetPos(Vector(math.Rand(mins.x,maxs.x), math.Rand(mins.y,maxs.y), spawnZ))
			prop:SetAngles(Angle(math.random(0,360),math.random(0,360),math.random(0,360)))
			prop:Spawn()
			prop:Activate()

			-- Prevent props from auto-removing (some models have a built-in fade)
			prop:SetKeyValue("fademindist", "-1")
			prop:SetKeyValue("fademaxdist", "0")

			local ph = prop:GetPhysicsObject()
			if IsValid(ph) then
				ph:Wake()
				ph:SetMass(5060)
				ph:SetVelocity(Vector(math.random(-80,80), math.random(-80,80), math.random(-2800,-1600)))
				ph:SetAngleVelocity(Vector(math.random(-300,300),math.random(-300,300),math.random(-300,300)))
			end

			table.insert(self.spawnedProps, prop)
		end)
	end
end

-- ============================================================
--  Tornado — pulls props + players, sends position to clients
--  for the giant fog cloud visual
-- ============================================================
-- ============================================================
--  Tornado — spans the entire map, multiple pull points
-- ============================================================
function ENT:StartTornado()
	if not IsValid(self) then return end

	local center = self.gnomePos or self:GetPos()
	local mins   = self.mapMins
	local maxs   = self.mapMaxs
	local midZ   = (mins.z + maxs.z) * 0.5

	-- Main center + 4 corner pull points spread across the map
	-- This makes the tornado feel like it fills the entire map
	local mapCenterX = (mins.x + maxs.x) * 0.5
	local mapCenterY = (mins.y + maxs.y) * 0.5
	local spreadX    = (maxs.x - mins.x) * 0.3
	local spreadY    = (maxs.y - mins.y) * 0.3

	self.tornadoCenters = {
		Vector(mapCenterX,            mapCenterY,            midZ),
		Vector(mapCenterX + spreadX,  mapCenterY + spreadY,  midZ + 200),
		Vector(mapCenterX - spreadX,  mapCenterY + spreadY,  midZ + 400),
		Vector(mapCenterX + spreadX,  mapCenterY - spreadY,  midZ + 200),
		Vector(mapCenterX - spreadX,  mapCenterY - spreadY,  midZ + 400),
	}
	self.tornadoCenter = self.tornadoCenters[1]  -- keep for OnRemove net msg

	-- Collect all physics props
	for _, ent in ipairs(ents.FindByClass("prop_physics")) do
		if IsValid(ent) then table.insert(self.tornadoProps, ent) end
	end

	-- Send all tornado centers to clients
	net.Start("gnome_tornado_pos")
		net.WriteVector(self.tornadoCenters[1])
		net.WriteBool(true)
	net.Broadcast()

	local tickIndex = 0

	local t = "gnome_tornado_think_" .. self:EntIndex()
	timer.Create(t, 0.05, 0, function()
		if not IsValid(self) then timer.Remove(t) return end

		tickIndex = (tickIndex % #self.tornadoCenters) + 1
		local tc = self.tornadoCenters[tickIndex]

		-- Props — prune dead, apply forces
		local alive = {}
		for _, ent in ipairs(self.tornadoProps) do
			if IsValid(ent) then
				table.insert(alive, ent)
				local ph = ent:GetPhysicsObject()
				if IsValid(ph) then
					ph:Wake()
					local pos  = ent:GetPos()
					local diff = tc - pos
					local dist = diff:Length()
					if mins then
						local cl = Vector(
							math.Clamp(pos.x, mins.x, maxs.x),
							math.Clamp(pos.y, mins.y, maxs.y),
							math.Clamp(pos.z, mins.z, maxs.z)
						)
						if cl ~= pos then
							ph:ApplyForceCenter((cl - pos):GetNormalized() * 60000)
						end
					end
					local pull  = diff:GetNormalized() * math.Clamp(70000 - dist*2, 15000, 90000)
					local swirl = Vector(-diff.y, diff.x, 0):GetNormalized() * 80000
					ph:ApplyForceCenter(pull + swirl + Vector(0,0,25000))
				end
			end
		end
		self.tornadoProps = alive

		-- Rain props
		for _, ent in ipairs(self.spawnedProps) do
			if IsValid(ent) then
				local ph = ent:GetPhysicsObject()
				if IsValid(ph) then
					ph:Wake()
					local diff  = tc - ent:GetPos()
					local pull  = diff:GetNormalized() * math.Clamp(70000 - diff:Length()*2, 15000, 90000)
					local swirl = Vector(-diff.y, diff.x, 0):GetNormalized() * 80000
					ph:ApplyForceCenter(pull + swirl + Vector(0,0,25000))
				end
			end
		end

		-- Players
		for _, ply in ipairs(player.GetAll()) do
			if IsValid(ply) and ply:Alive() then
				local diff  = tc - ply:GetPos()
				local dist  = diff:Length()
				local pull  = diff:GetNormalized() * math.Clamp(2000 - dist*0.05, 400, 2000)
				local swirl = Vector(-diff.y, diff.x, 0):GetNormalized() * 1800
				ply:SetVelocity(pull + swirl + Vector(0,0,700))
			end
		end
	end)
	table.insert(self.timers, t)
end

-- ============================================================
--  Cleanup
-- ============================================================
function ENT:OnRemove()
	-- Stop tornado visual on clients
	if self.tornadoCenter then
		net.Start("gnome_tornado_pos")
			net.WriteVector(self.tornadoCenter)
			net.WriteBool(false) -- deactivate
		net.Broadcast()
	end

	for _, t in ipairs(self.timers or {}) do timer.Remove(t) end

	for _, ent in ipairs(self.spawnedProps or {}) do
		if IsValid(ent) then ent:Remove() end
	end

	for _, ent in ipairs(self.tornadoProps or {}) do
		if IsValid(ent) then
			local ph = ent:GetPhysicsObject()
			if IsValid(ph) then
				ph:SetVelocity(Vector(0,0,0))
				ph:SetAngleVelocity(Vector(0,0,0))
			end
		end
	end
end
