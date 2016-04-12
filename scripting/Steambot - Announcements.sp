////////////////////
//Includes & Pragmas
#include <sourcemod>
//#include <drixevel>	//Custom Include
#include <socket>
#include <colorvariables>

#pragma semicolon 1
#pragma newdecls required

////////////////////
//Defines
//Debug Define (Enable to generate logs to help fix plugin issues)
//#define DEBUG

//Plugin Defines
#define PLUGIN_NAME		"[Steambot] Announcements"
#define PLUGIN_VERSION "1.0.0"
#define SOCKET_STRING "%sSTEAMGROUP_POST_ANOUNCEMENT%i/%s/%s"

////////////////////
//Globals

//ConVars
Handle hConVars[6];
bool cv_bStatus;
char cv_sBotIP[256];
char cv_sBotPort[32];
char cv_sBotPassword[32];
int cv_iGroupID;
float cv_fReconnect;

//Config Globals
Handle hAnnouncements_Name;
Handle hAnnouncements_Title;
Handle hAnnouncements_Body;

//Bot Globals
Handle hBotSocket;
bool bConnected;
Handle hReconnectTimer;

////////////////////
//Plugin Info
public Plugin myinfo = 
{
	name = PLUGIN_NAME,
	author = "Keith Warren (Drixevel) | Steambot by Arkarr",
	description = "",
	version = PLUGIN_VERSION,
	url = "http://www.drixevel.com/"
};

////////////////////
//Plugin Info
public void OnPluginStart()
{
	LoadTranslations("announces.steambot.phrases.txt");
	hConVars[0] = CreateConVar("sm_steambot_announcements_status", "1", "Status of the plugin.\n(1 = on, 0 = off)", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	hConVars[1] = CreateConVar("sm_steambot_announcements_bot_ip", "", "IP address to connect to the bot.", FCVAR_NOTIFY);
	hConVars[2] = CreateConVar("sm_steambot_announcements_bot_port", "", "Port to connect to the bot.", FCVAR_NOTIFY);
	hConVars[3] = CreateConVar("sm_steambot_announcements_bot_password", "", "Password to connect to the bot.", FCVAR_NOTIFY);
	hConVars[4] = CreateConVar("sm_steambot_announcements_steamgroup_id", "", "The ID of the steamgroup to post announcements in.", FCVAR_NOTIFY);
	hConVars[5] = CreateConVar("sm_steambot_announcements_bot_reconnect", "10.0", "Time in seconds on bot disconnect to attempt a reconnect.", FCVAR_NOTIFY, true, 1.0);
	
	RegAdminCmd("sm_announce", SendGroupAnnouncement, ADMFLAG_ROOT, "Post an announcement to the steamgroup.");
	RegAdminCmd("sm_manualannounce", ManualGroupAnnouncement, ADMFLAG_ROOT, "Post a manual announcement to the steamgroup.");
	RegAdminCmd("sm_reloadannouncements", ReloadAnnouncementsConfig, ADMFLAG_ROOT, "Reloads the announcements configurations data.");
	
	hAnnouncements_Name = CreateArray(ByteCountToCells(256));
	hAnnouncements_Title = CreateArray(ByteCountToCells(256));
	hAnnouncements_Body = CreateArray(ByteCountToCells(256));
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
			
			char sID[32]; char sName[256];
			GetMenuItem(menu, param2, sID, sizeof(sID), _, sName, sizeof(sName));
			int iID = StringToInt(sID);
			
			char sTitle[256];
			GetArrayString(hAnnouncements_Title, iID, sTitle, sizeof(sTitle));
			
			char sBody[256];
			GetArrayString(hAnnouncements_Body, iID, sBody, sizeof(sBody));
			
			GenerateGroupAnnouncement(sTitle, sBody);
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
	
	char sTitle[256];
	GetCmdArg(1, sTitle, sizeof(sTitle));
	
	char sBody[256];
	GetCmdArg(2, sBody, sizeof(sBody));
	
	GenerateGroupAnnouncement(sTitle, sBody);
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

bool GenerateGroupAnnouncement(const char[] sTitle, const char[] sBody)
{
	char sBuffer[1024];
	Format(sBuffer, sizeof(sBuffer), SOCKET_STRING, cv_sBotPassword, cv_iGroupID, sTitle, sBody);
	SocketSend(hBotSocket, sBuffer, sizeof(sBuffer));
}

void AttemptBotConnection()
{
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