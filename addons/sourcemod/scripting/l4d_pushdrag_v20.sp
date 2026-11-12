/*
 * Push And Drag - optimized edition
 * Original author: Pan Xiaohai (v1.2)
 * Optimized: v1.4.0
 *
 * Changes over v1.2:
 *  - Added master switch cvar (l4d_pushdrag_enable) + player-grab gate.
 *  - Every gameplay number is now a cvar with bounds (distances, hold times,
 *    force, throw forces, double tap window, ...).
 *  - Fixed the "gravity goes wrong after grabbing" bug:
 *      * held players keep their vertical velocity, so gravity still applies;
 *      * releasing an entity clears the artificial velocity instead of leaving
 *        it with the last teleported speed;
 *      * m_flLastPhysicsInfluenceTime now uses game time (curtime) and the
 *        physics attacker is cleared on release;
 *      * held entities are tracked by serial-encoded entrefs, so a deleted /
 *        reused edict can never be dragged by accident.
 *  - All release paths go through ReleaseHold(); no more leaked velocities on
 *    death, disconnect, map change, round end, plugin unload or master off.
 *  - v1.5: +speed + right click = strong throw (2000); +speed + double tap reload
 *    = long range grab (default 1000 units); the old "hold +speed + single
 *    reload" strong throw was removed.
 *  - v1.6: clear the physics-attacker state on release (stops players being
 *    launched when they stand on a previously grabbed prop); survivors may grab
 *    enemy special infected; spectators (team 1) may grab objects.
 *  - v1.7: hook PhysicsDamage::operator() (DHooks) to stop the engine shoving
 *    players who stand on a grabbed prop; spectators ignore player hits in the
 *    grab trace; single reload drops the held entity; held players can jump to
 *    break free; admin-only switches for grab / special grab / spectator grab.
 *  - v1.8: raw usercmd buttons (fixes incapped right click throw); fall damage
 *    protection for released players; incapped trace ignores enemy players;
 *    zoom key levels held props; special infected hold distance; held props deal
 *    no damage until thrown; translated hints (en/ru/chi).
 *  - v1.9: phrase #format so names resolve; func_/prop_dynamic mechanisms are no
 *    longer grabbable (fixes elevator repelling players); thrown props are
 *    settled once they stop so the throw force cannot launch players later.
 *  - v2.0: removed the obsolete DHooks PhysicsDamage patch (the throw settle is
 *    the real fix); numeric fall protection; spectator player grabs; zho
 *    translations; removed player_keep_gravity (old levitation behaviour kept);
 *    leveling is now a held toggle mode.
 *
 * Tested compiler: SourceMod 1.11.x / 1.12.x
 */

#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

#define PLUGIN_VERSION  "2.0.0"
#define SOUND_GRAB      "UI/helpful_event_1.wav"

#define HELD_NONE       (-1)
#define MAX_GRABTYPE    6
#define THROWN_MAX      32

enum
{
	GrabType_None = 0,
	GrabType_Object,
	GrabType_Car,
	GrabType_Weapon,
	GrabType_Player,
	GrabType_Default
};

ConVar g_cvEnable;
ConVar g_cvVersusSurvivor;
ConVar g_cvVersusInfected;
ConVar g_cvPlayerGrab;
ConVar g_cvSpectatorGrab;
ConVar g_cvSpectatorGrabPlayers;
ConVar g_cvSurvivorGrabSpecial;
ConVar g_cvGrabRange;
ConVar g_cvFarGrabRange;
ConVar g_cvDistObject;
ConVar g_cvDistCar;
ConVar g_cvDistWeapon;
ConVar g_cvDistPlayer;
ConVar g_cvDistDefault;
ConVar g_cvTimeObject;
ConVar g_cvTimeCar;
ConVar g_cvTimeWeapon;
ConVar g_cvTimePlayer;
ConVar g_cvTimeDefault;
ConVar g_cvHoldForce;
ConVar g_cvHoldForceDist;
ConVar g_cvHoldMaxSpeed;
ConVar g_cvBreakDist;
ConVar g_cvReleaseStop;
ConVar g_cvLatencyComp;
ConVar g_cvThrowForce;
ConVar g_cvThrowForceAttack2;
ConVar g_cvThrowForceBase;
ConVar g_cvThrowFalloff;
ConVar g_cvDoubleTap;
ConVar g_cvPhysicsAttacker;
ConVar g_cvAttackerTime;
ConVar g_cvReleaseSettle;
ConVar g_cvPlayerJumpEscape;
ConVar g_cvAdminOnly;
ConVar g_cvAdminOnlySpecial;
ConVar g_cvAdminOnlySpectator;
ConVar g_cvHoldDistSpecial;
ConVar g_cvNoHeldDamage;
ConVar g_cvFallProtect;
ConVar g_cvLevelKey;
ConVar g_cvIncapAttackThrow;
ConVar g_cvThrowSettle;
ConVar g_cvSound;

ConVar g_cvGameMode;

// Cached settings (never queried inside OnGameFrame).
bool  g_bEnabled;
bool  g_bPlayerGrab;
bool  g_bReleaseStop;
bool  g_bPhysicsAttacker;
bool  g_bSpectatorGrab;
bool  g_bSpectatorGrabPlayers;
bool  g_bSurvivorGrabSpecial;
bool  g_bReleaseSettle;
bool  g_bPlayerJumpEscape;
bool  g_bAdminOnly;
bool  g_bAdminOnlySpecial;
bool  g_bAdminOnlySpectator;
bool  g_bNoHeldDamage;
bool  g_bLevelKey;
bool  g_bIncapAttackThrow;
bool  g_bThrowSettle;
bool  g_bSound;
bool  g_bL4D2;
int   g_iGameMode;
int   g_iVersusSurvivor;
int   g_iVersusInfected;
float g_flGrabRange;
float g_flFarGrabRange;
float g_flDistSpecial;
float g_flDist[MAX_GRABTYPE];
float g_flHoldTime[MAX_GRABTYPE];
float g_flHoldForce;
float g_flHoldForceDist;
float g_flHoldMaxSpeed;
float g_flBreakDist;
float g_flLatencyComp;
float g_flThrowForce;
float g_flThrowForceAttack2;
float g_flThrowForceBase;
float g_flThrowFalloff;
float g_flDoubleTap;
float g_flAttackerTime;
float g_flFallProtectTime;

// Per client state.
int   g_iHeldRef[MAXPLAYERS + 1];
int   g_iHeldType[MAXPLAYERS + 1];
float g_flHoldDist[MAXPLAYERS + 1];
float g_flHoldUntil[MAXPLAYERS + 1];
float g_flHoldBreak[MAXPLAYERS + 1];
int   g_iKeyState[MAXPLAYERS + 1];
int   g_iKeyBuffer[MAXPLAYERS + 1];
float g_flKeyTime[MAXPLAYERS + 1];
int   g_iAttackerRef[MAXPLAYERS + 1];
float g_flAttackerClearAt[MAXPLAYERS + 1];
bool  g_bLevelMode[MAXPLAYERS + 1];
int   g_iRawButtons[MAXPLAYERS + 1];
bool  g_bRawValid[MAXPLAYERS + 1];
float g_flFallProtectUntil[MAXPLAYERS + 1];
int   g_iThrownRef[THROWN_MAX];
float g_flThrownAt[THROWN_MAX];
float g_flThrownPos[THROWN_MAX][3];
int   g_iThrownNext;

int   g_iVelocity = -1;
int   g_iGhostOffset = -1;
int   g_iIncapOffset = -1;
float g_flLastFrame;

public Plugin myinfo =
{
	name = "Push And Drag",
	author = "Pan Xiaohai",
	description = "Grab, drag and throw physics objects and players (cvar driven, gravity safe)",
	version = PLUGIN_VERSION,
	url = "https://forums.alliedmods.net/showthread.php?t=140673"
};

public void OnPluginStart()
{
	LoadTranslations("l4d_pushdrag.phrases");

	g_iVelocity = FindSendPropInfo("CBasePlayer", "m_vecVelocity[0]");
	if (g_iVelocity <= 0)
	{
		LogError("[Push And Drag] Could not find CBasePlayer::m_vecVelocity[0]; player dragging is disabled.");
	}

	char folder[16];
	GetGameFolderName(folder, sizeof(folder));
	g_bL4D2 = StrEqual(folder, "left4dead2", false);
	if (g_bL4D2)
	{
		g_iGhostOffset = FindSendPropInfo("CTerrorPlayer", "m_isGhost");
		g_iIncapOffset = FindSendPropInfo("CTerrorPlayer", "m_isIncapacitated");
	}

	CreateCvars();
	HookCvars();

	// Late load: SDKHooks only fires OnClientPutInServer for future clients.
	for (int client = 1; client <= MaxClients; client++)
	{
		if (IsClientInGame(client))
		{
			SDKUnhook(client, SDKHook_OnTakeDamage, OnTakeDamage);
			SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
		}
	}

	g_cvGameMode = FindConVar("mp_gamemode");
	if (g_cvGameMode != null)
	{
		HookConVarChange(g_cvGameMode, OnCvarChanged);
	}

	AutoExecConfig(true, "l4d_pushdrag");

	HookEvent("round_end", Event_RoundEnd);
	HookEvent("finale_win", Event_RoundEnd);
	HookEvent("mission_lost", Event_RoundEnd);
	HookEvent("map_transition", Event_RoundEnd);

	g_flLastFrame = GetGameTime();
	ResetState();
	RefreshSettings();
}

void CreateCvars()
{
	g_cvEnable = CreateConVar("l4d_pushdrag_enable", "1",
		"Master switch: 0 disables all grabbing and releases held entities, 1 enables the plugin",
		FCVAR_NOTIFY, true, 0.0, true, 1.0);

	g_cvVersusSurvivor = CreateConVar("l4d_pushdrag_versus_survivor", "3",
		"Versus/scavenge survivor mode: 0=disabled, 1=objects only, 2=teammates only, 3=objects and teammates",
		FCVAR_NOTIFY, true, 0.0, true, 3.0);

	g_cvVersusInfected = CreateConVar("l4d_pushdrag_versus_infected", "2",
		"Versus/scavenge infected mode: 0=disabled, 1=objects only, 2=teammates only, 3=objects and teammates",
		FCVAR_NOTIFY, true, 0.0, true, 3.0);

	g_cvPlayerGrab = CreateConVar("l4d_pushdrag_player_grab", "1",
		"Allow grabbing players at all (0/1)",
		FCVAR_NONE, true, 0.0, true, 1.0);

	g_cvSpectatorGrab = CreateConVar("l4d_pushdrag_spectator_grab", "1",
		"Allow spectators (team 1) to grab objects (0/1)",
		FCVAR_NONE, true, 0.0, true, 1.0);

	g_cvSpectatorGrabPlayers = CreateConVar("l4d_pushdrag_spectator_grab_players", "1",
		"Allow spectators to grab players and special infected too (0/1)",
		FCVAR_NONE, true, 0.0, true, 1.0);

	g_cvSurvivorGrabSpecial = CreateConVar("l4d_pushdrag_survivor_grab_special", "1",
		"Allow survivors to grab enemy special infected players (0/1)",
		FCVAR_NONE, true, 0.0, true, 1.0);

	g_cvGrabRange = CreateConVar("l4d_pushdrag_grab_range", "240.0",
		"Maximum distance (units) at which something can be grabbed",
		FCVAR_NONE, true, 16.0, true, 2000.0);

	g_cvFarGrabRange = CreateConVar("l4d_pushdrag_far_grab_range", "1000.0",
		"Maximum distance (units) for the +speed double tap long range grab",
		FCVAR_NONE, true, 16.0, true, 5000.0);

	g_cvDistObject = CreateConVar("l4d_pushdrag_hold_dist_object", "120.0",
		"Hold distance (units) for prop_* entities",
		FCVAR_NONE, true, 16.0, true, 1000.0);

	g_cvDistCar = CreateConVar("l4d_pushdrag_hold_dist_car", "200.0",
		"Hold distance (units) for entities whose classname contains \"car\"",
		FCVAR_NONE, true, 16.0, true, 1000.0);

	g_cvDistWeapon = CreateConVar("l4d_pushdrag_hold_dist_weapon", "50.0",
		"Hold distance (units) for weapon_* entities",
		FCVAR_NONE, true, 16.0, true, 1000.0);

	g_cvDistPlayer = CreateConVar("l4d_pushdrag_hold_dist_player", "70.0",
		"Hold distance (units) for player entities",
		FCVAR_NONE, true, 16.0, true, 1000.0);

	g_cvDistDefault = CreateConVar("l4d_pushdrag_hold_dist_default", "100.0",
		"Hold distance (units) for every other entity",
		FCVAR_NONE, true, 16.0, true, 1000.0);

	g_cvTimeObject = CreateConVar("l4d_pushdrag_hold_time_object", "15.0",
		"Maximum hold time (seconds) for prop_* entities",
		FCVAR_NONE, true, 1.0, true, 120.0);

	g_cvTimeCar = CreateConVar("l4d_pushdrag_hold_time_car", "10.0",
		"Maximum hold time (seconds) for entities whose classname contains \"car\"",
		FCVAR_NONE, true, 1.0, true, 120.0);

	g_cvTimeWeapon = CreateConVar("l4d_pushdrag_hold_time_weapon", "30.0",
		"Maximum hold time (seconds) for weapon_* entities",
		FCVAR_NONE, true, 1.0, true, 120.0);

	g_cvTimePlayer = CreateConVar("l4d_pushdrag_hold_time_player", "15.0",
		"Maximum hold time (seconds) for player entities",
		FCVAR_NONE, true, 1.0, true, 120.0);

	g_cvTimeDefault = CreateConVar("l4d_pushdrag_hold_time_default", "10.0",
		"Maximum hold time (seconds) for every other entity",
		FCVAR_NONE, true, 1.0, true, 120.0);

	g_cvHoldForce = CreateConVar("l4d_pushdrag_hold_force", "0.2",
		"Pull force coefficient: speed = force * distance^2",
		FCVAR_NONE, true, 0.01, true, 2.0);

	g_cvHoldForceDist = CreateConVar("l4d_pushdrag_hold_force_dist", "100.0",
		"Distance clamp (units) used by the pull force",
		FCVAR_NONE, true, 10.0, true, 500.0);

	g_cvHoldMaxSpeed = CreateConVar("l4d_pushdrag_hold_max_speed", "2000.0",
		"Maximum speed (units/second) applied to a held non-player entity",
		FCVAR_NONE, true, 100.0, true, 4000.0);

	g_cvBreakDist = CreateConVar("l4d_pushdrag_break_dist", "350.0",
		"Release the hold when the entity is farther than this from the player (units)",
		FCVAR_NONE, true, 50.0, true, 2000.0);

	g_cvReleaseStop = CreateConVar("l4d_pushdrag_release_stop", "1",
		"Zero the artificial velocity when releasing, so the entity falls normally again (0/1)",
		FCVAR_NONE, true, 0.0, true, 1.0);

	g_cvLatencyComp = CreateConVar("l4d_pushdrag_latency_comp", "4.0",
		"Client velocity prediction multiplier used for the hold point",
		FCVAR_NONE, true, 0.0, true, 20.0);

	g_cvThrowForce = CreateConVar("l4d_pushdrag_throw_force", "2000.0",
		"Throw force used by the +speed right click strong throw",
		FCVAR_NONE, true, 0.0, true, 5000.0);

	g_cvThrowForceAttack2 = CreateConVar("l4d_pushdrag_throw_force_attack2", "200.0",
		"Throw force used by +attack2",
		FCVAR_NONE, true, 0.0, true, 5000.0);

	g_cvThrowForceBase = CreateConVar("l4d_pushdrag_throw_force_base", "200.0",
		"Minimum force added by a throw at maximum distance",
		FCVAR_NONE, true, 0.0, true, 2000.0);

	g_cvThrowFalloff = CreateConVar("l4d_pushdrag_throw_falloff_dist", "1000.0",
		"Distance (units) at which the throw force falls back to the base force",
		FCVAR_NONE, true, 100.0, true, 5000.0);

	g_cvDoubleTap = CreateConVar("l4d_pushdrag_double_tap_time", "0.3",
		"Seconds allowed between the two reload taps (normal and long range grab)",
		FCVAR_NONE, true, 0.1, true, 1.0);

	g_cvPhysicsAttacker = CreateConVar("l4d_pushdrag_physics_attacker", "0",
		"Write m_hPhysicsAttacker on thrown props so physics kills are credited (0/1); keep 0 to avoid launching players who stand on the prop",
		FCVAR_NONE, true, 0.0, true, 1.0);

	g_cvAttackerTime = CreateConVar("l4d_pushdrag_attacker_time", "1.5",
		"Seconds a thrown prop keeps its physics attacker before it is cleared",
		FCVAR_NONE, true, 0.0, true, 10.0);

	g_cvReleaseSettle = CreateConVar("l4d_pushdrag_release_settle", "1",
		"On release: zero angular velocity and re-sync the prop origin so it settles normally (0/1)",
		FCVAR_NONE, true, 0.0, true, 1.0);

	g_cvPlayerJumpEscape = CreateConVar("l4d_pushdrag_player_jump_escape", "1",
		"A held player can press jump to break free (0/1)",
		FCVAR_NONE, true, 0.0, true, 1.0);

	g_cvAdminOnly = CreateConVar("l4d_pushdrag_admin_only", "0",
		"Only admins may grab at all (0/1)",
		FCVAR_NONE, true, 0.0, true, 1.0);

	g_cvAdminOnlySpecial = CreateConVar("l4d_pushdrag_admin_only_special", "0",
		"Only admins may grab enemy special infected (0/1)",
		FCVAR_NONE, true, 0.0, true, 1.0);

	g_cvAdminOnlySpectator = CreateConVar("l4d_pushdrag_admin_only_spectator", "0",
		"Only admins may grab while spectating (0/1)",
		FCVAR_NONE, true, 0.0, true, 1.0);

	g_cvHoldDistSpecial = CreateConVar("l4d_pushdrag_hold_dist_special", "180.0",
		"Hold distance (units) when a survivor grabs an enemy special infected",
		FCVAR_NONE, true, 16.0, true, 1000.0);

	g_cvNoHeldDamage = CreateConVar("l4d_pushdrag_no_held_damage", "1",
		"Held props do not damage players until they are thrown (0/1)",
		FCVAR_NONE, true, 0.0, true, 1.0);

	g_cvFallProtect = CreateConVar("l4d_pushdrag_player_fall_protect", "3.0",
		"Seconds of fall damage protection after releasing a held player (0 = off)",
		FCVAR_NONE, true, 0.0, true, 10.0);

	g_cvLevelKey = CreateConVar("l4d_pushdrag_level_key", "1",
		"Pressing IN_ZOOM (sniper aim) levels the held object (0/1)",
		FCVAR_NONE, true, 0.0, true, 1.0);

	g_cvIncapAttackThrow = CreateConVar("l4d_pushdrag_incap_attack_throw", "0",
		"While incapped, +attack also throws the held object (fallback when attack2 is not sent) (0/1)",
		FCVAR_NONE, true, 0.0, true, 1.0);

	g_cvThrowSettle = CreateConVar("l4d_pushdrag_throw_settle", "1",
		"Clear a thrown prop's velocity once it stops, so the throw force cannot launch players later (0/1)",
		FCVAR_NONE, true, 0.0, true, 1.0);

	g_cvSound = CreateConVar("l4d_pushdrag_sound", "1",
		"Play the grab sound (0/1)",
		FCVAR_NONE, true, 0.0, true, 1.0);
}

void HookCvars()
{
	HookConVarChange(g_cvEnable, OnCvarChanged);
	HookConVarChange(g_cvVersusSurvivor, OnCvarChanged);
	HookConVarChange(g_cvVersusInfected, OnCvarChanged);
	HookConVarChange(g_cvPlayerGrab, OnCvarChanged);
	HookConVarChange(g_cvSpectatorGrab, OnCvarChanged);
	HookConVarChange(g_cvSpectatorGrabPlayers, OnCvarChanged);
	HookConVarChange(g_cvSurvivorGrabSpecial, OnCvarChanged);
	HookConVarChange(g_cvGrabRange, OnCvarChanged);
	HookConVarChange(g_cvFarGrabRange, OnCvarChanged);
	HookConVarChange(g_cvDistObject, OnCvarChanged);
	HookConVarChange(g_cvDistCar, OnCvarChanged);
	HookConVarChange(g_cvDistWeapon, OnCvarChanged);
	HookConVarChange(g_cvDistPlayer, OnCvarChanged);
	HookConVarChange(g_cvDistDefault, OnCvarChanged);
	HookConVarChange(g_cvTimeObject, OnCvarChanged);
	HookConVarChange(g_cvTimeCar, OnCvarChanged);
	HookConVarChange(g_cvTimeWeapon, OnCvarChanged);
	HookConVarChange(g_cvTimePlayer, OnCvarChanged);
	HookConVarChange(g_cvTimeDefault, OnCvarChanged);
	HookConVarChange(g_cvHoldForce, OnCvarChanged);
	HookConVarChange(g_cvHoldForceDist, OnCvarChanged);
	HookConVarChange(g_cvHoldMaxSpeed, OnCvarChanged);
	HookConVarChange(g_cvBreakDist, OnCvarChanged);
	HookConVarChange(g_cvReleaseStop, OnCvarChanged);
	HookConVarChange(g_cvLatencyComp, OnCvarChanged);
	HookConVarChange(g_cvThrowForce, OnCvarChanged);
	HookConVarChange(g_cvThrowForceAttack2, OnCvarChanged);
	HookConVarChange(g_cvThrowForceBase, OnCvarChanged);
	HookConVarChange(g_cvThrowFalloff, OnCvarChanged);
	HookConVarChange(g_cvDoubleTap, OnCvarChanged);
	HookConVarChange(g_cvPhysicsAttacker, OnCvarChanged);
	HookConVarChange(g_cvAttackerTime, OnCvarChanged);
	HookConVarChange(g_cvReleaseSettle, OnCvarChanged);
	HookConVarChange(g_cvPlayerJumpEscape, OnCvarChanged);
	HookConVarChange(g_cvAdminOnly, OnCvarChanged);
	HookConVarChange(g_cvAdminOnlySpecial, OnCvarChanged);
	HookConVarChange(g_cvAdminOnlySpectator, OnCvarChanged);
	HookConVarChange(g_cvHoldDistSpecial, OnCvarChanged);
	HookConVarChange(g_cvNoHeldDamage, OnCvarChanged);
	HookConVarChange(g_cvFallProtect, OnCvarChanged);
	HookConVarChange(g_cvLevelKey, OnCvarChanged);
	HookConVarChange(g_cvIncapAttackThrow, OnCvarChanged);
	HookConVarChange(g_cvThrowSettle, OnCvarChanged);
	HookConVarChange(g_cvSound, OnCvarChanged);
}

public void OnCvarChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	RefreshSettings();
}

public void OnConfigsExecuted()
{
	RefreshSettings();
}

public void OnMapStart()
{
	PrecacheSound(SOUND_GRAB, true);
	g_flLastFrame = GetGameTime();
	ResetState();
	RefreshSettings();
}

public void OnMapEnd()
{
	ReleaseAll();
}

public void OnPluginEnd()
{
	ReleaseAll();
}

public void OnClientDisconnect(int client)
{
	SDKUnhook(client, SDKHook_OnTakeDamage, OnTakeDamage);
	ReleaseHold(client, true, true);
	ClearPendingAttacker(client, true);
	g_iKeyState[client] = 0;
	g_iKeyBuffer[client] = 0;
	g_flKeyTime[client] = 0.0;
	g_iRawButtons[client] = 0;
	g_bRawValid[client] = false;
	g_flFallProtectUntil[client] = 0.0;
	g_bLevelMode[client] = false;
}

public void OnClientPutInServer(int client)
{
	g_iRawButtons[client] = 0;
	g_bRawValid[client] = false;
	g_flFallProtectUntil[client] = 0.0;
	g_bLevelMode[client] = false;
	SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
}

public void OnPlayerRunCmdPre(int client, int buttons, int impulse, const float vel[3], const float angles[3], int weapon, int subtype, int cmdnum, int tickcount, int seed, const int mouse[2])
{
	if (client < 1 || client > MaxClients)
	{
		return;
	}

	g_iRawButtons[client] = buttons;
	g_bRawValid[client] = true;
}

public Action OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype)
{
	if (victim <= 0 || victim > MaxClients)
	{
		return Plugin_Continue;
	}

	if (g_flFallProtectTime > 0.0 && (damagetype & DMG_FALL) && GetGameTime() <= g_flFallProtectUntil[victim])
	{
		return Plugin_Handled;
	}

	if (g_bNoHeldDamage && (IsHeldProp(attacker) || IsHeldProp(inflictor)))
	{
		return Plugin_Handled;
	}

	return Plugin_Continue;
}

public void Event_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
	ReleaseAll();
}

public void OnGameFrame()
{
	float now = GetGameTime();
	float dt = now - g_flLastFrame;
	if (dt < 0.0 || dt > 1.0)
	{
		dt = 0.0;
	}
	g_flLastFrame = now;

	// Pending physics-attacker clears run even while the plugin is disabled.
	for (int client = 1; client <= MaxClients; client++)
	{
		if (g_iAttackerRef[client] != HELD_NONE && now >= g_flAttackerClearAt[client])
		{
			ClearPendingAttacker(client, true);
		}
	}

	ProcessThrownSettles(now);

	if (!g_bEnabled)
	{
		return;
	}

	for (int client = 1; client <= MaxClients; client++)
	{
		if (!IsClientInGame(client) || IsFakeClient(client))
		{
			if (g_iHeldRef[client] != HELD_NONE)
			{
				ReleaseHold(client, true, true);
			}
			continue;
		}

		int team = GetClientTeam(client);
		bool active;
		if (team == 1)
		{
			// Spectators have no IsPlayerAlive requirement.
			active = g_bSpectatorGrab && (!g_bAdminOnlySpectator || IsClientAdmin(client));
		}
		else if (!IsPlayerAlive(client))
		{
			active = false;
		}
		else if (team == 2)
		{
			active = (g_iVersusSurvivor > 0);
		}
		else if (team == 3)
		{
			active = (g_iVersusInfected > 0 && !IsPlayerGhost(client));
		}
		else
		{
			active = false;
		}

		if (active && g_bAdminOnly && !IsClientAdmin(client))
		{
			active = false;
		}

		if (!active)
		{
			if (g_iHeldRef[client] != HELD_NONE)
			{
				ReleaseHold(client, true, true);
			}
			continue;
		}

		ProcessClient(client, now, dt);
	}
}

void ProcessClient(int client, float now, float dt)
{
	int prevButtons = g_iKeyBuffer[client];
	int buttons = g_bRawValid[client] ? g_iRawButtons[client] : GetClientButtons(client);
	bool startgrab = false;
	bool cancelHeld = false;

	// Double tap reload detection (same state machine as the original).
	if (g_iKeyState[client] == 0)
	{
		if ((buttons & IN_RELOAD) && !(g_iKeyBuffer[client] & IN_RELOAD))
		{
			g_iKeyState[client] = 1;
			g_flKeyTime[client] = now;
			cancelHeld = true;
		}
	}

	if (g_iKeyState[client] == 1)
	{
		if (now - g_flKeyTime[client] < g_flDoubleTap)
		{
			if (!(buttons & IN_RELOAD) && (g_iKeyBuffer[client] & IN_RELOAD))
			{
				g_iKeyState[client] = 2;
			}
		}
		else
		{
			g_iKeyState[client] = 0;
		}
	}

	if (g_iKeyState[client] == 2)
	{
		if (now - g_flKeyTime[client] < g_flDoubleTap)
		{
			if ((buttons & IN_RELOAD) && !(g_iKeyBuffer[client] & IN_RELOAD))
			{
				g_iKeyState[client] = 3;
				startgrab = true;
			}
		}
		else
		{
			g_iKeyState[client] = 0;
		}
	}

	if (g_iKeyState[client] == 3 && !(buttons & IN_RELOAD))
	{
		g_iKeyState[client] = 0;
	}

	int ent = EntRefToEntIndex(g_iHeldRef[client]);
	bool grabed = (ent > 0);

	// A single reload press drops whatever is being held.
	if (cancelHeld && grabed)
	{
		ReleaseHold(client, true, true);
		grabed = false;
		ent = 0;
	}

	g_iKeyBuffer[client] = buttons;

	if (startgrab)
	{
		// Never keep the previous target alive when a new grab starts.
		if (grabed)
		{
			ReleaseHold(client, true, true);
			grabed = false;
			ent = 0;
		}

		// +speed + double tap reload = long range grab.
		bool farGrab = (buttons & IN_SPEED) != 0;
		int target = GetGrabTarget(client, now, farGrab ? g_flFarGrabRange : g_flGrabRange, farGrab);
		if (target > 0)
		{
			int ref = EntIndexToEntRef(target);
			if (ref != HELD_NONE)
			{
				g_iHeldRef[client] = ref;
				ent = target;
				grabed = true;

				float vOrigin[3];
				GetClientEyePosition(client, vOrigin);
				if (g_bSound)
				{
					EmitSoundToAll(SOUND_GRAB, 0, SNDCHAN_WEAPON, SNDLEVEL_TRAFFIC, SND_NOFLAGS, SNDVOL_NORMAL, 100, -1, vOrigin, NULL_VECTOR, false, 0.0);
				}
			}
		}
	}

	if (grabed)
	{
		bool heldJumped = false;
		if (ent <= MaxClients && g_bPlayerJumpEscape && IsClientInGame(ent))
		{
			int heldButtons = g_bRawValid[ent] ? g_iRawButtons[ent] : GetClientButtons(ent);
			heldJumped = (heldButtons & IN_JUMP) != 0;
		}

		bool levelPressed = (g_bLevelKey && ent > MaxClients && (buttons & IN_ZOOM) && !(prevButtons & IN_ZOOM));
		bool incapThrow = (g_bIncapAttackThrow && IsClientIncapacitated(client) && (buttons & IN_ATTACK));

		if (levelPressed)
		{
			g_bLevelMode[client] = !g_bLevelMode[client];
			if (g_bLevelMode[client])
			{
				LevelHeldEntity(ent);
				PrintHintText(client, "%t", "LevelModeOn");
			}
			else
			{
				PrintHintText(client, "%t", "LevelModeOff");
			}
		}
		else if (heldJumped)
		{
			PrintHintText(client, "%t", "PlayerEscaped", ent);
			PrintHintText(ent, "%t", "YouEscaped");
			ReleaseHold(client, true, true);
		}
		else if ((buttons & IN_ATTACK2) || incapThrow)
		{
			// +speed + right click = strong throw; plain right click = normal throw.
			if (buttons & IN_SPEED)
			{
				ThrowEntity(client, ent, g_flThrowForce);
				PrintHintText(client, "%t", "StrongThrow");
			}
			else
			{
				ThrowEntity(client, ent, g_flThrowForceAttack2);
			}
			// A throw schedules a short physics-attacker window (if enabled).
			ReleaseHold(client, false, false);
		}
		else if (g_flHoldUntil[client] > 0.0 && now >= g_flHoldUntil[client])
		{
			ReleaseHold(client, true, true);
		}
		else if (!ApplyHoldPhysics(client, ent, dt))
		{
			ReleaseHold(client, true, true);
		}

		if (g_bLevelMode[client] && g_iHeldRef[client] != HELD_NONE && ent > MaxClients)
		{
			LevelHeldEntity(ent);
		}
	}
	else if (g_iHeldRef[client] != HELD_NONE)
	{
		// The entity disappeared between frames; clear the stale reference.
		ReleaseHold(client, false, false);
	}
}

int GetGrabTarget(int client, float now, float maxRange, bool farGrab)
{
	float origin[3];
	GetClientEyePosition(client, origin);

	float angles[3];
	GetClientEyeAngles(client, angles);

	Handle trace = TR_TraceRayFilterEx(origin, angles, MASK_SOLID, RayType_Infinite, TraceRayDontHitSelf, client);
	int ent = 0;

	if (TR_DidHit(trace))
	{
		float pos[3];
		TR_GetEndPosition(pos, trace);
		int hit = TR_GetEntityIndex(trace);
		float dist = GetVectorDistance(origin, pos);

		if (hit <= 0)
		{
			PrintHintText(client, "%t", "NothingGrabbed");
		}
		else if (dist > maxRange)
		{
			PrintHintText(client, "%t", "TooFar");
		}
		else
		{
			char classname[64];
			GetEdictClassname(hit, classname, sizeof(classname));

			if (IsMechanismClass(classname))
			{
				PrintHintText(client, "%t", "MechanismBlocked");
			}
			else if (StrContains(classname, "ladder") == -1
				&& StrContains(classname, "door") == -1
				&& StrContains(classname, "infected") == -1)
			{
				ent = ValidateGrabTarget(client, hit, classname, now, maxRange, farGrab);
			}
		}
	}

	delete trace;
	return ent;
}

int ValidateGrabTarget(int client, int hit, const char[] classname, float now, float maxRange, bool farGrab)
{
	int type = GrabType_Default;

	if (StrContains(classname, "prop_") != -1)
	{
		type = GrabType_Object;
	}
	if (StrContains(classname, "car") != -1)
	{
		type = GrabType_Car;
	}
	if (StrContains(classname, "weapon_") != -1)
	{
		type = GrabType_Weapon;
	}
	if (hit <= MaxClients)
	{
		type = GrabType_Player;
	}

	int clientTeam = GetClientTeam(client);
	int grabmode;
	if (clientTeam == 1)
	{
		// Spectators use "all" for object grabs; player targets are still
		// blocked by the team check below.
		grabmode = 3;
	}
	else
	{
		grabmode = (clientTeam == 2) ? g_iVersusSurvivor : g_iVersusInfected;
	}

	bool enemySpecial = false;

	if (type == GrabType_Player)
	{
		if (!g_bPlayerGrab)
		{
			PrintHintText(client, "%t", "PlayersDisabled");
			return 0;
		}
		if (!IsClientInGame(hit) || !IsPlayerAlive(hit) || IsPlayerGhost(hit))
		{
			PrintHintText(client, "%t", "PlayerDead");
			return 0;
		}
		if (grabmode != 2 && grabmode != 3)
		{
			PrintHintText(client, "%t", "PlayersDisabled");
			return 0;
		}
		if (GetClientTeam(client) != GetClientTeam(hit))
		{
			// Survivors may grab enemy special infected when allowed; spectators
			// may grab any player when the spectator-player cvar is on.
			bool spectatorAllowed = (clientTeam == 1 && g_bSpectatorGrabPlayers);
			enemySpecial = (g_bSurvivorGrabSpecial
				&& clientTeam == 2
				&& GetClientTeam(hit) == 3
				&& (!g_bAdminOnlySpecial || IsClientAdmin(client)));
			if (!spectatorAllowed && !enemySpecial)
			{
				PrintHintText(client, "%t", "EnemyGrab");
				return 0;
			}
		}

		PrintHintText(client, "%t", "GrabPlayer", hit);
		PrintHintText(hit, "%t", "GrabbedBy", client);
	}
	else
	{
		if (grabmode != 1 && grabmode != 3)
		{
			PrintHintText(client, "%t", "ObjectsDisabled");
			return 0;
		}
		PrintHintText(client, "%t", "GrabObject");
	}

	g_iHeldType[client] = type;
	g_flHoldDist[client] = enemySpecial ? g_flDistSpecial : g_flDist[type];
	g_flHoldUntil[client] = now + g_flHoldTime[type];

	// A long range grab starts far away, so it needs a larger break distance
	// for the first frames; otherwise the hold would be dropped immediately.
	g_flHoldBreak[client] = g_flBreakDist;
	if (farGrab)
	{
		// The trace reports the hit point, while the hold check uses the entity
		// origin; large props/cars need a margin or they would be dropped
		// immediately after a 1000 unit grab.
		float farLimit = maxRange + 300.0;
		if (farLimit > g_flHoldBreak[client])
		{
			g_flHoldBreak[client] = farLimit;
		}
	}
	return hit;
}

bool ApplyHoldPhysics(int client, int ent, float dt)
{
	if (ent <= MaxClients)
	{
		if (!IsClientInGame(ent) || !IsPlayerAlive(ent) || IsPlayerGhost(ent))
		{
			return false;
		}
	}

	float eye[3];
	float angles[3];
	float pos[3];
	GetClientEyePosition(client, eye);
	GetClientEyeAngles(client, angles);
	GetEntityOrigin(ent, pos);

	// Never yank an entity from the other side of the map. Long range grabs
	// get a per-hold limit so the first frames are not dropped instantly;
	// once the entity gets close, the normal limit applies again.
	float holdDistance = GetVectorDistance(eye, pos);
	if (g_flBreakDist > 0.0 && g_flHoldBreak[client] > g_flBreakDist && holdDistance <= g_flBreakDist)
	{
		g_flHoldBreak[client] = g_flBreakDist;
	}
	if (g_flHoldBreak[client] > 0.0 && holdDistance > g_flHoldBreak[client])
	{
		return false;
	}

	// Latency compensation: extrapolate the player's eye a little.
	if (g_flLatencyComp > 0.0 && g_iVelocity > 0)
	{
		float clientVel[3];
		GetEntDataVector(client, g_iVelocity, clientVel);
		ScaleVector(clientVel, dt * g_flLatencyComp);
		AddVectors(eye, clientVel, eye);
	}

	// Hold point: eye + view direction * hold distance.
	float viewDir[3];
	GetAngleVectors(angles, viewDir, NULL_VECTOR, NULL_VECTOR);
	NormalizeVector(viewDir, viewDir);
	ScaleVector(viewDir, g_flHoldDist[client]);
	AddVectors(eye, viewDir, eye);

	float delta[3];

	// Full 3D spring velocity (the old levitation behaviour, players included),
	// capped so a bad cvar or a zero distance can never feed an insane / NaN
	// velocity into VPhysics.
	SubtractVectors(eye, pos, delta);
	float dist = GetVectorLength(delta);
	float speed = 0.0;
	if (dist >= 1.0 && g_flHoldForceDist > 0.0)
	{
		float clampDist = (dist > g_flHoldForceDist) ? g_flHoldForceDist : dist;
		speed = g_flHoldForce * clampDist * clampDist;
		if (speed > g_flHoldMaxSpeed)
		{
			speed = g_flHoldMaxSpeed;
		}
	}

	if (speed > 0.0)
	{
		NormalizeVector(delta, delta);
		ScaleVector(delta, speed);
	}
	else
	{
		delta[0] = 0.0;
		delta[1] = 0.0;
		delta[2] = 0.0;
	}

	TeleportEntity(ent, NULL_VECTOR, NULL_VECTOR, delta);
	return true;
}

void ThrowEntity(int client, int ent, float force)
{
	float eye[3];
	float angles[3];
	float pos[3];
	GetClientEyePosition(client, eye);
	GetClientEyeAngles(client, angles);
	GetEntityOrigin(ent, pos);

	float falloff = (g_flThrowFalloff > 1.0) ? g_flThrowFalloff : 1.0;
	float dist = GetVectorDistance(eye, pos);
	if (dist > falloff)
	{
		dist = falloff;
	}

	float finalForce = force * (falloff - dist) / falloff + g_flThrowForceBase;

	float dir[3];
	SubtractVectors(pos, eye, dir);
	if (GetVectorLength(dir) < 1.0)
	{
		GetAngleVectors(angles, dir, NULL_VECTOR, NULL_VECTOR);
	}

	NormalizeVector(dir, dir);
	ScaleVector(dir, finalForce);
	TeleportEntity(ent, NULL_VECTOR, NULL_VECTOR, dir);

	if (ent > MaxClients)
	{
		if (g_bPhysicsAttacker)
		{
			MarkPhysicsAttacker(ent, client);
			ScheduleAttackerClear(client, ent);
		}
		else
		{
			ClearPhysicsAttacker(ent);
		}

		RecordThrownProp(ent);
	}
}

void MarkPhysicsAttacker(int ent, int client)
{
	if (!g_bPhysicsAttacker || ent <= 0 || ent > MaxClients)
	{
		return;
	}

	char classname[64];
	GetEdictClassname(ent, classname, sizeof(classname));
	if (StrContains(classname, "prop_") == -1)
	{
		return;
	}

	SetEntPropEnt(ent, Prop_Data, "m_hPhysicsAttacker", client);
	// The engine compares this stamp against gpGlobals->curtime, which is
	// GetGameTime(), not GetEngineTime().
	SetEntPropFloat(ent, Prop_Data, "m_flLastPhysicsInfluenceTime", GetGameTime());
}

void ClearPhysicsAttacker(int ent)
{
	if (ent <= 0 || ent > MaxClients)
	{
		return;
	}

	char classname[64];
	GetEdictClassname(ent, classname, sizeof(classname));
	if (StrContains(classname, "prop_") == -1)
	{
		return;
	}

	// Always clear: any stale "recently physgunned by a player" state makes the
	// engine shove players who touch the prop. Use a far-past stamp instead of
	// 0.0 because HasPhysicsAttacker(5.0) treats 0.0 as recent during the first
	// five seconds of a map.
	SetEntPropEnt(ent, Prop_Data, "m_hPhysicsAttacker", -1);
	SetEntPropFloat(ent, Prop_Data, "m_flLastPhysicsInfluenceTime", GetGameTime() - 60.0);
}

void ScheduleAttackerClear(int client, int ent)
{
	ClearPendingAttacker(client, true);
	g_iAttackerRef[client] = EntIndexToEntRef(ent);
	g_flAttackerClearAt[client] = GetGameTime() + g_flAttackerTime;

	if (g_flAttackerTime <= 0.0)
	{
		ClearPendingAttacker(client, true);
	}
}

void ClearPendingAttacker(int client, bool clearEntity)
{
	if (client < 1 || client > MaxClients)
	{
		return;
	}

	if (g_iAttackerRef[client] != HELD_NONE)
	{
		if (clearEntity)
		{
			int ent = EntRefToEntIndex(g_iAttackerRef[client]);
			if (ent > 0)
			{
				ClearPhysicsAttacker(ent);
			}
		}
		g_iAttackerRef[client] = HELD_NONE;
		g_flAttackerClearAt[client] = 0.0;
	}
}

void ClearAllPendingAttackers(bool clearEntity)
{
	for (int client = 1; client <= MaxClients; client++)
	{
		ClearPendingAttacker(client, clearEntity);
	}
}

void ReleaseHold(int client, bool drop, bool clearAttacker)
{
	int ent = EntRefToEntIndex(g_iHeldRef[client]);

	if (ent > 0)
	{
		if (ent <= MaxClients && g_flFallProtectTime > 0.0 && IsClientInGame(ent))
		{
			g_flFallProtectUntil[ent] = GetGameTime() + g_flFallProtectTime;
			if (HasEntProp(ent, Prop_Send, "m_flFallVelocity"))
			{
				SetEntPropFloat(ent, Prop_Send, "m_flFallVelocity", 0.0);
			}
		}

		if (drop && g_bReleaseStop)
		{
			if (ent <= MaxClients)
			{
				// Only stop the horizontal drag: keep the vertical velocity so a
				// falling player keeps falling instead of hanging in the air.
				if (IsClientInGame(ent) && g_iVelocity > 0)
				{
					float vel[3];
					GetEntDataVector(ent, g_iVelocity, vel);
					vel[0] = 0.0;
					vel[1] = 0.0;
					TeleportEntity(ent, NULL_VECTOR, NULL_VECTOR, vel);
				}
			}
			else
			{
				float stop[3] = {0.0, 0.0, 0.0};
				if (g_bReleaseSettle)
				{
					float pos[3];
					GetEntityOrigin(ent, pos);
					if (HasEntProp(ent, Prop_Data, "m_vecAngVelocity"))
					{
						SetEntPropVector(ent, Prop_Data, "m_vecAngVelocity", stop);
					}
					// Re-sync the physics body at its current origin so a sleeping
					// prop cannot keep an old velocity/state.
					TeleportEntity(ent, pos, NULL_VECTOR, stop);
				}
				else
				{
					TeleportEntity(ent, NULL_VECTOR, NULL_VECTOR, stop);
				}
			}
		}

		if (clearAttacker)
		{
			ClearPendingAttacker(client, true);
			ClearPhysicsAttacker(ent);
		}
	}

	g_iHeldRef[client] = HELD_NONE;
	g_iHeldType[client] = GrabType_None;
	g_flHoldDist[client] = 0.0;
	g_flHoldUntil[client] = 0.0;
	g_flHoldBreak[client] = 0.0;
	g_bLevelMode[client] = false;
}

void ReleaseAll()
{
	for (int client = 1; client <= MaxClients; client++)
	{
		if (g_iHeldRef[client] != HELD_NONE)
		{
			ReleaseHold(client, true, true);
		}
	}
	ClearAllPendingAttackers(true);
}

void ResetState()
{
	for (int client = 0; client <= MaxClients; client++)
	{
		g_iHeldRef[client] = HELD_NONE;
		g_iHeldType[client] = GrabType_None;
		g_flHoldDist[client] = 0.0;
		g_flHoldUntil[client] = 0.0;
		g_flHoldBreak[client] = 0.0;
		g_iKeyState[client] = 0;
		g_iKeyBuffer[client] = 0;
		g_flKeyTime[client] = 0.0;
		g_iAttackerRef[client] = HELD_NONE;
		g_flAttackerClearAt[client] = 0.0;
	}

	for (int i = 0; i <= MaxClients; i++)
	{
		g_iRawButtons[i] = 0;
		g_bRawValid[i] = false;
		g_flFallProtectUntil[i] = 0.0;
		g_bLevelMode[i] = false;
	}

	g_iThrownNext = 0;
	for (int i = 0; i < THROWN_MAX; i++)
	{
		g_iThrownRef[i] = HELD_NONE;
		g_flThrownAt[i] = 0.0;
	}
}

void GetEntityOrigin(int ent, float pos[3])
{
	if (ent <= MaxClients)
	{
		GetClientAbsOrigin(ent, pos);
	}
	else
	{
		GetEntPropVector(ent, Prop_Send, "m_vecOrigin", pos);
	}
}

bool IsPlayerGhost(int client)
{
	if (!g_bL4D2 || g_iGhostOffset <= 0)
	{
		return false;
	}
	return GetEntData(client, g_iGhostOffset, 1) != 0;
}

bool IsClientAdmin(int client)
{
	return CheckCommandAccess(client, "sm_pushdrag_admin", ADMFLAG_GENERIC);
}

bool IsHeldProp(int ent)
{
	if (ent <= MaxClients)
	{
		return false;
	}

	for (int client = 1; client <= MaxClients; client++)
	{
		if (g_iHeldRef[client] == HELD_NONE)
		{
			continue;
		}
		if (EntRefToEntIndex(g_iHeldRef[client]) == ent)
		{
			return true;
		}
	}
	return false;
}

bool IsClientIncapacitated(int client)
{
	if (!g_bL4D2 || g_iIncapOffset <= 0)
	{
		return false;
	}
	return GetEntData(client, g_iIncapOffset, 1) != 0;
}

void LevelHeldEntity(int ent)
{
	float angles[3];
	GetEntPropVector(ent, Prop_Send, "m_angRotation", angles);
	angles[0] = 0.0;
	angles[2] = 0.0;

	float zero[3] = {0.0, 0.0, 0.0};
	if (HasEntProp(ent, Prop_Data, "m_vecAngVelocity"))
	{
		SetEntPropVector(ent, Prop_Data, "m_vecAngVelocity", zero);
	}

	TeleportEntity(ent, NULL_VECTOR, angles, NULL_VECTOR);
}

bool IsMechanismClass(const char[] classname)
{
	return (StrContains(classname, "func_") == 0
		|| StrContains(classname, "trigger_") == 0
		|| StrContains(classname, "logic_") == 0
		|| StrContains(classname, "info_") == 0
		|| StrContains(classname, "env_") == 0
		|| StrContains(classname, "point_") == 0
		|| StrContains(classname, "ambient_") == 0
		|| StrContains(classname, "sky_") == 0
		|| StrContains(classname, "water") == 0
		|| StrContains(classname, "prop_dynamic") == 0
		|| StrContains(classname, "prop_static") == 0);
}

void SettlePropEntity(int ent)
{
	if (ent <= MaxClients)
	{
		return;
	}

	float pos[3];
	float stop[3] = {0.0, 0.0, 0.0};
	GetEntityOrigin(ent, pos);
	if (HasEntProp(ent, Prop_Data, "m_vecAngVelocity"))
	{
		SetEntPropVector(ent, Prop_Data, "m_vecAngVelocity", stop);
	}
	TeleportEntity(ent, pos, NULL_VECTOR, stop);
	ClearPhysicsAttacker(ent);
}

void RecordThrownProp(int ent)
{
	if (ent <= MaxClients)
	{
		return;
	}

	int ref = EntIndexToEntRef(ent);
	if (ref == HELD_NONE)
	{
		return;
	}

	for (int i = 0; i < THROWN_MAX; i++)
	{
		if (g_iThrownRef[i] == ref)
		{
			g_flThrownAt[i] = GetGameTime();
			GetEntityOrigin(ent, g_flThrownPos[i]);
			return;
		}
	}

	g_iThrownRef[g_iThrownNext] = ref;
	g_flThrownAt[g_iThrownNext] = GetGameTime();
	GetEntityOrigin(ent, g_flThrownPos[g_iThrownNext]);
	g_iThrownNext = (g_iThrownNext + 1) % THROWN_MAX;
}

void ProcessThrownSettles(float now)
{
	if (!g_bThrowSettle)
	{
		return;
	}

	for (int i = 0; i < THROWN_MAX; i++)
	{
		if (g_iThrownRef[i] == HELD_NONE)
		{
			continue;
		}

		int ent = EntRefToEntIndex(g_iThrownRef[i]);
		if (ent <= 0)
		{
			g_iThrownRef[i] = HELD_NONE;
			g_flThrownAt[i] = 0.0;
			continue;
		}

		// Do not touch a prop that was grabbed again.
		if (IsHeldProp(ent))
		{
			g_iThrownRef[i] = HELD_NONE;
			g_flThrownAt[i] = 0.0;
			continue;
		}

		float elapsed = now - g_flThrownAt[i];
		if (elapsed < 0.0)
		{
			elapsed = 0.0;
		}

		float pos[3];
		GetEntityOrigin(ent, pos);
		float moved = GetVectorDistance(pos, g_flThrownPos[i]);

		if ((elapsed >= 0.3 && moved < 2.0) || elapsed >= 2.0)
		{
			SettlePropEntity(ent);
			g_iThrownRef[i] = HELD_NONE;
			g_flThrownAt[i] = 0.0;
			continue;
		}

		GetEntityOrigin(ent, g_flThrownPos[i]);
	}
}

public bool TraceRayDontHitSelf(int entity, int mask, any data)
{
	if (entity == data)
	{
		return false;
	}

	// Spectator cameras sit inside the spectated player; skip player entities so
	// spectators can grab props instead of hitting an "enemy" player.
	if (entity > 0 && entity <= MaxClients)
	{
		int grabberTeam = GetClientTeam(data);
		if (grabberTeam == 1)
		{
			if (!g_bSpectatorGrabPlayers)
			{
				return false;
			}

			// Skip only the spectated player (the camera sits inside them) so
			// other players, special infected and props remain reachable.
			int observerTarget = GetEntPropEnt(data, Prop_Send, "m_hObserverTarget");
			if (observerTarget > 0 && entity == observerTarget)
			{
				return false;
			}

			return true;
		}

		// An incapped grabber's low camera often hits the special infected on
		// top of them; skip enemy players so teammates behind remain reachable.
		if (IsClientIncapacitated(data) && GetClientTeam(entity) != grabberTeam)
		{
			return false;
		}
	}

	return true;
}

void RefreshSettings()
{
	bool wasEnabled = g_bEnabled;

	g_bEnabled = g_cvEnable.BoolValue;
	g_bPlayerGrab = g_cvPlayerGrab.BoolValue;
	g_bReleaseStop = g_cvReleaseStop.BoolValue;
	g_bPhysicsAttacker = g_cvPhysicsAttacker.BoolValue;
	g_bSpectatorGrab = g_cvSpectatorGrab.BoolValue;
	g_bSpectatorGrabPlayers = g_cvSpectatorGrabPlayers.BoolValue;
	g_bSurvivorGrabSpecial = g_cvSurvivorGrabSpecial.BoolValue;
	g_bReleaseSettle = g_cvReleaseSettle.BoolValue;
	g_bPlayerJumpEscape = g_cvPlayerJumpEscape.BoolValue;
	g_bAdminOnly = g_cvAdminOnly.BoolValue;
	g_bAdminOnlySpecial = g_cvAdminOnlySpecial.BoolValue;
	g_bAdminOnlySpectator = g_cvAdminOnlySpectator.BoolValue;
	g_bNoHeldDamage = g_cvNoHeldDamage.BoolValue;
	g_flFallProtectTime = g_cvFallProtect.FloatValue;
	g_bLevelKey = g_cvLevelKey.BoolValue;
	g_bIncapAttackThrow = g_cvIncapAttackThrow.BoolValue;
	g_bThrowSettle = g_cvThrowSettle.BoolValue;
	g_bSound = g_cvSound.BoolValue;

	g_flGrabRange = g_cvGrabRange.FloatValue;
	g_flFarGrabRange = g_cvFarGrabRange.FloatValue;
	g_flDistSpecial = g_cvHoldDistSpecial.FloatValue;
	g_flHoldForce = g_cvHoldForce.FloatValue;
	g_flHoldForceDist = g_cvHoldForceDist.FloatValue;
	g_flHoldMaxSpeed = g_cvHoldMaxSpeed.FloatValue;
	g_flBreakDist = g_cvBreakDist.FloatValue;
	g_flLatencyComp = g_cvLatencyComp.FloatValue;
	g_flThrowForce = g_cvThrowForce.FloatValue;
	g_flThrowForceAttack2 = g_cvThrowForceAttack2.FloatValue;
	g_flThrowForceBase = g_cvThrowForceBase.FloatValue;
	g_flThrowFalloff = g_cvThrowFalloff.FloatValue;
	g_flDoubleTap = g_cvDoubleTap.FloatValue;
	g_flAttackerTime = g_cvAttackerTime.FloatValue;

	g_flDist[GrabType_None] = 0.0;
	g_flDist[GrabType_Object] = g_cvDistObject.FloatValue;
	g_flDist[GrabType_Car] = g_cvDistCar.FloatValue;
	g_flDist[GrabType_Weapon] = g_cvDistWeapon.FloatValue;
	g_flDist[GrabType_Player] = g_cvDistPlayer.FloatValue;
	g_flDist[GrabType_Default] = g_cvDistDefault.FloatValue;

	g_flHoldTime[GrabType_None] = 0.0;
	g_flHoldTime[GrabType_Object] = g_cvTimeObject.FloatValue;
	g_flHoldTime[GrabType_Car] = g_cvTimeCar.FloatValue;
	g_flHoldTime[GrabType_Weapon] = g_cvTimeWeapon.FloatValue;
	g_flHoldTime[GrabType_Player] = g_cvTimePlayer.FloatValue;
	g_flHoldTime[GrabType_Default] = g_cvTimeDefault.FloatValue;

	g_iVersusSurvivor = g_cvVersusSurvivor.IntValue;
	g_iVersusInfected = g_cvVersusInfected.IntValue;

	g_iGameMode = 0;
	if (g_cvGameMode != null)
	{
		char mode[32];
		g_cvGameMode.GetString(mode, sizeof(mode));

		if (StrEqual(mode, "survival", false))
		{
			g_iGameMode = 3;
		}
		else if (StrEqual(mode, "versus", false)
			|| StrEqual(mode, "teamversus", false)
			|| StrEqual(mode, "scavenge", false)
			|| StrEqual(mode, "teamscavenge", false))
		{
			g_iGameMode = 2;
		}
		else if (StrEqual(mode, "coop", false) || StrEqual(mode, "realism", false))
		{
			g_iGameMode = 1;
		}
	}

	// Outside competitive modes survivors have always been able to grab.
	if (g_iGameMode != 2)
	{
		g_iVersusSurvivor = 3;
	}

	if (wasEnabled && !g_bEnabled)
	{
		ReleaseAll();
		for (int client = 1; client <= MaxClients; client++)
		{
			g_iKeyState[client] = 0;
			g_iKeyBuffer[client] = 0;
		}
	}
}
