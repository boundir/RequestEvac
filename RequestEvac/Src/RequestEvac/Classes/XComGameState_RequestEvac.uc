class XComGameState_RequestEvac extends XComGameState_Item config(RequestEvac);

var private localized string strEvacRequestTitle;
var private localized string strEvacRequestSubtitle;
var private localized string strRemoveEvacTitle;
var private localized string strRemoveEvacSubtitle;

// Extends XCGS_Item as a hack so we get access to X2VisualizedInterface functions.

// var config bool DisplayFlareBeforeEvacSpawn;
var config int TurnsBeforeEvacExpires;
var privatewrite int Countdown;
var privatewrite int RemoveEvacCountdown;
var privatewrite vector EvacLocation;

// Entry point: create a delayed evac zone instance with the given countdown and position.
// or generate countdown and position if they're not given.
static final function XComGameState_RequestEvac InitiateEvacZoneDeployment(XComGameState NewGameState, optional const vector OverrideDeploymentLocation, optional const int OverrideInitialDelay = -1)
{
	local XComGameState_RequestEvac NewEvacSpawnerState;
	local vector DeploymentLocation;
	local vector EmptyVector;
	local int InitialCountdown;

	`RELOG("Running with parameters:" @ `ShowVar(OverrideDeploymentLocation) @ `ShowVar(OverrideInitialDelay));

	if (OverrideDeploymentLocation != EmptyVector)
	{
		DeploymentLocation = OverrideDeploymentLocation;
	}
	else
	{
		DeploymentLocation = class'X2Ability_RequestEvac'.static.GenerateEvacLocation();
	}

	if (OverrideInitialDelay != -1)
	{
		InitialCountdown = OverrideInitialDelay;
	}
	else
	{
		InitialCountdown = class'X2Ability_RequestEvac'.static.GenerateEvacDelay();
	}

	NewEvacSpawnerState = XComGameState_RequestEvac(`XCOMHISTORY.GetSingleGameStateObjectForClass(class'XComGameState_RequestEvac', true));
	if (NewEvacSpawnerState != none && !NewEvacSpawnerState.bRemoved)
	{
		`RELOG("Found existing state object for the Evac State" @ NewEvacSpawnerState.ObjectID @ NewEvacSpawnerState.bRemoved);
		NewEvacSpawnerState = XComGameState_RequestEvac(NewGameState.ModifyStateObject(class'XComGameState_RequestEvac', NewEvacSpawnerState.ObjectID));
	}
	else
	{
		NewEvacSpawnerState = XComGameState_RequestEvac(NewGameState.CreateNewStateObject(class'XComGameState_RequestEvac'));
		`RELOG("Creating new state object for the Evac State" @ NewEvacSpawnerState.ObjectID);
	}

	NewEvacSpawnerState.EvacLocation = DeploymentLocation;
	NewEvacSpawnerState.RegisterForEvents();

	`RELOG("Final parameters:" @ `ShowVar(DeploymentLocation) @ `ShowVar(InitialCountdown));

	// no countdown specified, spawn the evac zone immediately.
	if (InitialCountdown == 0)
	{
		NewEvacSpawnerState.SpawnEvacZone(NewGameState);
	}
	else
	{
		NewEvacSpawnerState.Countdown = InitialCountdown;
		NewEvacSpawnerState.RemoveEvacCountdown = -1;
	}

	// Let others know we've requested an evac.
	`XEVENTMGR.TriggerEvent('EvacSpawnerCreated', NewEvacSpawnerState, NewEvacSpawnerState, NewGameState);
	`XEVENTMGR.TriggerEvent('EvacRequested', NewEvacSpawnerState, NewEvacSpawnerState, NewGameState);

	return NewEvacSpawnerState;
}

// Countdown complete: time to spawn the evac zone.
final function SpawnEvacZone(XComGameState NewGameState)
{
	local Object ThisObj;

	// Place the evac zone on the map.
	// This will also enable the Evac ability.
	class'XComGameState_EvacZone'.static.PlaceEvacZone(NewGameState, EvacLocation, eTeam_XCom);

	ThisObj = self;
	`XEVENTMGR.TriggerEvent('SpawnEvacZoneComplete', ThisObj, ThisObj, NewGameState);

	ResetCountdown();
	InitRemoveEvacCountdown();
}

// Evac zone has expired, time for Skyranger to leave.
private function RemoveEvacZone(XComGameState NewGameState)
{
    local XComGameState_EvacZone EvacZone;

	`RELOG(GetFuncName() @ "Running");

	UnregisterFromAllEvents();

	// Disable the evac ability
    class'XComGameState_BattleData'.static.SetGlobalAbilityEnabled('Evac', false, NewGameState);

	EvacZone = class'XComGameState_EvacZone'.static.GetEvacZone();
    if (EvacZone == none)
        return;

	`RELOG(GetFuncName() @ "Found existing evac zone, removing");

    // Remove the evac zone state
    NewGameState.RemoveStateObject(EvacZone.ObjectID);
}

// --------------------------------------------------------------------------------------------------------------
// Event handling

private function RegisterForEvents()
{
	local X2EventManager EventManager;
	local Object ThisObj;

	EventManager = `XEVENTMGR;
	ThisObj = self;	

	`RELOG("Request Evac State Object registering for events:" @ self.ObjectID);

	EventManager.RegisterForEvent(ThisObj, 'PlayerTurnBegun', OnPlayerTurnBegun, ELD_OnStateSubmitted,,);
	EventManager.RegisterForEvent(ThisObj, 'TileDataChanged', OnTileDataChanged, ELD_OnStateSubmitted,,);
	EventManager.RegisterForEvent(ThisObj, 'EvacZoneDestroyed', OnEvacZoneDestroyed, ELD_OnStateSubmitted,,);

	// As this handler updates the UI, don't do it on the game state thread but within a visualization block instead.
	EventManager.RegisterForEvent(ThisObj, 'EvacRequested', OnUpdateTimerEvent, ELD_OnVisualizationBlockStarted,,);
	EventManager.RegisterForEvent(ThisObj, 'PlayerTurnBegun', OnUpdateTimerEvent, ELD_OnVisualizationBlockStarted,,);
}

function OnEndTacticalPlay(XComGameState NewGameState)
{
	UnregisterFromAllEvents();
}

private function UnregisterFromAllEvents()
{
	local X2EventManager EventManager;
	local Object ThisObj;

	EventManager = `XEVENTMGR;
	ThisObj = self;

	`RELOG("Request Evac State Object unregistering from all events:" @ self.ObjectID);

	EventManager.UnRegisterFromEvent(ThisObj, 'PlayerTurnBegun');
	EventManager.UnRegisterFromEvent(ThisObj, 'TileDataChanged');
	EventManager.UnRegisterFromEvent(ThisObj, 'EvacZoneDestroyed');
	EventManager.UnRegisterFromEvent(ThisObj, 'EvacRequested');
	EventManager.UnRegisterFromEvent(ThisObj, 'PlayerTurnBegun');
}


// --------------------------------------------------------------------------------------------------------------
// Main Timer until Skyranger arrives and then until it leaves.

// Called when the player's turn has begun. Check if we have an active evac zone placement state with a countdown. If so, display it.
private function EventListenerReturn OnPlayerTurnBegun(Object EventData, Object EventSource, XComGameState GameState, Name EventID, Object CallbackData)
{
	local XComGameState_Player			PlayerState;
	local XComGameState_RequestEvac		NewEvacState;
	local XComGameState					NewGameState;

	// `RELOG("DEBUG : OnTurnBegun", , 'RequestEvac');
	// `RELOG("DEBUG : OnTurnBegun GetCountdown" @ EvacState.GetCountdown(), , 'RequestEvac');
	// `RELOG("DEBUG : OnTurnBegun GetRemoveEvacCountdown" @ EvacState.GetRemoveEvacCountdown(), , 'RequestEvac');

	PlayerState = XComGameState_Player(EventData);
	if (PlayerState == none || PlayerState.GetTeam() != eTeam_XCom)
		return ELR_NoInterrupt;

	// If Evac Zone is already spawned, tick its timer, and remove it if it's time to do so.
	if (GetRemoveEvacCountdown() > 0)
	{
		// Decrement the counter
		NewGameState = class'XComGameStateContext_ChangeContainer'.static.CreateChangeState("UpdateRemoveEvacCountdown");
		NewEvacState = XComGameState_RequestEvac(NewGameState.ModifyStateObject(self.Class, self.ObjectID));
		NewEvacState.SetRemoveEvacCountdown(GetRemoveEvacCountdown() - 1);
		
		// We've hit zero: time to delete the evac zone!
		if (NewEvacState.GetRemoveEvacCountdown() == 0)
		{
			NewEvacState.ResetRemoveEvacCountdown();
			NewEvacState.RemoveEvacZone(NewGameState);
			XComGameStateContext_ChangeContainer(NewGameState.GetContext()).BuildVisualizationFn = RemoveEvacZone_BuildVisualization;

			// Remove the Evac State oject too, since it serves no purpose at this point.

			`RELOG("Removing Request Evac State object:" @ self.ObjectID);
			NewGameState.RemoveStateObject(self.ObjectID);
		}

		`TACTICALRULES.SubmitGameState(NewGameState);

		return ELR_NoInterrupt;
	}
	else if (GetCountdown() > 0) // If Evac Flare is up, tick its timer, and spawn the Evac Zone, if it's time.
	{
		// Decrement the counter
		NewGameState = class'XComGameStateContext_ChangeContainer'.static.CreateChangeState("UpdateEvacCountdown");
		NewEvacState = XComGameState_RequestEvac(NewGameState.ModifyStateObject(self.Class, self.ObjectID));
		NewEvacState.SetCountdown(GetCountdown() - 1);

		// We've hit zero: time to spawn the evac zone!
		if (NewEvacState.GetCountdown() == 0)
		{
			NewEvacState.SpawnEvacZone(NewGameState);
			XComGameStateContext_ChangeContainer(NewGameState.GetContext()).BuildVisualizationFn = SpawnEvacZone_BuildVisualization;
		}

		`TACTICALRULES.SubmitGameState(NewGameState);
	}

	return ELR_NoInterrupt;
}

// Visualize the evac spawn: turn off the flare we dropped as a countdown visualizer and visualize the evac zone dropping.
private function SpawnEvacZone_BuildVisualization(XComGameState VisualizeGameState)
{
	local XComGameState_EvacZone		EvacZone;
	local VisualizationActionMetadata	ActionMetadata;
	local VisualizationActionMetadata	EmptyTrack;
	local X2Action_PlayEffect			EvacSpawnerEffectAction;
	local X2Action_PlayNarrative		NarrativeAction;
	local X2Action_RevealArea			RevealAreaAction;

	// First, get rid of our old visualization from the delayed spawn.
	ActionMetadata.StateObject_OldState = self;
	ActionMetadata.StateObject_NewState = self;

	EvacSpawnerEffectAction = X2Action_PlayEffect(class'X2Action_PlayEffect'.static.AddToVisualizationTree(ActionMetadata, VisualizeGameState.GetContext(), false, ActionMetadata.LastActionAdded));
	EvacSpawnerEffectAction.EffectName = "BDRequestEvac.P_EvacZone_Flare";
	EvacSpawnerEffectAction.EffectLocation = GetLocation();
	EvacSpawnerEffectAction.bStopEffect = true;
	EvacSpawnerEffectAction.bWaitForCompletion = false;
	EvacSpawnerEffectAction.bWaitForCameraCompletion = false;

	// Now add the new visualization for the evac zone placement.
	foreach VisualizeGameState.IterateByClassType(class'XComGameState_EvacZone', EvacZone)
	{
		ActionMetadata = EmptyTrack;
		ActionMetadata.StateObject_OldState = EvacZone;
		ActionMetadata.StateObject_NewState = EvacZone;
		ActionMetadata.VisualizeActor = EvacZone.GetVisualizer();

		RevealAreaAction = X2Action_RevealArea(class'X2Action_RevealArea'.static.AddToVisualizationTree(ActionMetadata, VisualizeGameState.GetContext()));
		RevealAreaAction.ScanningRadius = class'XComWorldData'.const.WORLD_StepSize * 5.0f;
		RevealAreaAction.TargetLocation = GetLocation();
		RevealAreaAction.bDestroyViewer = false;
		RevealAreaAction.AssociatedObjectID = EvacZone.ObjectID;

		class'X2Action_PlaceEvacZone'.static.AddToVisualizationTree(ActionMetadata, VisualizeGameState.GetContext(), false, ActionMetadata.LastActionAdded);
	
		NarrativeAction = X2Action_PlayNarrative(class'X2Action_PlayNarrative'.static.AddToVisualizationTree(ActionMetadata, VisualizeGameState.GetContext(), false, ActionMetadata.LastActionAdded));
		NarrativeAction.Moment = XComNarrativeMoment(`CONTENT.RequestGameArchetype("BDRequestEvac.Firebrand_Arrived"));
		NarrativeAction.WaitForCompletion = false;

		break;
	}
}

private function RemoveEvacZone_BuildVisualization(XComGameState VisualizeGameState)
{
	local VisualizationActionMetadata	ActionMetadata;
	local XComGameState_EvacZone		EvacZone;

	`RELOG(GetFuncName() @ "Running");

	foreach VisualizeGameState.IterateByClassType(class'XComGameState_EvacZone', EvacZone)
	{
		ActionMetadata.StateObject_OldState = EvacZone;
		ActionMetadata.StateObject_NewState = EvacZone;
		ActionMetadata.VisualizeActor = `XCOMHISTORY.GetVisualizer(EvacZone.ObjectID);
	
		`RELOG(GetFuncName() @ "It was removed:" @ ActionMetadata.StateObject_OldState.bRemoved);
		`RELOG(GetFuncName() @ "It is  removed:" @ ActionMetadata.StateObject_NewState.bRemoved);
		`RELOG(GetFuncName() @ "Found visualizer:" @ ActionMetadata.VisualizeActor != none);

		class'X2Action_DestroyActor'.static.AddToVisualizationTree(ActionMetadata, VisualizeGameState.GetContext());
		class'X2Action_UpdateEvacTimer'.static.AddToVisualizationTree(ActionMetadata, VisualizeGameState.GetContext());
		break;
	}
}

// --------------------------------------------------------------------------------------------------------------
// Handle floors under the evac flare being destroyed before Skyranger arrives.

private function EventListenerReturn OnTileDataChanged(Object EventData, Object EventSource, XComGameState GameState, Name EventID, Object CallbackData)
{
	local XComGameState_RequestEvac	NewEvacState;
	local XComGameState				NewGameState;
	local TTile						CenterTile;

	// If evac doesn't have an active timer, there isn't anything to do.
	if (GetCountdown() < 1)
		return ELR_NoInterrupt;

	CenterTile = GetCenterTile();
	if (!class'X2TargetingMethod_EvacZone'.static.ValidateEvacArea(CenterTile, false))
	{
		`RELOG("Evac location is no longer valid.");

		// Destroy the old flare, find a new location for the evac zone and spawn a flare there.

		NewGameState = class'XComGameStateContext_ChangeContainer'.static.CreateChangeState("Respawning Evac Flare");
		NewEvacState = XComGameState_RequestEvac(NewGameState.ModifyStateObject(self.Class, self.ObjectID));
		`XEVENTMGR.TriggerEvent('EvacSpawnerDestroyed', NewEvacState, NewEvacState, NewGameState);

		class'XComGameState_RequestEvac'.static.InitiateEvacZoneDeployment(NewGameState,, GetCountdown());
		XComGameStateContext_ChangeContainer(NewGameState.GetContext()).BuildVisualizationFn = RespawnFlare_BuildVisualization;

		`RELOG("Moving Evac Flare from:" @ GetLocation() @ "to:" @ NewEvacState.GetLocation());

		`TACTICALRULES.SubmitGameState(NewGameState);
	}

	return ELR_NoInterrupt;
}

static private function RespawnFlare_BuildVisualization(XComGameState VisualizeGameState)
{
	local X2Action_PlayEffect			FlareEffectAction;
	local VisualizationActionMetadata	ActionMetadata;
	local X2Action_PlayNarrative		NarrativeAction;
	local XComGameState_RequestEvac		NewEvacState;
	local XComGameState_RequestEvac		OldEvacState;

	foreach VisualizeGameState.IterateByClassType(class'XComGameState_RequestEvac', NewEvacState)
	{
		OldEvacState = XComGameState_RequestEvac(`XCOMHISTORY.GetGameStateForObjectID(NewEvacState.ObjectID,, VisualizeGameState.HistoryIndex - 1));
		if (OldEvacState == none)
			continue;

		`RELOG("Running - moving Evac Flare from:" @ OldEvacState.GetLocation() @ "to:" @ NewEvacState.GetLocation());

		ActionMetadata.StateObject_OldState = OldEvacState;
		ActionMetadata.StateObject_NewState = NewEvacState;

		FlareEffectAction = X2Action_PlayEffect(class'X2Action_PlayEffect'.static.AddToVisualizationTree(ActionMetadata, VisualizeGameState.GetContext()));
		FlareEffectAction.EffectName = "BDRequestEvac.P_EvacZone_Flare";
		FlareEffectAction.EffectLocation = OldEvacState.GetLocation();
		FlareEffectAction.bStopEffect = true;
		FlareEffectAction.bWaitForCompletion = false;
		FlareEffectAction.bWaitForCameraCompletion = false;

		NarrativeAction = X2Action_PlayNarrative(class'X2Action_PlayNarrative'.static.AddToVisualizationTree(ActionMetadata, VisualizeGameState.GetContext(), false, ActionMetadata.LastActionAdded));
		if (Frand() > 0.5)
		{
			NarrativeAction.Moment = XComNarrativeMoment(`CONTENT.RequestGameArchetype("X2NarrativeMoments.TACTICAL.Extract.Central_Extract_VIP_Evac_Destroyed"));
		}
		else
		{
			NarrativeAction.Moment = XComNarrativeMoment(`CONTENT.RequestGameArchetype("X2NarrativeMoments.TACTICAL.RescueVIP.Central_Rescue_VIP_EvacDestroyed"));
		}
		NarrativeAction.WaitForCompletion = true;

		FlareEffectAction = X2Action_PlayEffect(class'X2Action_PlayEffect'.static.AddToVisualizationTree(ActionMetadata, VisualizeGameState.GetContext(), false, ActionMetadata.LastActionAdded));
		FlareEffectAction.EffectName = "BDRequestEvac.P_EvacZone_Flare";
		FlareEffectAction.EffectLocation = NewEvacState.GetLocation();
		FlareEffectAction.bStopEffect = false;
		FlareEffectAction.bWaitForCameraCompletion = true;
		FlareEffectAction.CenterCameraOnEffectDuration = 2.0f; // Hold camera on the new evac flare for a couple seconds.

		break;
	}
}

// --------------------------------------------------------------------------------------------------------------
// Handle evac zone itself being destroyed

private function EventListenerReturn OnEvacZoneDestroyed(Object EventData, Object EventSource, XComGameState GameState, Name EventID, Object CallbackData)
{
	local XComGameState_EvacZone	EvacZone;
	local XComGameState_RequestEvac NewEvacState;
	local XComGameState				NewGameState;

	`RELOG("Running");

	EvacZone = XComGameState_EvacZone(EventData);
	if (EvacZone == none || EvacZone.Team != eTeam_XCom)
		return ELR_NoInterrupt;

	`RELOG("EvacZone is removed:" @ EvacZone.bRemoved @ "Remaining countdown:" @ GetRemoveEvacCountdown());

	// If no evac or it doesn't have an active timer, there isn't anything to do.
	if (GetRemoveEvacCountdown() < 1)
		return ELR_NoInterrupt;

	NewGameState = class'XComGameStateContext_ChangeContainer'.static.CreateChangeState("Recreating Evac Zone");
	class'XComGameState_RequestEvac'.static.InitiateEvacZoneDeployment(NewGameState,, 0);
	NewEvacState = XComGameState_RequestEvac(NewGameState.GetGameStateForObjectID(self.ObjectID));
	NewEvacState.SetRemoveEvacCountdown(GetRemoveEvacCountdown());
	XComGameStateContext_ChangeContainer(NewGameState.GetContext()).BuildVisualizationFn = RespawnEvac_BuildVisualization;

	`RELOG("Moving Evac Zone from:" @ GetLocation() @ "to:" @ NewEvacState.GetLocation());

	`TACTICALRULES.SubmitGameState(NewGameState);

	return ELR_NoInterrupt;
}
private function RespawnEvac_BuildVisualization(XComGameState VisualizeGameState)
{
	local XComGameState_EvacZone		EvacZone;
	local VisualizationActionMetadata	ActionMetadata;
	local X2Action_PlayNarrative		NarrativeAction;
	local X2Action_RevealArea			RevealAreaAction;

	// Add visualization for the evac zone placement.
	foreach VisualizeGameState.IterateByClassType(class'XComGameState_EvacZone', EvacZone)
	{
		ActionMetadata.StateObject_OldState = EvacZone;
		ActionMetadata.StateObject_NewState = EvacZone;
		ActionMetadata.VisualizeActor = EvacZone.GetVisualizer();

		RevealAreaAction = X2Action_RevealArea(class'X2Action_RevealArea'.static.AddToVisualizationTree(ActionMetadata, VisualizeGameState.GetContext()));
		RevealAreaAction.bDestroyViewer = true;
		RevealAreaAction.AssociatedObjectID = EvacZone.ObjectID;

		NarrativeAction = X2Action_PlayNarrative(class'X2Action_PlayNarrative'.static.AddToVisualizationTree(ActionMetadata, VisualizeGameState.GetContext(), false, ActionMetadata.LastActionAdded));
		if (Frand() > 0.5)
		{
			NarrativeAction.Moment = XComNarrativeMoment(`CONTENT.RequestGameArchetype("X2NarrativeMoments.TACTICAL.Extract.Central_Extract_VIP_Evac_Destroyed"));
		}
		else
		{
			NarrativeAction.Moment = XComNarrativeMoment(`CONTENT.RequestGameArchetype("X2NarrativeMoments.TACTICAL.RescueVIP.Central_Rescue_VIP_EvacDestroyed"));
		}
		NarrativeAction.WaitForCompletion = true;

		class'X2Action_PlaceEvacZone'.static.AddToVisualizationTree(ActionMetadata, VisualizeGameState.GetContext(), false, ActionMetadata.LastActionAdded);
	
		RevealAreaAction = X2Action_RevealArea(class'X2Action_RevealArea'.static.AddToVisualizationTree(ActionMetadata, VisualizeGameState.GetContext()));
		RevealAreaAction.ScanningRadius = class'XComWorldData'.const.WORLD_StepSize * 5.0f;
		RevealAreaAction.TargetLocation = GetLocation();
		RevealAreaAction.bDestroyViewer = false;
		RevealAreaAction.AssociatedObjectID = EvacZone.ObjectID;

		break;
	}
}

// --------------------------------------------------------------------------------------------------------------
// Visually updated evac countdown timer

private function EventListenerReturn OnUpdateTimerEvent(Object EventData, Object EventSource, XComGameState GameState, Name EventID, Object CallbackData)
{
	UpdateEvacTimer();

	return ELR_NoInterrupt;
}

// Update/refresh the evac timer.
final function UpdateEvacTimer()
{
	local UISpecialMissionHUD SpecialMissionHUD;

	SpecialMissionHUD = `PRES.GetSpecialMissionHUD();
	if (SpecialMissionHUD == none)
		return;

	// `RELOG("DEBUG : UpdateEvacTimer", , 'RequestEvac');

	// Update the UI
	if (GetCountdown() > 0)
	{
		SpecialMissionHUD.m_kTurnCounter2.SetUIState(eUIState_Normal);
		SpecialMissionHUD.m_kTurnCounter2.SetLabel(default.strEvacRequestTitle);
		SpecialMissionHUD.m_kTurnCounter2.SetSubLabel(default.strEvacRequestSubtitle);
		SpecialMissionHUD.m_kTurnCounter2.SetCounter(string(GetCountdown()));
	}
	else if(GetRemoveEvacCountdown() > 0)
	{
		SpecialMissionHUD.m_kTurnCounter2.SetUIState(eUIState_Normal);
		SpecialMissionHUD.m_kTurnCounter2.SetLabel(default.strRemoveEvacTitle);
		SpecialMissionHUD.m_kTurnCounter2.SetSubLabel(default.strRemoveEvacSubtitle);
		SpecialMissionHUD.m_kTurnCounter2.SetCounter(string(GetRemoveEvacCountdown()));
	}
	else
	{
		SpecialMissionHUD.m_kTurnCounter2.Hide();
	}
}


// --------------------------------------------------------------------------------------------------------------
// Getters, Setters, Resetters

// Countdown Getters

function int GetCountdown()
{
	return Countdown;
}
function int GetRemoveEvacCountdown()
{
	return RemoveEvacCountdown;
}


// Countdown Setters

function SetCountdown(int NewCountdown)
{
	Countdown = NewCountdown;
}
function SetRemoveEvacCountdown(int NewCountdown)
{
	RemoveEvacCountdown = NewCountdown;
}


// Countdown Resetters

function InitRemoveEvacCountdown()
{
	// `RELOG("DEBUG : InitRemoveEvacCountdown" @ default.TurnsBeforeEvacExpires, , 'RequestEvac');
	RemoveEvacCountdown = default.TurnsBeforeEvacExpires;
}
function ResetCountdown()
{
	// Clear the countdown (effectively disable the spawner)
	Countdown = -1;
}
function ResetRemoveEvacCountdown()
{
	// Clear the countdown (effectively disable the spawner)
	RemoveEvacCountdown = -1;
}


// Location Getters

function vector GetLocation()
{
	return EvacLocation;
}

function TTile GetCenterTile()
{
	return `XWORLD.GetTileCoordinatesFromPosition(EvacLocation);
}


// --------------------------------------------------------------------------------------------------------------
// Override functions inherited from X2VisualizedInterface
// These run when loading a save.

function SyncVisualizer(optional XComGameState GameState = none) {}

// If the save was made while the player is waiting for evac to arrive, respawn a flare particle effect on the evac location.
// Else if save was made after evac has already arriver, respawn the squad viewer to keep the evac zone revealed.
function AppendAdditionalSyncActions( out VisualizationActionMetadata ActionMetadata, const XComGameStateContext Context)
{
	local X2Action_PlayEffect		PlayEffect;
	local X2Action_RevealArea		RevealAreaAction;
	local XComGameState_EvacZone	EvacZone;

	if (ActionMetadata.StateObject_NewState.bRemoved)
		return;

	`RELOG(GetFuncName() @ "Running");

	if (GetCountdown() > 0)
	{
		PlayEffect = X2Action_PlayEffect(class'X2Action_PlayEffect'.static.AddToVisualizationTree(ActionMetadata, Context, false, ActionMetadata.LastActionAdded));

		PlayEffect.EffectName = "BDRequestEvac.P_EvacZone_Flare";
		PlayEffect.EffectLocation = GetLocation();
		PlayEffect.CenterCameraOnEffectDuration = 0;
		PlayEffect.bStopEffect = false;

		`RELOG("Spawning flare on save load:" @ GetCountdown() @ GetLocation() @ ActionMetadata.StateObject_NewState.bRemoved @ ObjectID);
	}
	else if (GetRemoveEvacCountdown() > 0)
	{
		EvacZone = class'XComGameState_EvacZone'.static.GetEvacZone();
		if (EvacZone != none)
		{
			RevealAreaAction = X2Action_RevealArea(class'X2Action_RevealArea'.static.AddToVisualizationTree(ActionMetadata, Context, false, ActionMetadata.LastActionAdded));
			RevealAreaAction.ScanningRadius = class'XComWorldData'.const.WORLD_StepSize * 5.0f;
			RevealAreaAction.TargetLocation = GetLocation();
			RevealAreaAction.bDestroyViewer = false;
			RevealAreaAction.AssociatedObjectID = EvacZone.ObjectID;
		}
	}

	UpdateEvacTimer();
}

// --------------------------------------------------------------------------------------------------------------
// Override functions inherited from XCGS_Item we're not gonna use.

event RequestResources(out array<string> ArchetypesToLoad) {}
event OnCreation(optional X2DataTemplate Template) {}
function OnBeginTacticalPlay(XComGameState NewGameState) {}
protected function RegisterForCosmeticUnitEvents(XComGameState NewGameState) {}
//function OnEndTacticalPlay(XComGameState NewGameState) {}
function CreateCosmeticItemUnit(XComGameState NewGameState) {}
simulated function bool HasBeenModified() { return false; }
simulated function bool IsStartingItem() { return false; }
simulated function Object GetGameArchetype(optional bool bAlt = false) { return none; }
simulated function array<WeaponAttachment> GetWeaponAttachments(optional bool bGetContent=true)
{
	local array<WeaponAttachment> DummyArray;
	DummyArray.Length = 0;
	return DummyArray;
}
simulated function int GetClipSize() { return 0; }
simulated function bool HasInfiniteAmmo() { return false; }
simulated function int GetItemSize() { return 0; }
simulated function int GetItemRange(const XComGameState_Ability AbilityState) { return 0; }
simulated function GetBaseWeaponDamageValue(XComGameState_BaseObject TargetObjectState, out WeaponDamageValue DamageValue) {} 
simulated function GetWeaponDamageValue(XComGameState_BaseObject TargetObjectState, name Tag, out WeaponDamageValue DamageValue) {}
simulated function int GetItemEnvironmentDamage() { return 0; }
simulated function int GetItemSoundRange() { return 0; }
simulated function int GetItemClipSize() { return 0; }
simulated function int GetItemAimModifier() { return 0; }
simulated function int GetItemCritChance() { return 0; }
simulated function int GetItemPierceValue() { return 0; }
simulated function int GetItemRuptureValue() { return 0; }
simulated function int GetItemShredValue() { return 0; }
simulated function bool SoundOriginatesFromOwnerLocation() { return false; }
simulated function bool CanWeaponBeDodged() { return false; }
simulated function name GetWeaponCategory() { return ''; }
simulated function name GetWeaponTech() { return ''; }
simulated function array<string> GetWeaponPanelImages()
{
	local array<string> DummyArray; 
	DummyArray.Length = 0;
	return DummyArray;
}
function String GenerateNickname() { return ""; }
simulated function bool AllowsHeavyWeapon() { return false; }
simulated function EUISummary_WeaponStats GetWeaponStatsForUI()
{
	local EUISummary_WeaponStats Summary; 
	return Summary;
}
simulated function array<EUISummary_WeaponUpgrade> GetWeaponUpgradesForTooltipUI()
{
	local array<EUISummary_WeaponUpgrade> DummyArray; 
	DummyArray.Length = 0;
	return DummyArray;
}
simulated function string GetUpgradeEffectForUI(X2WeaponUpgradeTemplate UpgradeTemplate) { return ""; }
simulated function EUISummary_WeaponStats GetUpgradeModifiersForUI(X2WeaponUpgradeTemplate UpgradeTemplate) { return GetWeaponStatsForUI(); }
function bool IsNeededForGoldenPath() { return false; }
static function FilterOutGoldenPathItems(out array<StateObjectReference> ItemsToFilter) {}
function bool ShouldDisplayWeaponAndAmmo() { return false; }
function bool IsMissionObjectiveItem() { return false; }
function bool CanWeaponApplyUpgrade(X2WeaponUpgradeTemplate UpgradeTemplate) { return false; }

defaultproperties
{
	Quantity = 0
	m_TemplateName = "BD_RequestEvac_DummyItem"

	bSingletonStateType = false
	bTacticalTransient = true
}

