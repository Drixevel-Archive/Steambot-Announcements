 ////////////////////
//Includes & Pragmas
#include <sourcemod>
//#include <drixevel>	//Custom Include
#include <socket>
#include <colorvariables>

//Plugin Include
#include <steambot/Steambot-Announcements>

#pragma semicolon 1
#pragma newdecls required

////////////////////
//Defines
//Debug Define (Enable to generate logs to help fix plugin issues)
//#define DEBUG

//Plugin Defines
#define PLUGIN_NAME		"[Steambot] Announcements"
#define PLUGIN_VERSION "1.0.1"
#define SOCKET_STRING "%sSTEAMGROUP_POST_ANOUNCEMENT%i/%s/%s"

////////////////////
//Globals

//ConVars
Handle hConVars[7];
bool cv_bStatus;
char cv_sBotIP[256];
char cv_sBotPort[32];
char cv_sBotPassword[32];
int cv_iGroupID;
float cv_fReconnect;
float cv_fAntispam;

//Config Globals
Handle hAnnouncements_Name;
Handle hAnnouncements_Title;
Handle hAnnouncements_Body;

//Bot Globals
Handle hBotSocket;
bool bConnected;
Handle hReconnectTimer;
Handle hAntispamTimer;

////////////////////
//Plugin Info
public Plugin myinfo = 
{
	name = PLUGIN_NAME, 
	author = "Keith Warren (Shaders Allen) | Steambot by Arkarr", 
	description = "This is a module for the Steambot by Arkarr which allows admins and server operators to send announcements to their steamgroups.", 
	version = PLUGIN_VERSION, 
	url = "http://www.shadersallen.com/"
};

//Ask Plugin Load 2
public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	CreateNative("Steambot_Announce", Native_GenerateAnnouncement);
	
	RegPluginLibrary("Steambot-Announcements");
	return APLRes_Success;
}

////////////////////
//Plugin Info
public void OnPluginStart()
{
	LoadTranslations("announces.steambot.phrases.txt");
	CreateConVar("steambot_announcements_version", PLUGIN_VERSION, PLUGIN_NAME, FCVAR_REPLICATED | FCVAR_NOTIFY | FCVAR_SPONLY | FCVAR_DONTRECORD);
	hConVars[0] = CreateConVar("sm_steambot_announcements_status", "1", "Status of the plugin.\n(1 = on, 0 = off)", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	hConVars[1] = CreateConVar("sm_steambot_announcements_bot_ip", "", "IP address to connect to the bot.", FCVAR_NOTIFY);
	hConVars[2] = CreateConVar("sm_steambot_announcements_bot_port", "", "Port to connect to the bot.", FCVAR_NOTIFY);
	hConVars[3] = CreateConVar("sm_steambot_announcements_bot_password", "", "Password to connect to the bot.", FCVAR_NOTIFY);
	hConVars[4] = CreateConVar("sm_steambot_announcements_steamgroup_id", "", "The ID of the steamgroup to post announcements in.", FCVAR_NOTIFY);
	hConVars[5] = CreateConVar("sm_steambot_announcements_bot_reconnect", "10.0", "Time in seconds on bot disconnect to attempt a reconnect.", FCVAR_NOTIFY, true, 1.0);
	hConVars[6] = CreateConVar("sm_steambot_announcements_antispam", "120.0", "Time in seconds to delay announcements to the steamgroup.", FCVAR_NOTIFY, true, 1.0);
	
	RegAdminCmd("sm_announce", SendGroupAnnouncement, ADMFLAG_ROOT, "Post an announcement to the steamgroup.");
	RegAdminCmd("sm_ann", SendGroupAnnouncement, ADMFLAG_ROOT, "Post an announcement to the steamgroup.");
	RegAdminCmd("sm_event", SendGroupAnnouncement, ADMFLAG_ROOT, "Post an announcement to the steamgroup.");
	RegAdminCmd("sm_manualannounce", ManualGroupAnnouncement, ADMFLAG_ROOT, "Post a manual announcement to the steamgroup.");
	RegAdminCmd("sm_manannounce", ManualGroupAnnouncement, ADMFLAG_ROOT, "Post a manual announcement to the steamgroup.");
	RegAdminCmd("sm_manann", ManualGroupAnnouncement, ADMFLAG_ROOT, "Post a manual announcement to the steamgroup.");
	RegAdminCmd("sm_reloadannouncements", ReloadAnnouncementsConfig, ADMFLAG_ROOT, "Reloads the announcements configurations data.");
	RegAdminCmd("sm_reloadannounce", ReloadAnnouncementsConfig, ADMFLAG_ROOT, "Reloads the announcements configurations data.");
	RegAdminCmd("sm_relann", ReloadAnnouncementsConfig, ADMFLAG_ROOT, "Reloads the announcements configurations data.");
	
	hAnnouncements_Name = CreateArray(ByteCountToCells(256));
	hAnnouncements_Title = CreateArray(ByteCountToCells(256));
	hAnnouncements_Body = CreateArray(ByteCountToCells(256));
	
	AutoExecConfig();
}

////////////////////
//On Configs Executed
public void OnConfigsExecuted()
{
	cv_bStatus = GetConVarBool(hConVars[0]);
	GetConVarString(hConVars[1], cv_sBotIP, sizeof(cv_sBotIP));
	GetConVarString(hConVars[2], cv_sBotPort, sizeof(cv_sBotPort));
	GetConVarString(hConVars[3], cv_sBotPassword, sizeof(cv_sBotPassword));
	cv_iGroupID = GetConVarInt(hConVars[4]);
	cv_fReconnect = GetConVarFloat(hConVars[5]);
	cv_fAntispam = GetConVarFloat(hConVars[6]);
	
	if (cv_bStatus)
	{
		LoadAnnouncementsConfig();
		AttemptBotConnection();
	}
}

public Action SendGroupAnnouncement(int client, int args)
{
	if (!cv_bStatus)
	{
		return Plugin_Handled;
	}
	
	if (!bConnected)
	{
		CReplyToCommand(client, "%t", "error connecting public message");
		return Plugin_Handled;
	}
	
	if (hAntispamTimer != null)
	{
		CReplyToCommand(client, "%t", "antispam warning");
		return Plugin_Handled;
	}
	
	Handle hMenu = CreateMenu(MenuHandle_AnnouncementsMenu);
	SetMenuTitle(hMenu, "%t", "pick an announcement menu title");
	
	for (int i = 0; i < GetArraySize(hAnnouncements_Name); i++)
	{
		char sName[256];
		if (GetArrayString(hAnnouncements_Name, i, sName, sizeof(sName)))
		{
			char sID[32];
			IntToString(i, sID, sizeof(sID));
			AddMenuItem(hMenu, sID, sName);
		}
	}
	
	DisplayMenu(hMenu, client, MENU_TIME_FOREVER);
	return Plugin_Handled;
}

public int MenuHandle_AnnouncementsMenu(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			if (!bConnected)
			{
				CReplyToCommand(param1, "%t", "error connecting public message");
				return;
			}
			
			if (hAntispamTimer != null)
			{
				CReplyToCommand(param1, "%t", "antispam warning");
				return;
			}
			
			char sID[32]; char sName[256];
			GetMenuItem(menu, param2, sID, sizeof(sID), _, sName, sizeof(sName));
			int iID = StringToInt(sID);
			
			char sTitle[256];
			GetArrayString(hAnnouncements_Title, iID, sTitle, sizeof(sTitle));
			
			char sBody[256];
			GetArrayString(hAnnouncements_Body, iID, sBody, sizeof(sBody));
			
			GenerateGroupAnnouncement(param1, sTitle, sBody);
			CPrintToChat(param1, "%t", "config announcement successfully sent", sName);
		}
		case MenuAction_Cancel:CloseHandle(menu);
	}
}

public Action ManualGroupAnnouncement(int client, int args)
{
	if (!cv_bStatus)
	{
		return Plugin_Handled;
	}
	
	if (args < 2)
	{
		char sCommand[64];
		GetCmdArg(0, sCommand, sizeof(sCommand));
		
		CReplyToCommand(client, "%t", "manual command usage", sCommand);
		return Plugin_Handled;
	}
	
	if (!bConnected)
	{
		CReplyToCommand(client, "%t", "error connecting public message");
		return Plugin_Handled;
	}
	
	if (hAntispamTimer != null)
	{
		CReplyToCommand(client, "%t", "antispam warning");
		return Plugin_Handled;
	}
	
	char sTitle[256];
	GetCmdArg(1, sTitle, sizeof(sTitle));
	
	char sBody[256];
	GetCmdArg(2, sBody, sizeof(sBody));
	
	GenerateGroupAnnouncement(client, sTitle, sBody);
	CReplyToCommand(client, "%t", "manual announcement sent successfully", sTitle, sBody);
	
	return Plugin_Handled;
}

public Action ReloadAnnouncementsConfig(int client, int args)
{
	if (!cv_bStatus)
	{
		return Plugin_Handled;
	}
	
	LoadAnnouncementsConfig();
	CReplyToCommand(client, "%t", "announcements config reloaded");
	return Plugin_Handled;
}

void LoadAnnouncementsConfig()
{
	Handle hKV = CreateKeyValues("steambot_announcements");
	
	char sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, sizeof(sPath), "configs/steambot.announcements.cfg");
	
	if (!FileToKeyValues(hKV, sPath))
	{
		CloseHandle(hKV);
		LogError("%t", "error finding configuration file");
		return;
	}
	
	if (!KvGotoFirstSubKey(hKV))
	{
		CloseHandle(hKV);
		LogError("%t", "error parsing empty configuration file");
		return;
	}
	
	ClearArray(hAnnouncements_Name);
	ClearArray(hAnnouncements_Title);
	ClearArray(hAnnouncements_Body);
	
	int i = 0;
	do {
		i++;
		char sName[256];
		KvGetSectionName(hKV, sName, sizeof(sName));
		
		char sTitle[256];
		KvGetString(hKV, "title", sTitle, sizeof(sTitle));
		
		char sBody[256];
		KvGetString(hKV, "body", sBody, sizeof(sBody));
		
		if (strlen(sName) < 1 || strlen(sTitle) < 1 || strlen(sBody) < 1)
		{
			LogError("%t", "error parsing item in configuration file", i);
			continue;
		}
		
		PushArrayString(hAnnouncements_Name, sName);
		PushArrayString(hAnnouncements_Title, sTitle);
		PushArrayString(hAnnouncements_Body, sBody);
		
	} while (KvGotoNextKey(hKV));
	
	CloseHandle(hKV);
	LogMessage("%t", "successfully parsed configuration file", GetArraySize(hAnnouncements_Name));
}

bool GenerateGroupAnnouncement(int client, const char[] sTitle, const char[] sBody)
{
	if (!bConnected)
	{
		CReplyToCommand(client, "%t", "error connecting public message");
		return false;
	}
	
	if (hAntispamTimer != null)
	{
		CReplyToCommand(client, "%t", "antispam warning");
		return false;
	}
	
	char sBuffer[1024];
	Format(sBuffer, sizeof(sBuffer), SOCKET_STRING, cv_sBotPassword, cv_iGroupID, sTitle, sBody);
	SocketSend(hBotSocket, sBuffer, sizeof(sBuffer));
	
	if (cv_fAntispam > 0.0)
	{
		hAntispamTimer = CreateTimer(cv_fAntispam, Timer_Antispam);
	}
	
	return true;
}

public Action Timer_Antispam(Handle timer)
{
	hAntispamTimer = null;
}

void AttemptBotConnection()
{
	if (strlen(cv_sBotIP) < 1 || strlen(cv_sBotPort) < 1)
	{
		SetFailState("Error creating bot connection, your IP and/or port ConVars are empty.");
		return;
	}
	
	bConnected = false;
	hBotSocket = SocketCreate(SOCKET_TCP, OnClientSocketError);
	SocketConnect(hBotSocket, OnClientSocketConnected, OnChildSocketReceive, OnChildSocketDisconnected, cv_sBotIP, StringToInt(cv_sBotPort));
}

public int OnClientSocketConnected(Handle socket, any arg)
{
	bConnected = true;
	
	if (hReconnectTimer != null)
	{
		KillTimer(hReconnectTimer);
		hReconnectTimer = null;
	}
	
	LogMessage("%t", "bot connected successfully");
}

public int OnClientSocketError(Handle socket, const int errorType, const int errorNum, any ary)
{
	bConnected = false;
	CloseHandle(socket);
	
	LogError("%t", "bot connected failure");
}

public int OnChildSocketReceive(Handle socket, char[] receiveData, const int dataSize, any hFile)
{
	//Nothing to do.
}

public int OnChildSocketDisconnected(Handle socket, any hFile)
{
	bConnected = false;
	CloseHandle(socket);
	
	hReconnectTimer = CreateTimer(cv_fReconnect, Timer_Reconnect, _, TIMER_REPEAT);
	LogError("%t", "bot disconnected", RoundFloat(cv_fReconnect));
}

public Action Timer_Reconnect(Handle timer, any data)
{
	AttemptBotConnection();
}

//Natives
public int Native_GenerateAnnouncement(Handle plugin, int numParams)
{
	int size;
	
	GetNativeStringLength(2, size);
	
	char[] sTitle = new char[size];
	GetNativeString(2, sTitle, size);
	
	GetNativeStringLength(3, size);
	
	char[] sBody = new char[size];
	GetNativeString(3, sBody, size);
	
	return GenerateGroupAnnouncement(GetNativeCell(1), sTitle, sBody);
} 