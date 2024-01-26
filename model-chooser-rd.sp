// =========================================================== //

#include <adt_trie>
#include <clientprefs>
#include <cstrike>
#include <regex>
#include <sdktools>
#include <sourcemod>

// ====================== DEFINITIONS ======================== //

#define MAX_MODELS  128
#define CONFIG_FILE "cfg/sourcemod/modelchooser-rd.cfg"

#define DEFAULT_MODEL_T  "models/player/tm_leet_varianta.mdl"
#define DEFAULT_ARM_T    "models/weapons/t_arms_leet.mdl"
#define DEFAULT_MODEL_CT "models/player/ctm_idf.mdl"
#define DEFAULT_ARM_CT   "models/weapons/ct_arms_fbi.mdl"

// ====================== FORMATTING ========================= //

#pragma newdecls required

// ====================== VARIABLES ========================== //

enum PMData
{
	PMData_Name = 0,
	PMData_Model,
	PMData_Arms,
	PMData_Count
};

StringMap g_IndicesMap;
char      g_SectionList[16][64];

int  gI_ModelCount         = 0;
bool gB_AllModelsPrecached = false;

Cookie gH_Cookie;
int    gI_SelectedSection[MAXPLAYERS + 1] = { -1, ... };
int    gI_SelectedModel[MAXPLAYERS + 1]   = { -1, ... };
char   gSZ_ModelData[MAX_MODELS][PMData_Count][PLATFORM_MAX_PATH];

// ====================== PLUGIN INFO ======================== //
public Plugin myinfo =
{
	name        = "ModelChooser",
	author      = "GameChaos, Sikari",
	description = "ModelChooser with clientprefs support",
	version     = "4.1k",
	url         = "https://github.com/zer0k-z/player-model-changer"
};

// ======================= MAIN CODE ========================= //
public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	RegConsoleCmd("sm_pm", Command_Models);
	RegConsoleCmd("sm_playermodel", Command_Models);
	RegConsoleCmd("sm_skin", Command_Models);
	RegConsoleCmd("sm_skins", Command_Models);
}

public void OnPluginStart()
{
	HookEvent("player_team", Event_OnPlayerTeam);
	HookEvent("player_spawn", Event_OnPlayerSpawn);
	HookEvent("player_death", Event_OnPlayerDeath);
	gH_Cookie    = new Cookie("ModelChooser-cookie", "ModelChooser cookie", CookieAccess_Private);
	g_IndicesMap = new StringMap();
}

public void OnMapStart()
{
	gB_AllModelsPrecached          = false;
	// set default
	gSZ_ModelData[0][PMData_Name]  = "DEFAULT";
	gSZ_ModelData[0][PMData_Model] = DEFAULT_MODEL_CT;
	gSZ_ModelData[0][PMData_Arms]  = DEFAULT_ARM_CT;
	// load custom models
	LoadModelsFromFile();
}

public void OnClientConnected(int client)
{
	gI_SelectedModel[client] = 0;
}

public void OnClientCookiesCached(int client)
{
	char buffer[3];
	gH_Cookie.Get(client, buffer, sizeof(buffer));
	gI_SelectedModel[client] = StringToInt(buffer);
	if (IsClientInGame(client) && IsPlayerAlive(client))
	{
		ChangeModel(client, gI_SelectedModel[client]);
	}
}

public void Event_OnPlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	ChangeModel(client, gI_SelectedModel[client]);
}

public void Event_OnPlayerTeam(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	ChangeModel(client, gI_SelectedModel[client]);
}

public void Event_OnPlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	ChangeModel(client, gI_SelectedModel[client]);
}

public Action Command_Models(int client, int args)
{
	ShowCategoriesMenu(client);
	return Plugin_Handled;
}

void LoadModelsFromFile()
{
	if (!FileExists(CONFIG_FILE))
	{
		SetFailState("%s does not exist!", CONFIG_FILE);
	}

	KeyValues config = new KeyValues("ModelChooser");
	config.ImportFromFile(CONFIG_FILE);

	if (config == null)
	{
		SetFailState("Failed reading %s as KeyValues, make sure it is in KeyValues format!", CONFIG_FILE);
	}

	gI_ModelCount = 1;

	BrowseSections(config);

	delete config;
	gB_AllModelsPrecached = true;
}

void BrowseSections(KeyValues config)
{
	int sectionIndex = 0;
	config.GotoFirstSubKey();
	do {
		config.GetSectionName(g_SectionList[sectionIndex], sizeof(g_SectionList[]));
		BrowseModels(config, g_SectionList[sectionIndex]);

		sectionIndex++;

		config.GoBack();
	}
	while (config.GotoNextKey());
}

void BrowseModels(KeyValues config, char[] sectionName)
{
	// PrintToServer("browse models in %s", sectionName);
	// index of modelIndicesInSection
	int index                   = 0;
	int[] modelIndicesInSection = new int[32];
	while (config.GotoFirstSubKey() || config.GotoNextKey())
	{
		modelIndicesInSection[index] = gI_ModelCount;
		config.GetSectionName(gSZ_ModelData[gI_ModelCount][PMData_Name], sizeof(gSZ_ModelData[][]));
		config.GetString("model", gSZ_ModelData[gI_ModelCount][PMData_Model], sizeof(gSZ_ModelData[][]));
		config.GetString("arms", gSZ_ModelData[gI_ModelCount][PMData_Arms], sizeof(gSZ_ModelData[][]));

		bool modelSet = (!StrEqual(gSZ_ModelData[gI_ModelCount][PMData_Model], ""));
		bool armsSet  = (!StrEqual(gSZ_ModelData[gI_ModelCount][PMData_Arms], ""));

		if (modelSet)
		{
			PrecacheModelEx(gSZ_ModelData[gI_ModelCount][PMData_Model]);
			AddFileToDownloadsTable(gSZ_ModelData[gI_ModelCount][PMData_Model]);
		}

		if (armsSet)
		{
			PrecacheModelEx(gSZ_ModelData[gI_ModelCount][PMData_Arms]);
			AddFileToDownloadsTable(gSZ_ModelData[gI_ModelCount][PMData_Arms]);
		}
		index++;
		gI_ModelCount++;
	}

	// (section name, its model indices)
	g_IndicesMap.SetArray(sectionName, modelIndicesInSection, 32);
}

void ChangeModel(int client, int modelIndex)
{
	if (!gB_AllModelsPrecached)
	{
		return;
	}

	if (modelIndex < 0)
	{
		return;
	}

	if (gI_SelectedModel[client] >= 0)
	{
		DataPack dp = new DataPack();
		dp.WriteCell(client);
		dp.WriteCell(modelIndex);
		CreateTimer(0.2, Timer_SetModel, dp);
	}
}

public Action Timer_SetModel(Handle timer, DataPack dp)
{
	dp.Reset();
	int client = dp.ReadCell();
	if (!IsClientInGame(client) || !IsPlayerAlive(client))
	{
		delete dp;
		return;
	}
	int modelIndex = dp.ReadCell();
	SetEntityModel(client, gSZ_ModelData[modelIndex][PMData_Model]);
	SetEntPropString(client, Prop_Send, "m_szArmsModel", gSZ_ModelData[modelIndex][PMData_Arms]);
	delete dp;
}

void ShowCategoriesMenu(int client)
{
	Menu menu = new Menu(MenuCategories, MENU_ACTIONS_ALL);
	menu.SetTitle("Model Categories");
	menu.AddItem("default", "Default");
	for (int i = 0; i < 16; i++)
	{
		if (StrEqual(g_SectionList[i], ""))
		{
			continue;
		}
		else
		{
			char index[12];
			IntToString(i, index, sizeof(index));
			menu.AddItem(index, g_SectionList[i]);
		}
	}
	menu.ExitButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuCategories(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			char info[12];
			menu.GetItem(param2, info, sizeof(info));
			if (StrEqual(info, "default"))
			{
				gI_SelectedModel[param1] = 0;
				ChangeModel(param1, 0);
				if (AreClientCookiesCached(param1))
				{
					gH_Cookie.Set(param1, "0");
				}
			}
			else {
				int sectionIndex           = StringToInt(info);
				gI_SelectedSection[param1] = sectionIndex;
				ShowModelsMenu(param1, 0, sectionIndex);
			}
		}
		case MenuAction_End:
		{
			delete menu;
		}
	}
}

void ShowModelsMenu(int client, int atItem = 0, int sectionIndex)
{
	Menu menu = new Menu(MenuModels, MENU_ACTIONS_ALL);
	menu.SetTitle("Select Models");
	int modelIndices[32];
	g_IndicesMap.GetArray(g_SectionList[sectionIndex], modelIndices, sizeof(modelIndices));
	for (int i = 0; i < 32; i++)
	{
		if (modelIndices[i] == 0)
		{
			continue;
		}
		else
		{
			int  modelIndex = modelIndices[i];
			char mdlIndex[12];
			IntToString(modelIndex, mdlIndex, sizeof(mdlIndex));
			menu.AddItem(mdlIndex, gSZ_ModelData[modelIndex][PMData_Name]);
		}
	}

	menu.ExitButton = true;
	menu.DisplayAt(client, atItem, MENU_TIME_FOREVER);
}

public int MenuModels(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			if (action == MenuAction_Select)
			{
				char info[12];
				menu.GetItem(param2, info, sizeof(info));
				int modelSelection       = StringToInt(info);
				gI_SelectedModel[param1] = modelSelection;
				ChangeModel(param1, modelSelection);
				if (AreClientCookiesCached(param1))
				{
					char buffer[3];
					IntToString(modelSelection, buffer, sizeof(buffer));
					gH_Cookie.Set(param1, buffer);
				}
				ShowModelsMenu(param1, (param2 / menu.Pagination * menu.Pagination), gI_SelectedSection[param1]);
			}
		}
		case MenuAction_Cancel:
		{
			ShowCategoriesMenu(param1);
		}
		case MenuAction_End:
		{
			delete menu;
		}
	}
}

stock void PrecacheModelEx(char[] modelPath)
{
	if (!IsModelPrecached(modelPath))
	{
		PrecacheModel(modelPath, true);
	}
}

stock bool IsValidClient(int client)
{
	return (client >= 1 && client <= MaxClients && IsValidEntity(client) && IsClientConnected(client) && IsClientInGame(client));
}