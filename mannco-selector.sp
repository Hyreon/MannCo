#pragma semicolon 1 // Force strict semicolon mode.
// ====[ INCLUDES ]====================================================
#include <sourcemod>
#include <sdktools_sound>
#define REQUIRE_EXTENSIONS
#include <tf2items>
#include <mannco-manager>

#define PLUGIN_NAME "[TF2Items] Mann Co. Gamemode"
#define PLUGIN_AUTHOR "Hyreon"
#define PLUGIN_VERSION "1.0"
#define PLUGIN_CONTACT "Hyreon#9109"

#define CHOICE1 "#choice1"
#define CHOICE2 "#choice2"
#define CHOICE3 "#choice3"

//flags need to work (flags2 now, also :\)

//we want menus and SFX for 5 things:
//ON RESPAWN: Display the changes to the custom weapons you are using. (no sfx)
// - Only display attributes changed by the mod
// - Cycle through primary, secondary, melee etc with menu options
//ON RESPAWN, at least 10 lives with one item, 10% chance per life: Ask the user what they think of it (any item in their kit).
// - Boring: nominate for a rework
// - Weak: nominate for a positive mod
// - Strong: nominate for a negative mod
// - Confusing: nominate for a revert
// - Don't care: don't nominate
//FIRST MINUTE OF A ROUND, USUALLY SETUP: Vote on which of 5 changes (rework, mod, tweak, nothing, revert)
// - Rework: Apply 2/3 major changes, and ignore permanent maximums(!)
// - Mod: Reject attributes flagged as minor, and reject the 15% least significant values
// - Tweak: Reject attributes flagged as major, and reject the 50% most significant values
//WHEN TOO MANY PLAYERS LEAVE/JOIN: Play a sound effect indicating whether the mod is active or not. (Pop-up only)
// - Value changes every round to reflect the average playercount of the last 50 rounds.
// - There must be 75% of this (allows highlander).
//WHEN A ROUND IS WON: Notify players of the outcome. (Pop-up only)
// - Say the new effect, and the winning team
// - For stalemates, pick the third most popular choice (or a random one)

#define ItemPreservedSoundFile "ui/duel_score_behind.wav"
#define ItemRevampedSoundFile "ui/duel_event.wav"

//NOT PRECACHED
#define ItemQuerySoundFile "ui/cyoa_objective_panel_expand.wav"
#define BoringResponseSoundFile "ui/cyoa_node_absent.wav"
#define NominateResponseSoundFile "ui/cyoa_node_activate.wav"

//NOT PRECACHED
#define RoundInvalidSoundFile "ui/duel_challenge_rejected_with_restriction.wav"
#define NewRoundValidSoundFile "ui/duel_challenge_with_restriction.wav"

//NOT PRECACHED
#define VoteBeginsSoundFile "ui/vote_started.wav"
#define YourVoteWonSoundFile "ui/vote_success.wav"
#define YourVoteLostSoundFile "ui/vote_failure.wav"
#define YourVoteSoundFile "ui/vote_yes.wav"

bool conservative = false; //true if reverting back to vanilla behavior; this means RED applies the change
int item_id = 0; //the item to change
int attribute_id = 0; //the attribute to change
float attribute_value = 0.0; //the final attribute
int attribute_type = 0; //default

//TODO make a queue for future changes

public Plugin myinfo = {
	name = PLUGIN_NAME,
	author = PLUGIN_AUTHOR,
	description = PLUGIN_NAME,
	version = PLUGIN_VERSION,
	url = PLUGIN_CONTACT
};

public void OnPluginStart() {
	LoadTranslations("menu_mannco.phrases");
    
	RegServerCmd("mannco_reroll", CmdReroll);
	RegServerCmd("mannco_adminapply", CmdAdminApply);
	
	RegServerCmd("mannco_forcemod", CmdAppendModifier);
	
	RegConsoleCmd("sm_menutest", Menu_Mannco1);
	
	RegConsoleCmd("sm_what", CmdWhat);
	RegConsoleCmd("sm_specs", CmdSpecs);
	
	HookEvent("teamplay_round_start", Event_RoundStart, EventHookMode_Pre);
	HookEvent("teamplay_round_win", Event_RoundEnd, EventHookMode_Pre);
	
	LoadPreviousMods("configs/mannco-history.cfg");
}

Action CmdWhat(int client, int args) {
    
    char item_debug[64], attribute_debug[64];
    
    M_Item_GetDebugName(item_id, item_debug);
    M_Attrib_GetDebugName(attribute_id, attribute_debug);
    
    PrintToChat(client, "BLU is fighting for: %s %s %.3f", item_debug, attribute_debug, attribute_value);
	
	return Plugin_Handled;
    
}

Action CmdSpecs(int client, int args) {
    
    char arg1[64];
    
    if (args == 0) {
        PrintToChat(client, "Unknown weapon. Please put in a weapon.");
	    return Plugin_Handled;
    } else {
        GetCmdArg(1, arg1, sizeof(arg1));
        int itemId = ItemFromNameFragment(arg1);
        if (itemId == -1) {
            PrintToChat(client, "Unknown weapon. Please put in a valid weapon.");
	        return Plugin_Handled;
        }
        int attribute_dump[20];
        float value_dump[20];
        DumpAttributes(itemId, attribute_dump, value_dump, 20);
        int i;
        for (i = 0; i < 20; i++) {
            if (attribute_dump[i] == 0) break;
            char attrib_name[64];
            M_Attrib_GetDebugName(attribute_dump[i], attrib_name);
            PrintToConsole(client, "%s %.3f", attrib_name, value_dump[i]);
        }
        char item_name[64];
        M_Item_GetDebugName(itemId, item_name);
        if (i == 0) {
            PrintToChat(client, "%s is unmodified. For now.", item_name);
        } else {
            PrintToChat(client, "Modifications have been printed to console for: %s", item_name);
        }
    }
	
	return Plugin_Handled;
    
}

public void LoadPreviousMods(char filename[64]) {
    char buffer[256];
    char errorBuffer[64];
    char arguments[8][128];
    char action[128];
    char itemName[64];
    char attributeDesc[64];
    int item;
    int attribute;
    float value;
    int mode;
    BuildPath(Path_SM, buffer, sizeof(buffer), filename);
    File file = OpenFile(buffer, "r");
    int i = 0;
    while (file.ReadLine(buffer, 256)) {
        i++;
        ExplodeString(buffer, " ", arguments, 8, 128);
        action = arguments[0];
        item = StringToInt(arguments[1]);
        attribute = StringToInt(arguments[2]);
        value = StringToFloat(arguments[3]);
        mode = M_Attrib_GetDatatype(attribute);
        M_Item_GetDebugName(item, itemName);
        M_Attrib_GetDebugName(attribute, attributeDesc);
        
        errorBuffer = "";
        if (!ValidateItem(item, 0, true)) StrCat(errorBuffer, 64, "Bad item. ");
        else if (!ValidateAttribute(item, attribute, 0, true)) StrCat(errorBuffer, 64, "Bad attribute. ");
        else if (!ValidateValue(item, attribute, value, mode, 0, true)) StrCat(errorBuffer, 64, "Bad value. ");
                
        if (StrEqual(action, "force")) {
            ApplyItemModification(item, attribute, value, mode, "");
        } else if (StrEqual(action, "apply")) {
            if (errorBuffer[0] == '\0') {
                ApplyItemModification(item, attribute, value, mode, "");
            } else {
                PrintToServer("%d: PREVIOUS MOD REJECTED! %s%s (%d) %s (%d) %.3f", i, errorBuffer, itemName, item, attributeDesc, attribute, value);
            }
        } else if (StrEqual(action, "reject")) {
            if (errorBuffer[0] == '\0') {
                PrintToServer("%d: Test failed, accepted invalid mod. %s (%d) %s (%d) %.3f", i, itemName, item, attributeDesc, attribute, value);
            }
        } else if (StrEqual(action, "accept")) {
            if (errorBuffer[0] != '\0') {
                PrintToServer("%d: Test failed, rejected valid mod. %s%s (%d) %s (%d) %.3f", i, errorBuffer, itemName, item, attributeDesc, attribute, value);
            }
        } else if (StrEqual(action, "ignore")) {
            //nothing.
        } else if (StrEqual(action, "test")) {
            PrintToServer("%d: %sTest result: %s (%d) %s (%d) %.3f", i, errorBuffer, itemName, item, attributeDesc, attribute, value);
        } else {    //test and apply; this does everything at once, except force.
            if (errorBuffer[0] == '\0') {
                ApplyItemModification(item, attribute, value, mode, "");
                PrintToServer("%d: Accepted: %s (%d) %s (%d) %.3f", i, itemName, item, attributeDesc, attribute, value);
            } else {
                PrintToServer("%d: Rejected: %s%s (%d) %s (%d) %.3f", i, errorBuffer, itemName, item, attributeDesc, attribute, value);
            }
        }
    }
    file.Close();
}

public void OnMapStart()
{
    PrecacheSound(ItemPreservedSoundFile);
    PrecacheSound(ItemRevampedSoundFile);
}

public Action Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
	Reroll();
    return Plugin_Continue;
}

bool ValidateItem(int item, int attempts = 0, bool verbose = false) {
    bool passing;
    char slot[64];
    M_Item_GetSlot(item, slot);
    
    passing = (item == M_Item_GetParent(item) || attempts >= 10000);
    passing = passing && (M_Item_IsKnown(item) || attempts >= 1000);
    passing = passing && (!StrEqual(slot, "misc") || attempts >= 100);
    passing = passing && (!StrEqual(slot, "head") || attempts >= 100);
    return passing;
}

bool ValidateAttribute(int item, int attribute, int attempts = 0, bool verbose = false) {
    bool passing = true;
    passing = passing && (M_Attrib_IsKnown(attribute) || attempts >= 1000);
    passing = passing && (M_FlagsAgree(item, attribute) || attempts >= 10000);
    return passing;
}

bool ValidateValue(int item, int attribute, float value, int mode, int attempts = 0, bool verbose = false) {
    bool passing = true;
    float oldValue = QueryAttributeValue(item, attribute, attribute_type);
    float actualValue = QueryAttributeEffect(item, attribute, value, mode);
    float maxIncrease = M_Attrib_GetMaxIncrease(attribute);
    float maxDecrease = M_Attrib_GetMaxDecrease(attribute);
    float maxValue = M_Attrib_GetMaximum(attribute);
    float minValue = M_Attrib_GetMinimum(attribute);
    // if (!(value == 0 || attempts >= 10)) {
    //     passing = false;
    //     if (verbose) PrintToServer("Value %.3f exceeds the maximum interval %.3f.", value, maxIncrease);
    // }
    if (!(maxIncrease <= 0 || value <= maxIncrease || attempts >= 100)) {
        passing = false;
        if (verbose) PrintToServer("New value %.3f exceeds the maximum increase %.3f.", value, maxIncrease);
    }
    if (!(maxDecrease >= 0 || value >= maxDecrease || attempts >= 100)) {
        passing = false;
        if (verbose) PrintToServer("New value %.3f exceeds the maximum decrease %.3f.", value, maxIncrease);
    }
    if (!(actualValue != oldValue || attempts >= 100)) {
        passing = false;
        if (verbose) PrintToServer("Value %.3f results in value %.3f, the same as the old value (%.3f).", value, actualValue, oldValue);
    }
    if (!(actualValue <= maxValue || attempts >= 1000)) {
        passing = false;
        if (verbose) PrintToServer("Value %.3f results in value %.3f, exceeding the fixed maximum bound %.3f.", value, actualValue, maxValue);
    }
    if (!(actualValue >= minValue || attempts >= 1000)) {
        passing = false;
        if (verbose) PrintToServer("Value %.3f results in value %.3f, exceeding the fixed minimum bound %.3f.", value, actualValue, minValue);
    }
    return passing;
}


public void Reroll() {
    
    float prevValue;
    float newValue;
    
    do {
    	int attempts = 0;
    	do {
	        //1181 is the hot hand, use when performance issues are resolved
	        //30758 is the prinny machete, use this once skins can be distinguished
    	    item_id = GetURandomInt() % 300;
    	    item_id = M_Item_GetParent(item_id);
    	    attempts++;
    	} while (!ValidateItem(item_id, attempts)); //allow pure cosmetics to change VERY rarely.
    	
    	
    	attempts = 0;
    	do {
    	    attribute_id = GetURandomInt() % 2067;
    	    attribute_id = M_Attrib_GetParent(attribute_id);
    	    attempts++;
    	} while (!ValidateAttribute(item_id, attribute_id, attempts));
    	
    	attribute_type = M_Attrib_GetDatatype(attribute_id);
    	
    	if (attribute_type == -1) {
    	    attribute_value = 1.0; //always on
    	} else if (attribute_type == 1) {
    	    float interval = M_Attrib_GetInterval(attribute_id);
    	    attribute_value = interval * float(RoundToNearest(30.0 * (GetURandomFloat() - 0.5)));
    	} else if (attribute_type == 3) {
    	    attribute_value = RoundToNearest(100.0 * (GetURandomFloat() - 0.5)) / 100.0;
    	} else {
    	    attribute_value = RoundToNearest(100.0 * (GetURandomFloat() + 0.5)) / 100.0;
    	}
    	
    	float maxIncrease = M_Attrib_GetMaxIncrease(attribute_id);
    	if (maxIncrease >= 0 && attribute_value > maxIncrease) {
    	    attribute_value = maxIncrease;
    	}
    	
    	float maxDecrease = M_Attrib_GetMaxDecrease(attribute_id);
    	if (maxDecrease >= 0 && attribute_value > maxDecrease) {
    	    attribute_value = maxDecrease;
    	}
    	
    	if (attribute_type > 2) {
    	    attribute_type -= 2;
    	}
    	
    	attempts = 0;
    	float lastIteratedValue;
    	do {
    	    lastIteratedValue = attribute_value;
    	    newValue = QueryAttributeEffect(item_id, attribute_id, attribute_value, attribute_type);
        	//TODO this does nothing, it needs to affect the attribute_value, not the newValue.
        	float maxValue = M_Attrib_GetMaximum(attribute_id);
        	if (newValue > maxValue) {
        	    if (attribute_type == 2) attribute_value *= maxValue / newValue;
        	    else attribute_value += maxValue - newValue;
        	}
        	float minValue = M_Attrib_GetMinimum(attribute_id);
        	if (newValue < minValue) {
        	    if (attribute_type == 2) attribute_value *= minValue / newValue;
        	    else attribute_value += minValue - newValue;
        	}
        	attempts++;
    	} while (attribute_value != lastIteratedValue && attempts < 1);
    	
    	
    	prevValue = QueryAttributeValue(item_id, attribute_id, attribute_type);
    } while (prevValue == newValue);
	
    //TODO update the attribute sign to match what it ought for display purposes
    //TryAttributeFlip();
    
	char item_debug[64];
	M_Item_GetDebugName(item_id, item_debug);
	
	char attribute_debug[64];
	M_Attrib_GetDebugName(attribute_id, attribute_debug);
	
	PrintToChatAll("[ MannCo ] If BLU wins, the following item changes FOR GOOD:\n%s %s %.3f", item_debug, attribute_debug, attribute_value);
	PrintToServer("[ MannCo ] Mod: %s (%d) %s (%d) %.3f", item_debug, item_id, attribute_debug, attribute_id, attribute_value);
}

public Action Event_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
    //char winnerDisplay[12] = "Winner:";
    //char buffer[12];
    //IntToString(event.GetInt("team"), buffer, 12);
    //StrCat(winnerDisplay, 12, buffer);
	//PrintToServer(winnerDisplay);
	
    if (!conservative ^ (event.GetInt("team") == 2)) //2 is RED. Unless red wins or the match was conservative, do nothing.
    {
        CreateTimer(8.0, ConfirmMod);
		ApplyItemModification(item_id, attribute_id, attribute_value, attribute_type, "apply");
    } else {
		CreateTimer(8.0, ConfirmDefense);
	}
    return Plugin_Continue;
}

public Action ConfirmDefense(Handle timer)
{
	PrintToChatAll("[ MannCo ] Item defended! Well done, RED!");
    EmitSoundToAll(ItemPreservedSoundFile, SOUND_FROM_PLAYER, SNDCHAN_AUTO, SNDLEVEL_NORMAL * 2, SND_NOFLAGS, SNDVOL_NORMAL, SNDPITCH_NORMAL, -1, NULL_VECTOR, NULL_VECTOR, true, 0.0);
}

public Action ConfirmMod(Handle timer)
{
	PrintToChatAll("[ MannCo ] Item revamped! Well done, BLU!");
    EmitSoundToAll(ItemRevampedSoundFile, SOUND_FROM_PLAYER, SNDCHAN_AUTO, SNDLEVEL_NORMAL * 2, SND_NOFLAGS, SNDVOL_NORMAL, SNDPITCH_NORMAL, -1, NULL_VECTOR, NULL_VECTOR, true, 0.0);
}

public int MenuHandler1(Menu menu, MenuAction action, int param1, int param2)
{
  switch(action)
  {
    case MenuAction_Start:
    {
      PrintToServer("Displaying menu");
    }
 
    case MenuAction_Display:
    {
      char buffer[255];
      Format(buffer, sizeof(buffer), "%T", "Vote Nextmap", param1);
 
      Panel panel = view_as<Panel>(param2);
      panel.SetTitle(buffer);
      PrintToServer("Client %d was sent menu with panel %x", param1, param2);
    }
 
    case MenuAction_Select:
    {
      char info[32];
      menu.GetItem(param2, info, sizeof(info));
      if (StrEqual(info, CHOICE3))
      {
        PrintToServer("Client %d somehow selected %s despite it being disabled", param1, info);
      }
      else
      {
        PrintToServer("Client %d selected %s", param1, info);
      }
    }
 
    case MenuAction_Cancel:
    {
      PrintToServer("Client %d's menu was cancelled for reason %d", param1, param2);
    }
 
    case MenuAction_End:
    {
      delete menu;
    }
 
    case MenuAction_DrawItem:
    {
      int style;
      char info[32];
      menu.GetItem(param2, info, sizeof(info), style);
 
      if (StrEqual(info, CHOICE3))
      {
        return ITEMDRAW_DISABLED;
      }
      else
      {
        return style;
      }
    }
 
    case MenuAction_DisplayItem:
    {
      char info[32];
      menu.GetItem(param2, info, sizeof(info));
 
      char display[64];
 
      if (StrEqual(info, CHOICE3))
      {
        Format(display, sizeof(display), "%T", "Choice 3", param1);
        return RedrawMenuItem(display);
      }
    }
  }
 
  return 0;
}

public Action Menu_Mannco1(int client, int args)
{
  Menu menu = new Menu(MenuHandler1, MENU_ACTIONS_ALL);
  menu.SetTitle("%T", "Menu Title", LANG_SERVER);
  menu.AddItem(CHOICE1, "Choice 1");
  menu.AddItem(CHOICE2, "Choice 2");
  menu.AddItem(CHOICE3, "Choice 3");
  menu.ExitButton = false;
  menu.Display(client, 20);
 
  return Plugin_Handled;
}

public Action CmdAdminApply(int args) {
	
	ApplyItemModification(item_id, attribute_id, attribute_value, attribute_type, "nag_admin_applied");
	Reroll();
	
	return Plugin_Handled;
	
}

public Action CmdReroll(int args) {
	
	Reroll();
	
	return Plugin_Handled;
	
}

public Action CmdAppendModifier(int args) {
	
	// Load the next 4 strings as arguments (the item, the attribute and the modifier; also the mode)
	char arg1[32], arg2[32], arg3[32], arg4[32];
    
    GetCmdArg(1, arg1, sizeof(arg1));
    GetCmdArg(2, arg2, sizeof(arg2));
    GetCmdArg(3, arg3, sizeof(arg3));
    GetCmdArg(4, arg4, sizeof(arg4));
	
	// Fire a message telling about the operation.
    LogMessage("Appending change");
	
	int item = StringToInt(arg1);
	int attribute = StringToInt(arg2);
	float modifier = StringToFloat(arg3);
	int mode = StringToInt(arg4);
	
	// Call the ApplyItemModification function.
	ApplyItemModification(item, attribute, modifier, mode, "nag_forced");
	return Plugin_Handled;
	
	
}