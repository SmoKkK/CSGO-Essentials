/**
 *
 * Alyx Network - CS:GO Essentials
 * A comprehensive server management plugin for Counter-Strike: Global Offensive.
 *
 * Features:
 * - Block Fake-Duck
 * - Force Lag Compensation 0 (also known as disable AX)
 * - Block Untrusted Angles
 * - Block Roll Angles
 * - Block Lag Peek
 * - Prevent Air Stuck
 * - Normalize Angles
 * - Latency management
 *
 * My discord: dragos112
 * Website: https://alyx.ro/
 * Repository: https://github.com/hiraeeth/CSGO-Essentials
 *
 */

#include <sourcemod>
#include <cstrike>
#include <sdktools_gamerules>
#include <sdktools>

#define VERSION			   "1.8.0"
#define MAX_ANGLES_WARNING 5

#define CS_TEAM_NONE	   0
#define CS_TEAM_SPECTATOR  1
#define CS_TEAM_T		   2
#define CS_TEAM_CT		   3

ConVar g_cvBlockAX;
ConVar g_cvWarnAX;

ConVar g_cvBlockUntrustedAngles;
ConVar g_cvWarnUntrustedAngles;

ConVar g_cvBlockRollAngles;
ConVar g_cvWarnRollAngles;

ConVar g_cvBlockAirStuck;
ConVar g_cvWarnAirStuck;

ConVar g_cvMaxLatency;
ConVar g_cvMaxLatencyWarnings;

ConVar g_cvBlockFakeDuck;
ConVar g_cvBlockLagPeek;
ConVar g_cvNormalizeAngles;

int g_iLatencyWarnings[MAXPLAYERS + 1] = { 0, ... };
float g_flLastLatencyWarningTime[MAXPLAYERS + 1] = { 0.0, ... };
float g_flLastUntrustedAnglesWarningTime[MAXPLAYERS + 1] = { 0.0, ... };	// ignore the long name

int g_iAngleWarnings[MAXPLAYERS + 1][3];
float g_flLastAngleWarningTime[MAXPLAYERS + 1][3];

int WarningType_UNTRUSTED_ANGLES = 1;
int WarningType_ROLL_ANGLES = 2;

stock bool clamp(float &value, float min, float max)
{
	float bk = value;
	if (value > max) value = max;
	else if (value < min) value = min;

	return bk != value;
}

enum struct Vec3
{
	float x;
	float y;
	float z;

	void From(const float array[3]){
		this.x = array[0];
		this.y = array[1];
		this.z = array[2]; }

void To(float array[3])
{
	array[0] = this.x;
	array[1] = this.y;
	array[2] = this.z;
}

void Set(float x, float y, float z)
{
	this.x = x;
	this.y = y;
	this.z = z;
}

bool Equals(const Vec3 other)
{
	return this.x == other.x && this.y == other.y && this.z == other.z;
}

void Clamp(float min, float max)
{
	clamp(this.x, min, max);
	clamp(this.y, min, max);
	clamp(this.z, min, max);
}

void Reset()
{
	this.x = 0.0;
	this.y = 0.0;
	this.z = 0.0;
}
}

ArrayList g_LagRecords;
enum struct LagRecord
{
	float m_flShotTime;
	Vec3 m_vecOrigin;
}

void BackupRound()
{
	ServerCommand("mp_backup_round_file \"\"");
	ServerCommand("mp_backup_round_file_last \"\"");
	ServerCommand("mp_backup_round_file_pattern \"\"");
	ServerCommand("mp_backup_round_auto 0");
}

public Plugin myinfo =
{
	name = "[Alyx-Network] Essentials",
	author = "dragos112 & unknowncheats & other developers",
	description = "Essentials for any hvh server",
	version = VERSION
};

int g_flSimulationTimeOffset = -1;

public void OnPluginStart()
{
	g_cvBlockAX = CreateConVar("sm_essentials_ax", "1", "Move to spectators and force lagcomp on every client.", FCVAR_PROTECTED, true, 0.0, true, 1.0);
	g_cvWarnAX = CreateConVar("sm_essentials_warn_ax", "1", "Warn players about AX", FCVAR_PROTECTED, true, 0.0, true, 1.0);

	g_cvBlockUntrustedAngles = CreateConVar("sm_essentials_unstrusted_angles", "1", "Block untrusted angles", FCVAR_PROTECTED, true, 0.0, true, 1.0);
	g_cvWarnUntrustedAngles = CreateConVar("sm_essentials_unstrusted_angles_warn", "1", "Warn players about untrusted angles", FCVAR_PROTECTED, true, 0.0, true, 1.0);

	g_cvBlockRollAngles = CreateConVar("sm_essentials_roll", "1", "Block roll angles", FCVAR_PROTECTED, true, 0.0, true, 1.0);
	g_cvWarnRollAngles = CreateConVar("sm_essentials_roll_warn", "0", "Warn players about roll angles", FCVAR_PROTECTED, true, 0.0, true, 1.0);

	g_cvBlockAirStuck = CreateConVar("sm_essentials_airstuck", "1", "Block air stuck", FCVAR_PROTECTED, true, 0.0, true, 1.0);
	g_cvWarnAirStuck = CreateConVar("sm_essentials_airstuck_warn", "0", "Warn players about air stuck", FCVAR_PROTECTED, true, 0.0, true, 1.0);

	g_cvBlockFakeDuck = CreateConVar("sm_essentials_fd", "0", "Stop people from using fake-duck.", FCVAR_PROTECTED, true, 0.0, true, 1.0);
	g_cvBlockLagPeek = CreateConVar("sm_essentials_lag_peek", "0", "Block lag peek", FCVAR_PROTECTED, true, 0.0, true, 1.0);
	g_cvNormalizeAngles = CreateConVar("sm_essentials_normalize_angles", "0", "Normalize angles", FCVAR_PROTECTED, true, 0.0, true, 1.0);
	g_cvMaxLatency = CreateConVar("sm_essentials_max_latency", "200", "Max latency in milliseconds", FCVAR_PROTECTED, true, 100.0, true, 1000.0);
	g_cvMaxLatencyWarnings = CreateConVar("sm_essentials_max_latency_warnings", "10", "Max latency warnings before kick", FCVAR_PROTECTED, true, 1.0, true, 100.0);

	g_flSimulationTimeOffset = FindSendPropInfo("CCSPlayer", "m_flSimulationTime");
	if (g_flSimulationTimeOffset == -1)
		SetFailState("Failed to find m_flSimulationTime offset!");

	g_LagRecords = new ArrayList(sizeof(LagRecord));

	BackupRound();
	HookEvent("player_spawn", PlayerSpawn);
	AddCommandListener(JoinTeam, "jointeam");

	LogMessage("Successfully loaded. Version: %s", VERSION);
	CreateTimer(1.0, CheckClientLatency, _, TIMER_REPEAT);
}

public Action CheckClientLatency(Handle timer)
{
	for (int client = 1; client <= MaxClients; client++)
	{
		if (!IsValidClient(client) || GetClientTeam(client) <= CS_TEAM_SPECTATOR)
			continue;

		int latency = RoundToNearest(GetClientLatency(client, NetFlow_Both) * 1000.0);
		if (latency > g_cvMaxLatency.IntValue)
		{
			float currentTime = GetGameTime();
			if (currentTime - g_flLastLatencyWarningTime[client] >= 5.0)
			{
				g_iLatencyWarnings[client]++;
				PrintToChat(client, " \x09Warning! \x08Your latency is too high: \x09%d ms \x08(max: \x09%d ms\x08)",
							latency, g_cvMaxLatency.IntValue);
				LogMessage("Client %d has high latency: %d ms (max: %d ms)", client, latency, g_cvMaxLatency.IntValue);

				g_flLastLatencyWarningTime[client] = currentTime;
				if (g_iLatencyWarnings[client] >= g_cvMaxLatencyWarnings.IntValue)
				{
					PrintToChat(client, " \x09Warning! \x08You have been \x09moved to spectators \x08due to \x09high latency\x08.");
					ChangeClientTeam(client, CS_TEAM_SPECTATOR);
					LogMessage("Client %d has been moved to spectators due to high latency", client);
					g_iLatencyWarnings[client] = 0;
				}
			}
		}
		else
			g_iLatencyWarnings[client] = 0;
	}

	return Plugin_Continue;
}

public void OnMapStart()
{
	BackupRound();
}

void RecordDataIntoTrack(int client)
{
	if (!IsValidClient(client))
		return;

	float curtime = GetGameTime();

	ConVar cvar = FindConVar("sv_maxunlag");
	float maxunlag = cvar.FloatValue;

	float flDeadTime = curtime - maxunlag;
	float vecOrigin[3];
	GetEntPropVector(client, Prop_Send, "m_vecOrigin", vecOrigin);

	Vec3 origin;
	origin.From(vecOrigin);

	float flSimulationTime = GetEntPropFloat(client, Prop_Data, "m_flSimulationTime");
	float flShotTime = GetShotTime(client);

	for (int i = g_LagRecords.Length - 1; i >= 0; i--)
	{
		LagRecord tail;
		g_LagRecords.GetArray(i, tail, sizeof(tail));

		if (tail.m_flShotTime >= flDeadTime)
			break;

		g_LagRecords.Erase(i);
	}

	LagRecord data;
	if (g_LagRecords.Length > 0)
	{
		LagRecord head;
		g_LagRecords.GetArray(g_LagRecords.Length - 1, head, sizeof(head));

		if (flSimulationTime <= head.m_flShotTime && !head.m_vecOrigin.Equals(origin) && flShotTime == data.m_flShotTime)
			SetEntProp(client, Prop_Send, "m_flSimulationTime", RoundToNearest(head.m_flShotTime + GetTickInterval()));
	}

	data.m_vecOrigin.From(vecOrigin);
	data.m_flShotTime = flShotTime;

	LagRecord newRecord;
	newRecord.m_flShotTime = flShotTime;
	newRecord.m_vecOrigin.From(vecOrigin);

	g_LagRecords.PushArray(newRecord, sizeof(newRecord));
}

void CheckAX(int client)
{
	if (!IsPlayerAlive(client) || GetClientTeam(client) == CS_TEAM_NONE || GetClientTeam(client) == CS_TEAM_SPECTATOR)
		return;

	int lag_comp = GetEntProp(client, Prop_Data, "m_bLagCompensation");
	if (lag_comp == 0)
	{
		if (g_cvWarnAX.BoolValue)
			PrintToChat(client, " \x09Warning! \x08You need to use \x09cl_lagcompensation 1\x08. We have forced it for you! ");
		ChangeClientTeam(client, CS_TEAM_SPECTATOR);

		char player_name[MAX_NAME_LENGTH];
		GetClientName(client, player_name, sizeof(player_name));
		PrintToChatAll(" \x09Warning! \x09%s \x08has been moved to spectators because they tried to use \x09anti-exploit", player_name);

		LogMessage("Client %s has been moved to spectators because they tried to use anti-exploit", player_name);
	}

	SetEntProp(client, Prop_Data, "m_bLagCompensation", 1);
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float velocity[3], float angles[3], int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2])
{
	if (!IsValidClient(client) || !IsPlayerAlive(client))
		return Plugin_Continue;

	char player_name[MAX_NAME_LENGTH];
	GetClientName(client, player_name, sizeof(player_name));

	Vec3 vec, vel;
	vec.From(angles);
	vel.From(velocity);

	bool modified = false;

	modified |= BlockAX(client);
	modified |= BlockFakeDuck(buttons);
	modified |= BlockUntrustedAngles(client, vec, angles);
	modified |= NormalizeAngles(vec, angles);
	modified |= BlockRollAngles(client, vec, angles);
	modified |= BlockLagPeek(client);
	modified |= BlockAirStuck(client, vel, buttons, tickcount);

	return modified ? Plugin_Changed : Plugin_Continue;
}

bool BlockAX(int client)
{
	if (g_cvBlockAX.BoolValue)
		CheckAX(client);
	return false;
}

bool BlockFakeDuck(int &buttons)
{
	if (g_cvBlockFakeDuck.BoolValue && buttons & IN_BULLRUSH)
	{
		buttons &= ~IN_BULLRUSH;
		return true;
	}
	return false;
}

bool BlockUntrustedAngles(int client, Vec3 vec, float angles[3])
{
	if (!g_cvBlockUntrustedAngles.BoolValue)
		return false;

	bool c1 = clamp(vec.x, -89.0, 89.0);
	bool c2 = clamp(vec.y, -180.0, 180.0);
	bool c3 = clamp(vec.z, -90.0, 90.0);

	if (c1 || c2 || c3)
	{
		float currentTime = GetGameTime();
		g_iAngleWarnings[client][WarningType_UNTRUSTED_ANGLES]++;
		if (currentTime - g_flLastAngleWarningTime[client][WarningType_UNTRUSTED_ANGLES] >= 5.0)
		{
			char player_name[MAX_NAME_LENGTH];
			GetClientName(client, player_name, sizeof(player_name));

			if (g_iAngleWarnings[client][WarningType_UNTRUSTED_ANGLES] > MAX_ANGLES_WARNING)
			{
				if (g_cvWarnUntrustedAngles.BoolValue)
					PrintToChat(client, " \x09Warning! \x08We have detected that you are using \x09untrusted angles\x08, please stop using them to avoid issues.",
								g_iAngleWarnings[client][WarningType_UNTRUSTED_ANGLES]);
				LogMessage("Client %s has been detected using untrusted angles", player_name,
						   g_iAngleWarnings[client][WarningType_UNTRUSTED_ANGLES]);
				g_iAngleWarnings[client][WarningType_UNTRUSTED_ANGLES] = 0;
			}
			g_flLastAngleWarningTime[client][WarningType_UNTRUSTED_ANGLES] = currentTime;
		}

		vec.To(angles);
		return true;
	}

	return false;
}

bool NormalizeAngles(Vec3 vec, float angles[3])
{
	if (!g_cvNormalizeAngles.BoolValue || (vec.y <= 180.0 && vec.y >= -180.0))
		return false;

	float r = vec.y / 360.0;
	int revs = RoundToFloor(FloatAbs(r));

	vec.y = (vec.y > 0.0) ? (vec.y - revs * 360.0) : (vec.y + revs * 360.0);
	vec.To(angles);

	return true;
}

bool BlockRollAngles(int client, Vec3 vec, float angles[3])
{
	if (!g_cvBlockRollAngles.BoolValue || vec.z == 0.0)
		return false;

	float bk = vec.z;
	vec.z = 0.0;
	vec.To(angles);

	float currentTime = GetGameTime();
	g_iAngleWarnings[client][WarningType_ROLL_ANGLES]++;
	if (currentTime - g_flLastAngleWarningTime[client][WarningType_ROLL_ANGLES] >= 5.0)
	{
		char player_name[MAX_NAME_LENGTH];
		GetClientName(client, player_name, sizeof(player_name));

		if (g_iAngleWarnings[client][WarningType_ROLL_ANGLES] > MAX_ANGLES_WARNING)
		{
			if (g_cvWarnRollAngles.BoolValue)
				PrintToChat(client, " \x09Warning! \x08We have detected that you are using \x09roll angles\x08, please stop using them. (\x09%i°\x08)",
							g_iAngleWarnings[client][WarningType_ROLL_ANGLES], RoundToNearest(bk));

			LogMessage("Client %s has been detected using roll angles (%i°)",
					   player_name, RoundToNearest(bk), g_iAngleWarnings[client][WarningType_ROLL_ANGLES]);
			g_iAngleWarnings[client][WarningType_ROLL_ANGLES] = 0;
		}
		g_flLastAngleWarningTime[client][WarningType_ROLL_ANGLES] = currentTime;
	}

	return true;
}

bool BlockLagPeek(int client)
{
	if (g_cvBlockLagPeek.BoolValue)
		RecordDataIntoTrack(client);

	return false;
}

bool BlockAirStuck(int client, Vec3 vel, int &buttons, int tickcount)
{
	if (!g_cvBlockAirStuck.BoolValue || !(tickcount == 0 && vel.x == 0.0 && vel.y == 0.0 && vel.z == 0.0 && !(buttons & IN_ATTACK)))
		return false;

	char player_name[MAX_NAME_LENGTH];
	GetClientName(client, player_name, sizeof(player_name));

	if (g_cvWarnAirStuck.BoolValue)
		PrintToChat(client, " \x09Warning! \x08We have detected that you are using \x09air stuck\x08, you have been \x09slayed\x08.");
	ForcePlayerSuicide(client);
	LogMessage("Client %s has been detected using air stuck", player_name);

	return true;
}

public Action PlayerSpawn(Event event, const char[] name, bool broadcast)
{
	int client = GetClientOfUserId(GetEventInt(event, "userid"));
	CheckAX(client);
	QueryClientConVar(client, "cl_lagcompensation", LagCompensation);

	return Plugin_Continue;
}

public void LagCompensation(QueryCookie cookie, int client, ConVarQueryResult result, const char[] cvarName, const char[] cvarValue, any value)
{
	if (GetClientTeam(client) == CS_TEAM_NONE)
		return;

	if (StringToInt(cvarValue) == 0)
	{
		PrintToChat(client, " \x09Warning! \x08You need to use \x09cl_lagcompensation 1");
		ChangeClientTeam(client, CS_TEAM_SPECTATOR);
	}
}

public Action JoinTeam(int client, const char[] command, int args)
{
	CheckAX(client);
	return Plugin_Continue;
}

public void OnClientConnected(int client)
{
	g_iLatencyWarnings[client] = 0;
	g_flLastLatencyWarningTime[client] = 0.0;
	g_flLastUntrustedAnglesWarningTime[client] = 0.0;
	g_iAngleWarnings[client][WarningType_UNTRUSTED_ANGLES] = 0;
	g_iAngleWarnings[client][WarningType_ROLL_ANGLES] = 0;
	g_flLastAngleWarningTime[client][WarningType_UNTRUSTED_ANGLES] = 0.0;
	g_flLastAngleWarningTime[client][WarningType_ROLL_ANGLES] = 0.0;
}

public void OnClientDisconnect(int client)
{
	g_iLatencyWarnings[client] = 0;
	g_flLastLatencyWarningTime[client] = 0.0;
	g_flLastUntrustedAnglesWarningTime[client] = 0.0;
	g_iAngleWarnings[client][WarningType_UNTRUSTED_ANGLES] = 0;
	g_iAngleWarnings[client][WarningType_ROLL_ANGLES] = 0;
	g_flLastAngleWarningTime[client][WarningType_UNTRUSTED_ANGLES] = 0.0;
	g_flLastAngleWarningTime[client][WarningType_ROLL_ANGLES] = 0.0;
}

float GetShotTime(int client)
{
	int weapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
	if (weapon != -1)
		return GetEntPropFloat(weapon, Prop_Send, "m_fLastShotTime");

	return 0.0;
}

bool IsValidClient(int client)
{
	return client > 0 && client <= MaxClients && IsClientConnected(client) && IsClientInGame(client);
}
