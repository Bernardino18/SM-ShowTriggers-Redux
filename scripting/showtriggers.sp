#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdkhooks>
#include <sdktools>

#define PLUGIN_NAME "Show Triggers (Brushes) Redux"
#define PLUGIN_AUTHOR "JoinedSenses"
#define PLUGIN_DESCRIPTION "Toggle brush visibility"
#define PLUGIN_VERSION "0.2.1"
#define PLUGIN_URL "http://github.com/JoinedSenses"

#define EF_NODRAW 32

public Plugin myinfo = {
	name = PLUGIN_NAME,
	author = PLUGIN_AUTHOR,
	description = PLUGIN_DESCRIPTION,
	version = PLUGIN_VERSION,
	url = PLUGIN_URL
}

#define ENABLE_ALL -2
#define DISABLE_ALL -1

enum {
	Func_Brush,
	Func_NoBuild,
	Func_NoGrenades,
	Func_Regenerate,
	Trigger_Apply_Impulse,
	Trigger_Capture_Area,
	Trigger_Catapult,
	Trigger_Gravity,
	Trigger_Hurt,
	Trigger_Impact,
	Trigger_Multiple,
	Trigger_Push,
	Trigger_Teleport,
	Trigger_Teleport_Relative,

	MAX_TYPES
};

static const char g_NAMES[][] = {
	"func_brush",
	"func_nobuild",
	"func_nogrenades",
	"func_regenerate",
	"trigger_apply_impulse",
	"trigger_capture_area",
	"trigger_catapult",
	"trigger_gravity",
	"trigger_hurt",
	"trigger_impact",
	"trigger_multiple",
	"trigger_push",
	"trigger_teleport",
	"trigger_teleport_relative"
};


// Which brush types does the player have enabled?
bool g_bTypeEnabled[MAXPLAYERS+1][MAX_TYPES];
// Offset for brush effects
int g_iOffsetMFEffects = -1;

// Main menu
Menu g_Menu;

public void OnPluginStart() {
	g_iOffsetMFEffects = FindSendPropInfo("CBaseEntity", "m_fEffects");
	if (g_iOffsetMFEffects == -1) {
		SetFailState("[Show Triggers] Could not find CBaseEntity:m_fEffects");
	}

	CreateConVar(
		"sm_showtriggers_version",
		PLUGIN_VERSION,
		PLUGIN_DESCRIPTION,
		FCVAR_SPONLY|FCVAR_NOTIFY|FCVAR_DONTRECORD
	).SetString(PLUGIN_VERSION);

	RegConsoleCmd("sm_showtriggers", cmdShowTriggers, "Toggles brush visibility");

	Menu menu = new Menu(menuHandler_Main, MenuAction_DrawItem|MenuAction_DisplayItem);
	menu.SetTitle("Toggle Visibility");
	menu.AddItem("-2", "Enable All");
	menu.AddItem("-1", "Disable All");
	for (int i = 0; i < MAX_TYPES; ++i) {
		menu.AddItem(IntToStringEx(i), g_NAMES[i]);
	}
	g_Menu = menu;
}

// Display trigger menu
public Action cmdShowTriggers(int client, int args) {
	if (client) {
		g_Menu.Display(client, MENU_TIME_FOREVER);
	}

	return Plugin_Handled;
}

public int menuHandler_Main(Menu menu, MenuAction action, int param1, int param2) {
	switch (action) {
		case MenuAction_Select: {
			char info[8];
			menu.GetItem(param2, info, sizeof info);

			int type = StringToInt(info);
			switch (type) {
				case ENABLE_ALL: {
					// Loop through all types and enable
					for (int i = 0; i < MAX_TYPES; ++i) {
						g_bTypeEnabled[param1][i] = true;
					}
				}
				case DISABLE_ALL: {
					// Loop through all types and disable
					for (int i = 0; i < MAX_TYPES; ++i) {
						g_bTypeEnabled[param1][i] = false;
					}
				}
				default: {
					// Toggle selected type
					g_bTypeEnabled[param1][type] = !g_bTypeEnabled[param1][type];
				}
			}

			CheckBrushes(ShouldRender());

			menu.DisplayAt(param1, menu.Selection, MENU_TIME_FOREVER);
		}
		// Check *_ALL items to see if they should be disabled
		case MenuAction_DrawItem: {
			char info[8];
			menu.GetItem(param2, info, sizeof info);
			switch (StringToInt(info)) {
				case ENABLE_ALL: {
					for (int i = 0; i < MAX_TYPES; ++i) {
						if (!g_bTypeEnabled[param1][i]) {
							return ITEMDRAW_DEFAULT;
						}
					}

					return ITEMDRAW_DISABLED;
				}
				case DISABLE_ALL: {
					for (int i = 0; i < MAX_TYPES; ++i) {
						if (g_bTypeEnabled[param1][i]) {
							return ITEMDRAW_DEFAULT;
						}
					}

					return ITEMDRAW_DISABLED;
				}
			}

			return ITEMDRAW_DEFAULT;
		}
		// Check which items are enabled.
		case MenuAction_DisplayItem: {
			char info[8];
			char text[64];
			menu.GetItem(param2, info, sizeof info, _, text, sizeof text);

			int type = StringToInt(info);
			if (type >= 0) {
				if (g_bTypeEnabled[param1][type]) {
					StrCat(text, sizeof text, " (Enabled)");
					return RedrawMenuItem(text);
				}
			}
		}
	}

	return 0;
}

public void OnClientDisconnect(int client) {
	for (int i = 0; i < MAX_TYPES; ++i) {
		g_bTypeEnabled[client][i] = false;
	}

	CheckBrushes(ShouldRender());
}

public void OnPluginEnd() {
	CheckBrushes(false);
}


// ======================== Normal Functions ========================


/**
 * If transmit state has changed, iterates through each brush type
 * to modify entity flags and to (un)hook as needed.
 *
 * @param transmit    Should we attempt to transmit these brushes?
 */
void CheckBrushes(bool transmit) {
	static bool hooked = false;

	// If transmit state has not changed, do nothing
	if (hooked == transmit) {
		return;
	}

	hooked = !hooked;

	char className[32];
	for (int ent = MaxClients + 1; ent <= 2048; ++ent) {
		if (!IsValidEntity(ent)) {
			continue;
		}

		GetEntityClassname(ent, className, sizeof className);
		if (StrContains(className, "func_") != 0 && StrContains(className, "trigger_") != 0) {
			continue;
		}

		for (int i = 0; i < MAX_TYPES; ++i) {
			if (!StrEqual(className, g_NAMES[i])) {
				continue;
			}

			SDKHookCB f = INVALID_FUNCTION;
			switch (i) {
				case Func_Brush:				f = hookST_funcBrush;
				case Func_NoBuild:              f = hookST_funcNobuild;
				case Func_NoGrenades:           f = hookST_funcNogrenades;
				case Func_Regenerate:           f = hookST_funcRegenerate;
				case Trigger_Apply_Impulse:     f = hookST_triggerApplyImpulse;
				case Trigger_Capture_Area:      f = hookST_triggerCaptureArea;
				case Trigger_Catapult:          f = hookST_triggerCatapult;
				case Trigger_Gravity:           f = hookST_triggerGravity;
				case Trigger_Hurt:              f = hookST_triggerHurt;
				case Trigger_Impact:            f = hookST_triggerImpact;
				case Trigger_Multiple:          f = hookST_triggerMultiple;
				case Trigger_Push:              f = hookST_triggerPush;
				case Trigger_Teleport:          f = hookST_triggerTeleport;
				case Trigger_Teleport_Relative: f = hookST_triggerTeleportRelative;
				// somehow got an invalid index. this shouldnt happen unless someone modifies this plugin and fucks up.
				default: break;
			}

			if (hooked) {
				SetEntData(ent, g_iOffsetMFEffects, GetEntData(ent, g_iOffsetMFEffects) & ~EF_NODRAW);
				ChangeEdictState(ent, g_iOffsetMFEffects);
				SetEdictFlags(ent, GetEdictFlags(ent) & ~FL_EDICT_DONTSEND);
				SDKHook(ent, SDKHook_SetTransmit, f);
			}
			else {
				SetEntData(ent, g_iOffsetMFEffects, GetEntData(ent, g_iOffsetMFEffects) | EF_NODRAW);
				ChangeEdictState(ent, g_iOffsetMFEffects);
				SetEdictFlags(ent, GetEdictFlags(ent) | FL_EDICT_DONTSEND);
				SDKUnhook(ent, SDKHook_SetTransmit, f);
			}

			break;
		}
	}
}

/**
 * Function to return the int value as a string directly.
 *
 * @param value    The integer value to convert to string
 * @return         String value of passed integer
 */
char[] IntToStringEx(int value) {
	char result[11];
	IntToString(value, result, sizeof result);
	return result;
}

/**
 * Function to check if we should be attempting to render any of the brush types.
 * Meant to be passed to CheckTriggers() and used for optimizing SetTransmit hooking.
 *
 * @return        True if any client has any brush types enabled, else false
 */
bool ShouldRender() {
	for (int client = 1; client <= MaxClients; ++client) {
		if (IsClientInGame(client)) {
			for (int i = 0; i < MAX_TYPES; ++i) {
				if (g_bTypeEnabled[client][i]) {
					return true;
				}
			}
		}
	}

	return false;
}

// ======================== SetTransmit Hooks ========================


public Action hookST_funcNogrenades(int entity, int client) {
	if (g_bTypeEnabled[client][Func_NoGrenades]) {
		return Plugin_Continue;
	}
	return Plugin_Handled;
}

public Action hookST_funcRegenerate(int entity, int client) {
	if (g_bTypeEnabled[client][Func_Regenerate]) {
		return Plugin_Continue;
	}
	return Plugin_Handled;
}


public Action hookST_funcBrush(int entity, int client) {
	if (g_bTypeEnabled[client][Func_Brush]) {
		return Plugin_Continue;
	}
	return Plugin_Handled;
}

public Action hookST_funcNobuild(int entity, int client) {
	if (g_bTypeEnabled[client][Func_NoBuild]) {
		return Plugin_Continue;
	}
	return Plugin_Handled;
}

public Action hookST_triggerApplyImpulse(int entity, int client) {
	if (g_bTypeEnabled[client][Trigger_Apply_Impulse]) {
		return Plugin_Continue;
	}
	return Plugin_Handled;
}

public Action hookST_triggerCaptureArea(int entity, int client) {
	if (g_bTypeEnabled[client][Trigger_Capture_Area]) {
		return Plugin_Continue;
	}
	return Plugin_Handled;
}

public Action hookST_triggerCatapult(int entity, int client) {
	if (g_bTypeEnabled[client][Trigger_Catapult]) {
		return Plugin_Continue;
	}
	return Plugin_Handled;
}

public Action hookST_triggerGravity(int entity, int client) {
	if (g_bTypeEnabled[client][Trigger_Gravity]) {
		return Plugin_Continue;
	}
	return Plugin_Handled;
}

public Action hookST_triggerHurt(int entity, int client) {
	if (g_bTypeEnabled[client][Trigger_Hurt]) {
		return Plugin_Continue;
	}
	return Plugin_Handled;
}

public Action hookST_triggerImpact(int entity, int client) {
	if (g_bTypeEnabled[client][Trigger_Impact]) {
		return Plugin_Continue;
	}
	return Plugin_Handled;
}

public Action hookST_triggerMultiple(int entity, int client) {
	if (g_bTypeEnabled[client][Trigger_Multiple]) {
		return Plugin_Continue;
	}
	return Plugin_Handled;
}

public Action hookST_triggerPush(int entity, int client) {
	if (g_bTypeEnabled[client][Trigger_Push]) {
		return Plugin_Continue;
	}
	return Plugin_Handled;
}

public Action hookST_triggerTeleport(int entity, int client) {
	if (g_bTypeEnabled[client][Trigger_Teleport]) {
		return Plugin_Continue;
	}
	return Plugin_Handled;
}

public Action hookST_triggerTeleportRelative(int entity, int client) {
	if (g_bTypeEnabled[client][Trigger_Teleport_Relative]) {
		return Plugin_Continue;
	}
	return Plugin_Handled;
}
