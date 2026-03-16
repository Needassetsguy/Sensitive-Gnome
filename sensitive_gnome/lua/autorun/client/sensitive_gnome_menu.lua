-- Force Sensitive Gnome into the Fun + Games entity tab

hook.Add("AddGamemodeHUDPanels", "SensitiveGnome_SpawnMenu", function() end)

list.Set("SpawnableEntities", "sent_sensitive_gnome", {
	PrintName    = "Sensitive Gnome",
	ClassName    = "sent_sensitive_gnome",
	Category     = "Fun + Games",
	Information  = "This sensitive gnome causes ultimate destruction, don't spawn this bitch.",
	Author       = "Federal Crime Committer",
	IconOverride = "entities/sent_sensitive_gnome",
})

-- Precache gnome sound clientside
sound.Add({
	name    = "sensitive_gnome.scream",
	channel = CHAN_AUTO,
	volume  = 1.0,
	level   = 120,
	pitch   = 100,
	sound   = "sensitive_gnome/gnome_scream.mp3",
})
