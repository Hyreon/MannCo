#pragma semicolon 1 // Force strict semicolon mode.
// ====[ INCLUDES ]====================================================
#include <sourcemod>
#define REQUIRE_EXTENSIONS
#include <tf2items>
#include <tf2attributes>

// ====[ CONSTANTS ]===================================================
#define PLUGIN_NAME "[TF2Items] Mann Co. Manager"
#define PLUGIN_AUTHOR "Damizean & Asherkin (& Hyreon!)"
#define PLUGIN_VERSION "1.0"
#define PLUGIN_CONTACT "Hyreon#9109"

#define ARRAY_SIZE 2
#define ARRAY_ITEM 0
#define ARRAY_FLAGS 1

#define FLT_MAX 999999999999.9
#define FLT_MIN -99999999999.9

#define PERCENTAGE 2
#define INVERTED_PERCENTAGE 4
#define ADDITIVE 1
#define ADDITIVE_PERCENTAGE 3
#define OVERRIDE -1
#define UNKNOWN_ATTRIBTYPE 0

//#define DEBUG

// ====[ VARIABLES ]===================================================
Handle g_hPlayerInfo;
Handle g_hPlayerArray;
Handle g_hGlobalSettings;
ConVar g_hCvarEnabled;
ConVar g_hCvarPlayerControlEnabled;

ConVar g_cvAssumedFlags;
ConVar g_cvAssumedFlags2;

KeyValues kv_attribs;
KeyValues kv_items;

bool g_bPlayerEnabled[MAXPLAYERS + 1] =  { true, ... };

// ====[ PLUGIN ]======================================================
public Plugin myinfo = {
	name = PLUGIN_NAME,
	author = PLUGIN_AUTHOR,
	description = PLUGIN_NAME,
	version = PLUGIN_VERSION,
	url = PLUGIN_CONTACT
};

// ====[ FUNCTIONS ]===================================================

/* OnPluginStart()
 *
 * When the plugin starts up.
 * -------------------------------------------------------------------------- */
public void OnPluginStart() {
    
    PrintToServer("Starting plugin, loading attribute phrases.");
	LoadTranslations("mannco-attributes.phrases");
    PrintToServer("Attributes loaded.");
	
	// Create convars
	CreateConVar("tf2items_manager_version", PLUGIN_VERSION, PLUGIN_NAME, FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY);
	g_hCvarEnabled = CreateConVar("tf2items_manager", "1", "Enables/disables the manager (0 - Disabled / 1 - Enabled)", FCVAR_REPLICATED|FCVAR_NOTIFY);
	g_hCvarPlayerControlEnabled = CreateConVar("tf2items_manager_playercontrol", "1", "Enables/disables the player's ability to control the manager (0 - Disabled / 1 - Enabled");
	
	g_cvAssumedFlags = CreateConVar("mannco_aflags", "0", "Which flags a new weapon is assumed to have. 0 for none, -1 for all.");
	g_cvAssumedFlags2 = CreateConVar("mannco_aflags2", "0", "Which flags a new weapon is assumed to have. 0 for none, -1 for all.");
	
	// Register console commands
	RegAdminCmd("tf2items_manager_reload", CmdReload, ADMFLAG_GENERIC);
	
	RegConsoleCmd("tf2items_enable", CmdEnable);
	RegConsoleCmd("tf2items_disable", CmdDisable);
	
	// Parse the items list
	ParseItems();
	
	LoadMetadata();
}

public void LoadMetadata()
{
	char buffer[256];
	
	BuildPath(Path_SM, buffer, sizeof(buffer), "configs/mannco-attributes.cfg");
	kv_attribs = CreateKeyValues("MannCoAttributes");
	if (FileToKeyValues(kv_attribs, buffer) == false)
		SetFailState("Error, can't read file containing the attribute metadata : %s", buffer);
	
	KvGetSectionName(kv_attribs, buffer, sizeof(buffer));
	if (StrEqual("attributes", buffer) == false)
		SetFailState("mannco-attributes.cfg structure corrupt, initial tag: \"%s\"", buffer);
	
	WhineAboutUndefinedAttributes();
	
	BuildPath(Path_SM, buffer, sizeof(buffer), "configs/mannco-items.cfg");
	kv_items = CreateKeyValues("MannCoItems");
	if (FileToKeyValues(kv_items, buffer) == false)
		SetFailState("Error, can't read file containing the item metadata : %s", buffer);
	
	KvGetSectionName(kv_items, buffer, sizeof(buffer));
	if (StrEqual("items", buffer) == false)
		SetFailState("mannco-items.cfg structure corrupt, initial tag: \"%s\"", buffer);
	
}

public void WhineAboutUndefinedAttributes()
{
    char buffer[64];
    int data;
    if (KvGotoFirstSubKey(kv_attribs)) {
        do {
            data = -1;
            data = KvGetNum(kv_attribs, "parent", -1);
            if (data == -1) data = KvGetNum(kv_attribs, "flags", -1);
            if (data == -1) data = KvGetNum(kv_attribs, "flags2", -1);
            if (data == -1) {
                KvGetString(kv_attribs, "name", buffer, 64, "unnamed");
                PrintToServer("Undefined attribute: %s", buffer);
            }
        } while (KvGotoNextKey(kv_attribs));
        KvGoBack(kv_attribs);
    }
    
}


int Native_ItemFromNameFragment(Handle plugin, int numParams) {
    
    char fragment[64];
    GetNativeString(1, fragment, 64);
    char buffer[256];
    int finalId = -1;
    char sectionName[64];
    if (KvGotoFirstSubKey(kv_items)) {
        do {
            KvGetString(kv_items, "name", buffer, 256, "");
            if (buffer[0] != '\0') {
                if (StrContains(buffer, fragment, false) != -1) {
                    KvGetSectionName(kv_items, sectionName, 64);
                    finalId = StringToInt(sectionName);
                }
            }
        } while (KvGotoNextKey(kv_items) && finalId < 0);
        KvGoBack(kv_items);
    }
    return finalId;
}

any Native_M_Item_IsKnown(Handle plugin, int numParams)
{
    int id = GetNativeCell(1);
    
    char buffer[64];
    IntToString(id, buffer, 64);
    bool result = KvJumpToKey(kv_items, buffer, false); //false if id is not here
    if (result) {
        KvGoBack(kv_items); //go back to root, or one level up
    }
    return result;
}

int Native_M_Item_GetDebugName(Handle plugin, int numParams)
{
    int id = GetNativeCell(1);
    char buffer[64];
    GetNativeString(2, buffer, 64);
    char buffer2[64];
    IntToString(id, buffer2, 64);
    bool result = KvJumpToKey(kv_items, buffer2, false); //false if id is not here
    if (result) {
        KvGetString(kv_items, "name", buffer, 64, "stinky unknown item");
        KvGoBack(kv_items); //go back to root, or one level up
    } else {
        buffer = "nonexistent item";
    }
    SetNativeString(2, buffer, 64);
}

int Native_M_Item_GetParent(Handle plugin, int numParams)
{
    int id = GetNativeCell(1);
    
    id = Internal_M_Item_GetParent(id);
    
    return id;
}

int Internal_M_Item_GetParent(int id) {
    
    char buffer[64];
    IntToString(id, buffer, 64);
    bool result = KvJumpToKey(kv_items, buffer, false); //false if id is not here
    if (result) {
        int lastItem = -1;
        while (lastItem != id) {
            lastItem = id;
            id = KvGetNum(kv_items, "parent", id);
        }
        KvGoBack(kv_items); //go back to root, or one level up
    }
    
    return id;
    
}

int Native_M_Item_GetSlot(Handle plugin, int numParams)
{
    int id = GetNativeCell(1);
    char buffer[64];
    GetNativeString(2, buffer, 64);
    char buffer2[64];
    IntToString(id, buffer2, 64);
    bool result = KvJumpToKey(kv_items, buffer2, false); //false if id is not here
    if (result) {
        KvGetString(kv_items, "item_slot", buffer, 64, "unknown");
        
        //catch taunts
        if (StrEqual(buffer, "unknown")) {
            bool isTaunt = KvJumpToKey(kv_items, "taunt", false);
            if (isTaunt) {
                buffer = "taunt";
                KvGoBack(kv_items);
            }
        }
        
        //catch newer items w/o a head/misc slot distinction
        if (StrEqual(buffer, "unknown")) {
            char buffer3[64];
            KvGetString(kv_items, "prefab", buffer3, 64, "unknown");
            if (StrEqual(buffer3, "hat")) {
                buffer = "head";
            } else if (StrEqual(buffer3, "misc")) {
                buffer = "misc";
            } else if (StrEqual(buffer3, "grenades")) {
                buffer = "misc";
            } else if (StrEqual(buffer3, "valve misc")) {
                buffer = "misc";
            } else if (StrEqual(buffer3, "hat decoration")) {
                buffer = "head";
            } else if (StrEqual(buffer3, "halloween hat")) {
                buffer = "head";
            } else if (StrEqual(buffer3, "valve no_craft hat")) {
                buffer = "head";
            } else if (StrEqual(buffer3, "backpack")) {
                buffer = "misc";
            } else if (StrEqual(buffer3, "tournament_medal")) {
                buffer = "misc";
            } else if (StrEqual(buffer3, "halloween misc")) {
                buffer = "misc";
            } else if (StrEqual(buffer3, "no_craft hat")) {
                buffer = "head";
            } else if (StrEqual(buffer3, "score_reward_hat")) {
                buffer = "head";
            } else if (StrEqual(buffer3, "beard")) {
                buffer = "misc";
            }
        }
        
        KvGoBack(kv_items); //go back to root, or one level up
    }
    SetNativeString(2, buffer, 64);
}

any Native_M_Attrib_IsKnown(Handle plugin, int numParams)
{
    int id = GetNativeCell(1);
    char buffer[64];
    IntToString(id, buffer, 64);
    bool result = KvJumpToKey(kv_attribs, buffer, false); //false if id is not here
    if (result) {
        KvGoBack(kv_attribs); //go back to root, or one level up
    }
    return result;
}

int Native_M_Attrib_GetDebugName(Handle plugin, int numParams)
{
    int id = GetNativeCell(1);
    char buffer[64];
    GetNativeString(2, buffer, 64);
    char buffer2[64];
    IntToString(id, buffer2, 64);
    bool result = KvJumpToKey(kv_attribs, buffer2, false); //false if id is not here
    if (result) {
        KvGetString(kv_attribs, "name", buffer, 64, "stinky unknown attribute");
        KvGoBack(kv_attribs); //go back to root, or one level up
    } else {
        buffer = "nonexistent attribute";
    }
    SetNativeString(2, buffer, 64);
}

int Native_M_Attrib_GetParent(Handle plugin, int numParams)
{
    int id = GetNativeCell(1);
    char buffer[64];
    IntToString(id, buffer, 64);
    bool result = KvJumpToKey(kv_attribs, buffer, false); //false if id is not here
    if (result) {
        int lastAttribute = -1;
        while (lastAttribute != id) {
            lastAttribute = id;
            id = KvGetNum(kv_attribs, "parent", id);
        }
        KvGoBack(kv_attribs); //go back to root, or one level up
    }
    return id;
}

int Native_M_Attrib_GetDatatype(Handle plugin, int numParams)
{
    int id = GetNativeCell(1);
    return Internal_M_Attrib_GetDatatype(id);
}

int Internal_M_Attrib_GetDatatype(int id) {
    
    char buffer[64], buffer2[64];
    IntToString(id, buffer2, 64);
    bool result = KvJumpToKey(kv_attribs, buffer2, false); //false if id is not here
    if (result) {
        KvGetString(kv_attribs, "description_format", buffer, 64, "value_is_percentage");
        KvGoBack(kv_attribs); //go back to root, or one level up
        if (StrEqual(buffer, "value_is_percentage")) {
            return PERCENTAGE;
        } else if (StrEqual(buffer, "value_is_inverted_percentage")) {
            return INVERTED_PERCENTAGE; //still percentage, just good and bad are reversed
        } else if (StrEqual(buffer, "value_is_additive")) {
            return ADDITIVE;
        } else if (StrEqual(buffer, "value_is_additive_percentage")) {
            return ADDITIVE_PERCENTAGE; //still additive, just smaller unit
        } else if (StrEqual(buffer, "value_is_or")) {
            return OVERRIDE; //override
        } else {
            return UNKNOWN_ATTRIBTYPE; //default
        }
    } else {
        return UNKNOWN_ATTRIBTYPE; //default
    }
    
}

any Native_M_Attrib_GetMaxIncrease(Handle plugin, int numParams)
{
    int id = GetNativeCell(1);
    float maxIncrease = -1.0;
    char buffer[64];
    IntToString(id, buffer, 64);
    bool result = KvJumpToKey(kv_attribs, buffer, false); //false if id is not here
    if (result) {
        maxIncrease = KvGetFloat(kv_attribs, "max_increase", -1.0);
        KvGoBack(kv_attribs); //go back to root, or one level up
    }
    return maxIncrease;
}

any Native_M_Attrib_GetMaxDecrease(Handle plugin, int numParams)
{
    int id = GetNativeCell(1);
    float maxDecrease = 1.0;
    char buffer[64];
    IntToString(id, buffer, 64);
    bool result = KvJumpToKey(kv_attribs, buffer, false); //false if id is not here
    if (result) {
        maxDecrease = KvGetFloat(kv_attribs, "maximum_decrease", 1.0);
        KvGoBack(kv_attribs); //go back to root, or one level up
    }
    return maxDecrease;
}

any Native_M_Attrib_GetInterval(Handle plugin, int numParams)
{
    int id = GetNativeCell(1);
    float interval = 1.0;
    char buffer[64];
    IntToString(id, buffer, 64);
    bool result = KvJumpToKey(kv_attribs, buffer, false); //false if id is not here
    if (result) {
        interval = KvGetFloat(kv_attribs, "interval", 1.0);
        KvGoBack(kv_attribs); //go back to root, or one level up
    }
    return interval;
}

any Native_M_Attrib_GetMaximum(Handle plugin, int numParams)
{
    int id = GetNativeCell(1);
    float maximum = FLT_MAX;
    char buffer[64];
    IntToString(id, buffer, 64);
    bool result = KvJumpToKey(kv_attribs, buffer, false); //false if id is not here
    if (result) {
        maximum = KvGetFloat(kv_attribs, "maximum", FLT_MAX);
        KvGoBack(kv_attribs); //go back to root, or one level up
    }
    return maximum;
}

any Native_M_Attrib_GetMinimum(Handle plugin, int numParams)
{
    int id = GetNativeCell(1);
    float minimum = FLT_MIN;
    char buffer[64];
    IntToString(id, buffer, 64);
    bool result = KvJumpToKey(kv_attribs, buffer, false); //false if id is not here
    if (result) {
        minimum = KvGetFloat(kv_attribs, "minimum", FLT_MIN);
        KvGoBack(kv_attribs); //go back to root, or one level up
    }
    return minimum;
}

any Native_M_Attrib_GetDesc(Handle plugin, int numParams)
{
    int attribId = GetNativeCell(1);
    float attribValue = view_as<float>(GetNativeCell(2));
    int attribMode = GetNativeCell(3);
    char descTag[64];
    char descBuffer[256];
    int client = GetNativeCell(5);
    
    char idAsString[64];
    char attribAsString[64];
    
    if (attribMode == 0) {
        attribMode = Internal_M_Attrib_GetDatatype(attribId);
    }
    
    if (attribMode == 1) {
        Format(attribAsString, 64, "%.1f", attribValue);
    } else if (attribMode == 2) {
        Format(attribAsString, 64, "%.1f", 100.0 * (attribValue - 1.0));
    } else if (attribMode == 3) {
        Format(attribAsString, 64, "%.1f", 100.0 * attribValue);
    } else if (attribMode == 4) {
        Format(attribAsString, 64, "%.1f", 100.0 * (1.0 / attribValue - 1.0));
    }
    
    IntToString(attribId, idAsString, 64);
    bool result = KvJumpToKey(kv_attribs, idAsString, false); //false if id is not here
    if (result) {
        KvGetString(kv_attribs, "description_string", descTag, sizeof(descTag), "Untagged_Attribute");
        Format(descBuffer, 256, "%T", descTag, client, attribAsString);
        KvGoBack(kv_attribs); //go back to root, or one level up
    }
    
    SetNativeString(4, descBuffer, 256);
}

any Native_M_FlagsAgree(Handle plugin, int numParams)
{
    int item = GetNativeCell(1);
    int attribute = GetNativeCell(2);
    char buffer[64], buffer2[64];
    bool result;
    bool result2;
    int attrib_flags = 0;
    int attrib_flags2 = 0;
    int item_flags = g_cvAssumedFlags.IntValue;
    int item_flags2 = g_cvAssumedFlags2.IntValue;
    IntToString(attribute, buffer, 64);
    result = KvJumpToKey(kv_attribs, buffer, false);
    if (result) {
        attrib_flags = KvGetNum(kv_attribs, "flags", 0);
        attrib_flags2 = KvGetNum(kv_attribs, "flags2", 0);
        KvGoBack(kv_attribs);
    }
    IntToString(item, buffer2, 64);
    result2 = KvJumpToKey(kv_items, buffer2, false);
    if (result2) {
        item_flags = KvGetNum(kv_items, "flags", g_cvAssumedFlags.IntValue);
        item_flags2 = KvGetNum(kv_items, "flags2", g_cvAssumedFlags2.IntValue);
        KvGoBack(kv_items);
    }
    //PrintToServer("Item: %d (%X %X), Attribute: %d (%X %X), Combined: %X %X", item, item_flags, item_flags2, attribute, attrib_flags, attrib_flags2, attrib_flags & ~item_flags, attrib_flags2 & ~item_flags2); //flags results
    return ((attrib_flags & ~item_flags) == 0 && (attrib_flags2 & ~item_flags2) == 0); //true if not a single expected flag is missing
}

int Native_TryAttributeFlip(Handle plugin, int numParams)
{

    int attributeId = GetNativeCell(1);
    int attributeType = GetNativeCell(2);
    float attributeValue = GetNativeCell(3);
    
    char buffer[64], buffer2[64];
    IntToString(attributeId, buffer, 64);
    bool result = KvJumpToKey(kv_attribs, buffer, false);
    PrintToServer("Trying to flip attribute: %d (%d %f)", attributeId, attributeType, attributeValue);
    if (result) {
        int counterpart = KvGetNum(kv_attribs, "counterpart", attributeId);
        int counterpart_min = KvGetNum(kv_attribs, "counterpart_min", -1);
        int counterpart_max = KvGetNum(kv_attribs, "counterpart_max", -1);
        int inverted = KvGetNum(kv_attribs, "inverted", 0);
        KvGetString(kv_attribs, "effect_type", buffer2, 64, "neutral");
        PrintToServer("Counterpart found: %d (currently %s).", counterpart, buffer2);
        //if attribute type is inverted %, values must be < 1
        if (counterpart_min == -1 && counterpart_max == -1) { //make some educated guesses
            if ((attributeType == INVERTED_PERCENTAGE) && (attributeValue > 1)) {
                attributeId = counterpart;
                PrintToServer("Swapped due to >1 value from inverted percentage");
            } else if ((attributeType == PERCENTAGE) && (attributeValue < 1)) {
                attributeId = counterpart;
                PrintToServer("Swapped due to <1 value from percentage");
            } else if ((StrEqual(buffer2, "negative")) && (attributeType != PERCENTAGE && attributeType != INVERTED_PERCENTAGE) && attributeValue > 0) {
                attributeId = counterpart;
                PrintToServer("Swapped to nonnegative counterpart");
            } else if ((StrEqual(buffer2, "positive")) && (attributeType != PERCENTAGE && attributeType != INVERTED_PERCENTAGE) && attributeValue < 0) {
                attributeId = counterpart;
                PrintToServer("Swapped to nonpositive counterpart");
            }
        } else { //behavior is complicated enough that it's been manually specified
            if (counterpart_min != -1 && attributeValue < counterpart_min) {
                attributeId = counterpart;
            } else if (counterpart_max != -1 && attributeValue > counterpart_max) {
                attributeId = counterpart;
            }
        }
        KvGoBack(kv_attribs);
    }
    return attributeId;
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	CreateNative("ApplyItemModification", Native_ApplyItemModification);
	CreateNative("QueryAttributeValue", Native_QueryAttributeValue);
	CreateNative("QueryAttributeEffect", Native_QueryAttributeEffect);
	CreateNative("DumpAttributes", Native_DumpAttributes);
	CreateNative("ItemFromNameFragment", Native_ItemFromNameFragment);
    CreateNative("TryAttributeFlip", Native_TryAttributeFlip);
    
	CreateNative("M_Item_IsKnown", Native_M_Item_IsKnown);
	CreateNative("M_Attrib_IsKnown", Native_M_Attrib_IsKnown);
    
	CreateNative("M_Item_GetParent", Native_M_Item_GetParent);
	CreateNative("M_Attrib_GetParent", Native_M_Attrib_GetParent);
    
	CreateNative("M_Item_GetDebugName", Native_M_Item_GetDebugName);
	CreateNative("M_Attrib_GetDebugName", Native_M_Attrib_GetDebugName);
    
	CreateNative("M_Item_GetSlot", Native_M_Item_GetSlot);
	CreateNative("M_Attrib_GetDatatype", Native_M_Attrib_GetDatatype);
    
	CreateNative("M_Attrib_GetMaxIncrease", Native_M_Attrib_GetMaxIncrease);
	CreateNative("M_Attrib_GetMaxDecrease", Native_M_Attrib_GetMaxDecrease);
	CreateNative("M_Attrib_GetInterval", Native_M_Attrib_GetInterval);
	CreateNative("M_Attrib_GetMaximum", Native_M_Attrib_GetMaximum);
	CreateNative("M_Attrib_GetMinimum", Native_M_Attrib_GetMinimum);
    
    CreateNative("M_Attrib_GetDesc", Native_M_Attrib_GetDesc);
	CreateNative("M_FlagsAgree", Native_M_FlagsAgree);
    
	return APLRes_Success;
}

/* TF2Items_OnGiveNamedItem()
 *
 * When an item is about to be given to a client.
 * -------------------------------------------------------------------------- */
public Action TF2Items_OnGiveNamedItem(int client, char[] classname, int itemDefIndex, Handle &override) {
	// If disabled, use the default values.
	if (!GetConVarBool(g_hCvarEnabled) || (GetConVarBool(g_hCvarPlayerControlEnabled) && !g_bPlayerEnabled[client]))
		return Plugin_Continue;
	
	// If another plugin already tryied to override the item, let him go ahead.
	if (override != null)
		return Plugin_Continue; // Plugin_Changed
	
    //use the most recent, valid item.
    itemDefIndex = Internal_M_Item_GetParent(itemDefIndex);
    
	// Find item. If any is found, override the attributes with these.
	Handle item = FindItem(client, itemDefIndex);
	if (item != null) {
		override = item;
		return Plugin_Changed;
	}
	
	// None found, use default values.
	return Plugin_Continue;
}

// only one is needed.
// Doing this for just-in-casenesses sake

public void OnClientConnected(int client) {
	g_bPlayerEnabled[client] = true;
}

public void OnClientDisconnect(int client) {
	g_bPlayerEnabled[client] = true;
}

/*
 * ------------------------------------------------------------------
 *    ______                                          __    
 *   / ____/___  ____ ___  ____ ___  ____ _____  ____/ /____
 *  / /   / __ \/ __ `__ \/ __ `__ \/ __ `/ __ \/ __  / ___/
 * / /___/ /_/ / / / / / / / / / / / /_/ / / / / /_/ (__  ) 
 * \____/\____/_/ /_/ /_/_/ /_/ /_/\__,_/_/ /_/\__,_/____/  
 * ------------------------------------------------------------------
 */

/* CmdReload()
**
** Reloads the item list.
** -------------------------------------------------------------------------- */
public Action CmdReload(int client, int action) {
	// Fire a message telling about the operation.
	if (client)
		ReplyToCommand(client, "Reloading items list");
	else
		LogMessage("Reloading items list");
	
	// Call the ParseItems function.
	ParseItems();
	return Plugin_Handled;
}

public Action CmdEnable(int client, int action) {
	if (!GetConVarBool(g_hCvarPlayerControlEnabled)) {
		ReplyToCommand(client, "The server administrator has disabled this command.");
		return Plugin_Handled;
	}

	ReplyToCommand(client, "Re-enabling TF2Items for you.");
	g_bPlayerEnabled[client] = true;
	return Plugin_Handled;
}

public Action CmdDisable(int client, int action) {
	if (!GetConVarBool(g_hCvarPlayerControlEnabled)) {
		ReplyToCommand(client, "The server administrator has disabled this command.");
		return Plugin_Handled;
	}
	
	ReplyToCommand(client, "Disabling TF2Items for you.");
	g_bPlayerEnabled[client] = false;
	return Plugin_Handled;
}

/*
 * ------------------------------------------------------------------
 *     __  ___                                                  __ 
 *    /  |/  /___ _____  ____ _____ ____  ____ ___  ___  ____  / /_
 *   / /|_/ / __ `/ __ \/ __ `/ __ `/ _ \/ __ `__ \/ _ \/ __ \/ __/
 *  / /  / / /_/ / / / / /_/ / /_/ /  __/ / / / / /  __/ / / / /_  
 * /_/  /_/\__,_/_/ /_/\__,_/\__, /\___/_/ /_/ /_/\___/_/ /_/\__/  
 *                          /____/                                 
 * ------------------------------------------------------------------
 */

/* FindItem()
**
** Tryies to find a custom item usable by the client.
** -------------------------------------------------------------------------- */
Handle FindItem(int client, int itemDefIndex) {
	// Check if the player is valid
	if (!IsValidClient(client))
		return null;
	
	// Retrieve the STEAM auth string
	char auth[64];
	GetClientAuthId(client, AuthId_Steam2, auth, sizeof(auth));
	
	// Check if it's on the list. If not, try with the global settings.
	Handle itemArray = null; 
	GetTrieValue(g_hPlayerInfo, auth, itemArray);
	
	// Check for each.
	Handle output;
	output = FindItemOnArray(client, itemArray, itemDefIndex);
	if (output == null)
		output = FindItemOnArray(client, g_hGlobalSettings, itemDefIndex);
	
	// Done
	return output;
}

//Cuts out the chaff and just searches the array.
Handle FindItemSimple(int itemDefIndex) {

	Handle array = g_hGlobalSettings;
	
	for (int itemEntry = 0; itemEntry < GetArraySize(array); itemEntry++) {
		// Retrieve item
		Handle item = GetArrayCell(array, itemEntry, ARRAY_ITEM);
		if (item == null)
			continue;
			
		// Is the item we're looking for? If so return item, but first
		// check if it's possible due to the 
		if (TF2Items_GetItemIndex(item) == itemDefIndex)
			return item;
	}
	
	// Done, returns wildcard item if it exists.
	return null;
	
}

/* FindItemOnArray()
**
** 
** -------------------------------------------------------------------------- */
Handle FindItemOnArray(int client, Handle array, int itemDefIndex) {
	// Check if the array is valid.
	if (array == null)
		return null;
		
	Handle wildcardItem = null;
	
	// Iterate through each item entry and close the handle.
	for (int itemEntry = 0; itemEntry < GetArraySize(array); itemEntry++) {
		// Retrieve item
		Handle item = GetArrayCell(array, itemEntry, ARRAY_ITEM);
		int itemflags = GetArrayCell(array, itemEntry, ARRAY_FLAGS);
		if (item == null)
			continue;
		
		// Is a wildcard item? If so, store it.
		if (TF2Items_GetItemIndex(item) == -1 && wildcardItem == null)
			if (CheckItemUsage(client, itemflags))
				wildcardItem = item;
			
		// Is the item we're looking for? If so return item, but first
		// check if it's possible due to the 
		if (TF2Items_GetItemIndex(item) == itemDefIndex)
			if (CheckItemUsage(client, itemflags))
				return item;
		}
	
	// Done, returns wildcard item if it exists.
	return wildcardItem;
}

/* CheckItemUsage()
 *
 * Checks if a client has any of the specified flags.
 * -------------------------------------------------------------------------- */
bool CheckItemUsage(int client, int flags) {
	if (flags == 0)
		return true;
	
	int clientFlags = GetUserFlagBits(client);
	if (clientFlags & ADMFLAG_ROOT)
		return true;
	else 
		return (clientFlags & flags) != 0;
}

int Native_DumpAttributes(Handle plugin, int numParams) {
    
    int itemId = GetNativeCell(1);
    int size = GetNativeCell(4);
    int[] attributes = new int[size];
    float[] values = new float[size];
    
    GetNativeArray(2, attributes, size);
    GetNativeArray(3, values, size);
    
    Handle item = FindItemSimple(itemId);
    
    if (item != null) {
        int numAttributes = TF2Items_GetNumAttributes(item);
    	for (int i = 0; i < numAttributes; i++) {
    		int currentAttributeId = TF2Items_GetAttributeId(item, i);
    		float currentAttributeValue = TF2Items_GetAttributeValue(item, i);
    		attributes[i] = currentAttributeId;
    		values[i] = currentAttributeValue;
    	}
    	SetNativeArray(2, attributes, size);
    	SetNativeArray(3, values, size);
    	return numAttributes;
    }
    
    return 0;
}

/*
 *
 * Checks if a client has any of the specified flags.
 * item: the item id
 * attribute: the attribute id
 * modifier: the modifier flag to use
 * mode: if -1, override.
 * if 0, item default.
 * if 1, add (additive, additive percentage)
 * if 2, multiply (percentage, inverted percentage)
 * */
int Native_ApplyItemModification(Handle plugin, int numParams) {
    
    int itemId = GetNativeCell(1);
    int attribute = GetNativeCell(2);
    float modifier = view_as<float>(GetNativeCell(3));
    int mode = GetNativeCell(4);
    char logLabel[64];
    
    GetNativeString(5, logLabel, 64);
	
	Handle item = FindItemSimple(itemId);
	
	if (item == null) {
		item = MakeBlankItem(itemId);
        LogMessage("Item not found, creating blank");
	}
	
	float previousValue = QueryAttribute(item, attribute, mode);
	float newValue = InternalQueryAttributeEffect(previousValue, modifier, mode);
	int attributeNum = SetAttribute(item, attribute, newValue);
	
    if (logLabel[0] != '\0') {
    
        char buffer[256];
        
        BuildPath(Path_SM, buffer, sizeof(buffer), "configs/mannco-history.cfg");
        File file = OpenFile(buffer, "a+");
        file.WriteLine("%s %d %d %f", logLabel, itemId, attribute, modifier);
        file.Close();
    
    }
    
    return attributeNum;
	
}

any Native_QueryAttributeEffect(Handle plugin, int numParams) {
    
    int itemId = GetNativeCell(1);
    int attribute = GetNativeCell(2);
    float modifier = view_as<float>(GetNativeCell(3));
    int mode = GetNativeCell(4);
	
	Handle item = FindItemSimple(itemId);
	
	if (item == null) {
		item = MakeBlankItem(itemId);
        LogMessage("Item not found, creating blank");
	}
	
	float previousValue = QueryAttribute(item, attribute, mode);
	return InternalQueryAttributeEffect(previousValue, modifier, mode);
	
}

any Native_QueryAttributeValue(Handle plugin, int numParams) {
    
    int itemId = GetNativeCell(1);
    int attribute = GetNativeCell(2);
    int mode = GetNativeCell(3);
	
	Handle item = FindItemSimple(itemId);
	
	if (item == null) {
		item = MakeBlankItem(itemId);
        LogMessage("Item not found, creating blank");
	}
	
	return QueryAttribute(item, attribute, mode);
	
}

float QueryAttribute(Handle item, int attribute, int mode) {
    
    int numAttributes = TF2Items_GetNumAttributes(item);
	for (int i = 0; i < numAttributes; i++) {
		int currentAttributeId = TF2Items_GetAttributeId(item, i);
		if (attribute == currentAttributeId) {
			return TF2Items_GetAttributeValue(item, i);
		}
	}
	
	int itemIndex = TF2Items_GetItemIndex(item);
	int iAttribIndices[20];
	float flAttribValues[20];
	int numStaticAttribs = TF2Attrib_GetStaticAttribs(itemIndex, iAttribIndices, flAttribValues, 20);
	for (int i = 0; i < numStaticAttribs; i++) {
		int currentAttributeId = iAttribIndices[i];
		if (attribute == currentAttributeId) {
			return flAttribValues[i];
		}
	}
	
	if (mode == 2 || mode == 4) return 1.0; //multiplicative identity
	
	return 0.0;
	
    
}

float InternalQueryAttributeEffect(float previousValue, float modifier, int mode) {
    
    if (mode == -1) return modifier;
    
    if (mode == 0) mode = 2; //TODO use a table for which attributes are additive or multiplicative
    
    if (mode == 1 || mode == 3) {
        return previousValue + modifier;
    }
    
    if (mode == 2 || mode == 4) {
        return previousValue * modifier;
    }
    
    return previousValue;
    
}

int SetAttribute(Handle item, int attribute, float finalModifier) {
    
    int numAttributes = TF2Items_GetNumAttributes(item);
	for (int i = 0; i < numAttributes; i++) {
		int currentAttributeId = TF2Items_GetAttributeId(item, i);
		if (attribute == currentAttributeId) {
		    TF2Items_SetAttribute(item, i, attribute, finalModifier);
		    return i;
		}
	}
	
	TF2Items_SetAttribute(item, numAttributes, attribute, finalModifier);
	TF2Items_SetNumAttributes(item, numAttributes + 1);
	return numAttributes;
    
}

//Legacy code for how attributes were updated in the past.
int UpdateAttribute(Handle item, int attribute, float modifier, int mode) {
	
	int numAttributes = TF2Items_GetNumAttributes(item);
	for (int i = 0; i < numAttributes; i++) {
		int currentAttributeId = TF2Items_GetAttributeId(item, i);
		if (attribute == currentAttributeId) {
			float attributeStrength = TF2Items_GetAttributeValue(item, i);
			if (mode == 0) mode = 2; //TODO use a table for which attributes are additive or multiplicative
			if (mode == -1) {
				attributeStrength = modifier;
			} else if (mode == 1) {
				attributeStrength += modifier;
			} else if (mode == 2) {
				attributeStrength *= modifier;
			}
			TF2Items_SetAttribute(item, i, attribute, attributeStrength);
			return i;
		}
	}
	
	int itemIndex = TF2Items_GetItemIndex(item);
	int iAttribIndices[20];
	float flAttribValues[20];
	int numStaticAttribs = TF2Attrib_GetStaticAttribs(itemIndex, iAttribIndices, flAttribValues, 20);
	for (int i = 0; i < numStaticAttribs; i++) {
		int currentAttributeId = iAttribIndices[i];
		if (attribute == currentAttributeId) {
			LogMessage("Static attribute found, multiplying!");
			float attributeStrength = flAttribValues[i];
			if (mode == 0) mode = 2; //TODO use a table for which attributes are additive or multiplicative
			if (mode == -1) {
				attributeStrength = modifier;
			} else if (mode == 1) {
				attributeStrength += modifier;
			} else if (mode == 2) {
				attributeStrength *= modifier;
			}
			TF2Items_SetAttribute(item, numAttributes, attribute, attributeStrength);
			TF2Items_SetNumAttributes(item, numAttributes + 1);
			return i;
		}
	}
	
	TF2Items_SetAttribute(item, numAttributes, attribute, modifier);
	TF2Items_SetNumAttributes(item, numAttributes + 1);
	return numAttributes;
	
	
	
}

Handle MakeBlankItem(int itemId) {

	Handle item = TF2Items_CreateItem(OVERRIDE_ALL);
	int attrflags = 0;
	
	TF2Items_SetItemIndex(item, itemId);
	
	attrflags |= PRESERVE_ATTRIBUTES;
	attrflags |= OVERRIDE_ATTRIBUTES;
	
	int flags = 0;
	
	TF2Items_SetFlags(item, attrflags);
	PushArrayCell(g_hGlobalSettings, 0);
	SetArrayCell(g_hGlobalSettings, GetArraySize(g_hGlobalSettings)-1, item, ARRAY_ITEM);
	SetArrayCell(g_hGlobalSettings, GetArraySize(g_hGlobalSettings)-1, flags, ARRAY_FLAGS);
	
	return item;
	
}

/* ParseItems()
 *
 * Reads up the items information from the Key-Values.
 * -------------------------------------------------------------------------- */
void ParseItems() {
	char buffer[256], split[16][64];
	
	// Destroy the current items data.
	DestroyItems();
	
	// Create key values object and parse file.
	BuildPath(Path_SM, buffer, sizeof(buffer), "configs/tf2items.weapons.txt");
	KeyValues kv = CreateKeyValues("TF2Items");
	if (FileToKeyValues(kv, buffer) == false)
		SetFailState("Error, can't read file containing the item list : %s", buffer);
	
	// Check the version
	KvGetSectionName(kv, buffer, sizeof(buffer));
	if (StrEqual("custom_weapons_v3", buffer) == false)
		SetFailState("tf2items.weapons.txt structure corrupt or incorrect version: \"%s\"", buffer);
	
	// Create the array and trie to store & access the item information.
	g_hPlayerArray = CreateArray();
	g_hPlayerInfo = CreateTrie();
	
	#if defined DEBUG
		LogMessage("Parsing items");
		LogMessage("{");
	#endif 
	
	// Jump into the first subkey and go on.
	if (KvGotoFirstSubKey(kv)) {
		do {
			// Retrieve player information and split into multiple strings.
			KvGetSectionName(kv, buffer, sizeof(buffer));
			int auths = ExplodeString(buffer, ";", split, 16, 64);
			
			// Create new array entry and upload to the array.
			Handle entry = CreateArray(2);
			PushArrayCell(g_hPlayerArray, entry);
			
			#if defined DEBUG
				LogMessage("  Entry", buffer);
				LogMessage("  {");
				LogMessage("    Used by:");
			#endif
			
			// Iterate through each player auth strings and make an
			// entry for each.
			for (int auth = 0; auth < auths; auth++) {
				TrimString(split[auth]);
				SetTrieValue(g_hPlayerInfo, split[auth], entry);
				
				#if defined DEBUG
					LogMessage("    \"%s\"", split[auth]);
				#endif
			}
			
			#if defined DEBUG
				LogMessage("");
			#endif
			
			// Read all the item entries
			ParseItemsEntry(kv, entry);
			
			#if defined DEBUG
				LogMessage("  }");
			#endif
		}
		while (KvGotoNextKey(kv));
			KvGoBack(kv);
	}
	
	// Close key values
	delete kv;
	
	// Try to find the global item settings.
	GetTrieValue(g_hPlayerInfo, "*", g_hGlobalSettings);
	
	// Done.
	#if defined DEBUG
		LogMessage("}");
	#endif
}

/* ParseItemsEntry()
 *
 * Reads up a particular items entry.
 * -------------------------------------------------------------------------- */
void ParseItemsEntry(KeyValues kv, Handle entry) {
	char buffer[64], buffer2[64], split[2][64];
	
	// Jump into the first subkey.
	if (KvGotoFirstSubKey(kv)) {
		do {
			Handle item = TF2Items_CreateItem(OVERRIDE_ALL);
			int attrflags = 0;
			
			// Retrieve item definition index and store.
			KvGetSectionName(kv, buffer, sizeof(buffer));
			if (buffer[0] == '*')
				TF2Items_SetItemIndex(item, -1);
			else
				TF2Items_SetItemIndex(item, StringToInt(buffer));
			
			#if defined DEBUG
				LogMessage("    Item: %i", TF2Items_GetItemIndex(item));
				LogMessage("    {");
			#endif
			
			// Retrieve entity level
			int level = KvGetNum(kv, "level", -1);
			if (level != -1) {
				TF2Items_SetLevel(item, level);
				attrflags |= OVERRIDE_ITEM_LEVEL;
			}
			
			#if defined DEBUG
				if (attrflags & OVERRIDE_ITEM_LEVEL)
					LogMessage("      Level: %i", TF2Items_GetLevel(item));
			#endif
			
			// Retrieve entity quality
			int quality = KvGetNum(kv, "quality", -1);
			if (quality != -1) {
				TF2Items_SetQuality(item, quality);
				attrflags |= OVERRIDE_ITEM_QUALITY;
			}
			
			#if defined DEBUG
				if (attrflags & OVERRIDE_ITEM_QUALITY)
					LogMessage("      Quality: %i", TF2Items_GetQuality(item));
			#endif
			
			// Check for attribute preservation key
			int preserve = KvGetNum(kv, "preserve-attributes", -1);
			if (preserve == 1)
				attrflags |= PRESERVE_ATTRIBUTES;
			else {
				preserve = KvGetNum(kv, "preserve_attributes", -1);
				if (preserve == 1)
					attrflags |= PRESERVE_ATTRIBUTES;
			}
			
			#if defined DEBUG
				LogMessage("      Preserve Attributes: %s", (attrflags & PRESERVE_ATTRIBUTES)?"true":"false");
			#endif
			
			// Read all the attributes
			int attributeCount = 0;
			for (;;) {
				// Format the attribute entry name
				Format(buffer, sizeof(buffer), "%i", attributeCount+1);
				
				// Try to read the attribute
				KvGetString(kv, buffer, buffer2, sizeof(buffer2));
				
				// If not found, break.
				if (buffer2[0] == '\0') break;
				
				// Split the information in two buffers
				ExplodeString(buffer2, ";", split, 2, 64);
				int attribute = StringToInt(split[0]);
				float value = StringToFloat(split[1]);
				
				// Attribute found, set information.
				TF2Items_SetAttribute(item, attributeCount, attribute, value);
				
				#if defined DEBUG
					LogMessage("      Attribute[%i] : %i / %f",
						attributeCount,
						TF2Items_GetAttributeId(item, attributeCount),
						TF2Items_GetAttributeValue(item, attributeCount)
					);
				#endif
				
				// Increase attribute count and continue.
				attributeCount++;
			}
			
			// Done, set attribute count and upload.
			if (attributeCount != 0) {
				TF2Items_SetNumAttributes(item, attributeCount);
				attrflags |= OVERRIDE_ATTRIBUTES;
			}
			
			// Retrieve the admin flags
			KvGetString(kv, "admin-flags", buffer, sizeof(buffer), "");
			int flags = ReadFlagString(buffer);
			
			// Set flags and upload.
			TF2Items_SetFlags(item, attrflags);
			PushArrayCell(entry, 0);
			SetArrayCell(entry, GetArraySize(entry)-1, item, ARRAY_ITEM);
			SetArrayCell(entry, GetArraySize(entry)-1, flags, ARRAY_FLAGS);
			
			#if defined DEBUG
				LogMessage("      Flags: %05b", TF2Items_GetFlags(item));
				LogMessage("      Admin: %s", ((flags == 0)? "(none)":buffer));
				LogMessage("    }");
			#endif
		}
		while (KvGotoNextKey(kv));
			KvGoBack(kv);
	}
}

/* DestroyItems()
 *
 * Destroys the current list for items.
 * -------------------------------------------------------------------------- */
void DestroyItems() {
	if (g_hPlayerArray != null) {
		// Iterate through each player and retrieve the internal
		// weapon list.
		for (int entry = 0; entry < GetArraySize(g_hPlayerArray); entry++) {
			// Retrieve the item array.
			Handle itemArray = GetArrayCell(g_hPlayerArray, entry);
			if (itemArray == null)
				continue;
			
			// Iterate through each item entry and close the handle.
			for (int itemEntry = 0; itemEntry < GetArraySize(itemArray); itemEntry++) {
				// Retrieve item
				Handle item = GetArrayCell(itemArray, itemEntry);
				
				// Close handle
				delete item;
			}
		}
		
		// Done, free array
		delete g_hPlayerArray;
	}
	
	// Free player trie
	delete g_hPlayerInfo;
	
	// Done
	g_hGlobalSettings = null;
}

/* IsValidClient()
 *
 * Checks if a client is valid.
 * -------------------------------------------------------------------------- */
bool IsValidClient(int client) {
	if (client < 1 || client > MaxClients)
		return false;
	if (!IsClientConnected(client))
		return false;
	return IsClientInGame(client);
}
