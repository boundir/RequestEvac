//-----------------------------------------------------------
// Used by the visualizer system to control a Visualization Actor
//-----------------------------------------------------------
class X2Action_RequestEvac extends X2Action	config(GameCore);

var XComGameStateContext_Ability AbilityContext;
var XGUnit UnitWhoRequestedEvac;

function Init()
{
	super.Init();

	AbilityContext = XComGameStateContext_Ability(StateChangeContext);
	if (AbilityContext != None)
	{
		UnitWhoRequestedEvac = XGUnit(`XCOMHISTORY.GetGameStateForObjectID(AbilityContext.InputContext.SourceObject.ObjectID).GetVisualizer());
	}
}

simulated state Executing
{

Begin:

	if (`SYNC_RAND(100)<10)
	{
		UnitWhoRequestedEvac.UnitSpeak('MissionAbortRequest');
	}
	else
	{
		UnitWhoRequestedEvac.UnitSpeak('EVACrequest');
	}
	Sleep(2.0f); // to let the Soldier speak then Firebrand can answer the call.

	CompleteAction();
}


