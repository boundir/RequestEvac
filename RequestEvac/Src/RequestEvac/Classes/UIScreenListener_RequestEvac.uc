class UIScreenListener_RequestEvac extends UIScreenListener;

var localized string strEvacRequestTitle;
var localized string strEvacRequestSubtitle;
var localized string strRemoveEvacTitle;
var localized string strRemoveEvacSubtitle;

// This event is triggered after a screen is initialized
event OnInit(UIScreen Screen)
{
	local Object ThisObj;
	local X2EventManager EventMgr;

	ThisObj = self;
	EventMgr = `XEVENTMGR;

	// Event management for evac zones.
	EventMgr.RegisterForEvent(ThisObj, 'PlayerTurnBegun', OnTurnBegun, ELD_OnStateSubmitted);
	EventMgr.RegisterForEvent(ThisObj, 'TileDataChanged', OnTileDataChanged, ELD_OnStateSubmitted);

	// As this handler updates the UI, don't do it on the game state thread but within a visualization
	// block instead.
	EventMgr.RegisterForEvent(ThisObj, 'EvacRequested', OnEvacRequested, ELD_OnVisualizationBlockStarted);
	EventMgr.RegisterForEvent(ThisObj, 'PlayerTurnBegun', OnEvacRequested, ELD_OnVisualizationBlockStarted);

	// Update the evac timer so it will appear if we are loading a save with an active evac timer.
	UpdateEvacTimer(false);
}

// Update/refresh the evac timer.
function UpdateEvacTimer(bool DecrementCounter)
{
	local GameState_RequestEvac EvacState;
	local XComGameStateHistory History;
	local UISpecialMissionHUD SpecialMissionHUD;

	History = `XCOMHISTORY;
	EvacState = GameState_RequestEvac(History.GetSingleGameStateObjectForClass(class'GameState_RequestEvac', true));
	SpecialMissionHUD = `PRES.GetSpecialMissionHUD();

	if (EvacState == none)
	{
		return;
	}

	`log("DEBUG : UpdateEvacTimer", , 'RequestEvac');

	// Update the UI
	if (EvacState.GetCountdown() > 0)
	{
		SpecialMissionHUD.m_kTurnCounter2.SetUIState(eUIState_Normal);
		SpecialMissionHUD.m_kTurnCounter2.SetLabel(strEvacRequestTitle);
		SpecialMissionHUD.m_kTurnCounter2.SetSubLabel(strEvacRequestSubtitle);
		SpecialMissionHUD.m_kTurnCounter2.SetCounter(string(EvacState.GetCountdown()));
	}
	else if(EvacState.GetRemoveEvacCountdown() > 0)
	{
		SpecialMissionHUD.m_kTurnCounter2.SetUIState(eUIState_Normal);
		SpecialMissionHUD.m_kTurnCounter2.SetLabel(strRemoveEvacTitle);
		SpecialMissionHUD.m_kTurnCounter2.SetSubLabel(strRemoveEvacSubtitle);
		SpecialMissionHUD.m_kTurnCounter2.SetCounter(string(EvacState.GetRemoveEvacCountdown()));
	}
	else
	{
		SpecialMissionHUD.m_kTurnCounter2.Hide();
	}
}

// Called when the player's turn has begun. Check if we have an active evac zone placement state with a countdown. If so,
// display it.
function EventListenerReturn OnTurnBegun(Object EventData, Object EventSource, XComGameState GameState, Name EventID, Object CallbackData)
{
	local XComGameState_Player Player;
	local GameState_RequestEvac EvacState;
	local XComGameStateHistory History;
	local XComGameState NewGameState;
	local bool NeedsUpdate;

	`log("DEBUG : OnTurnBegun", , 'RequestEvac');
	
	History = `XCOMHISTORY;
	EvacState = GameState_RequestEvac(History.GetSingleGameStateObjectForClass(class'GameState_RequestEvac', true));

	`log("DEBUG : OnTurnBegun GetCountdown" @ EvacState.GetCountdown(), , 'RequestEvac');
	`log("DEBUG : OnTurnBegun GetRemoveEvacCountdown" @ EvacState.GetRemoveEvacCountdown(), , 'RequestEvac');

	Player = XComGameState_Player(EventData);
	NeedsUpdate = Player != none && Player.GetTeam() == eTeam_XCom;

	if (EvacState.GetRemoveEvacCountdown() > 0 && NeedsUpdate)
	{
		// Decrement the counter if necessary
		NewGameState = class'XComGameStateContext_ChangeContainer'.static.CreateChangeState("UpdateRemoveEvacCountdown");
		EvacState = GameState_RequestEvac(NewGameState.CreateStateObject(class'GameState_RequestEvac', EvacState.ObjectID));
		EvacState.SetRemoveEvacCountdown(EvacState.GetRemoveEvacCountdown() - 1);
		NewGameState.AddStateObject(EvacState);
		`TACTICALRULES.SubmitGameState(NewGameState);

		// We've hit zero: time to delete the evac zone!
		if (EvacState.GetRemoveEvacCountdown() == 0)
		{
			class'GameState_RequestEvac'.static.RemoveExistingEvacZone(NewGameState);
			EvacState.ResetRemoveEvacCountdown();
		}
	}

	if (EvacState.GetCountdown() > 0 && NeedsUpdate)
	{
		// Decrement the counter if necessary
		NewGameState = class'XComGameStateContext_ChangeContainer'.static.CreateChangeState("UpdateEvacCountdown");
		EvacState = GameState_RequestEvac(NewGameState.CreateStateObject(class'GameState_RequestEvac', EvacState.ObjectID));
		EvacState.SetCountdown(EvacState.GetCountdown() - 1);
		NewGameState.AddStateObject(EvacState);
		`TACTICALRULES.SubmitGameState(NewGameState);

		// We've hit zero: time to spawn the evac zone!
		if (EvacState.GetCountdown() == 0)
		{
			EvacState.SpawnEvacZone();
		}
	}

	return ELR_NoInterrupt;
}

function EventListenerReturn OnTileDataChanged(Object EventData, Object EventSource, XComGameState GameState, Name EventID, Object CallbackData)
{
	local GameState_RequestEvac EvacState;
	local XComGameStateHistory History;
	local UISpecialMissionHUD SpecialMissionHUD;
	local XComGameState NewGameState;
	local TTile CenterTile;

	`log("DEBUG : OnTileDataChanged", , 'RequestEvac');

	History = `XCOMHISTORY;
	EvacState = GameState_RequestEvac(History.GetSingleGameStateObjectForClass(class'GameState_RequestEvac', true));

	// If no evac or it doesn't have an active timer, there isn't anything to do.
	if (EvacState == none || EvacState.GetCountdown() < 1)
	{
		return ELR_NoInterrupt;
	}

	CenterTile = EvacState.GetCenterTile();
	if (!class'X2TargetingMethod_EvacZone'.static.ValidateEvacArea(CenterTile, false))
	{
		NewGameState = class'XComGameStateContext_ChangeContainer'.static.CreateChangeState("Invalidating Delayed Evac Zone");

		// update the evac zone
		EvacState = GameState_RequestEvac(NewGameState.CreateStateObject(class'GameState_RequestEvac', EvacState.ObjectID));
		EvacState.ResetCountdown();
		XComGameStateContext_ChangeContainer(NewGameState.GetContext()).BuildVisualizationFn = EvacState.BuildVisualizationForFlareDestroyed;

		NewGameState.AddStateObject(EvacState);
		`XEVENTMGR.TriggerEvent('EvacSpawnerDestroyed', EvacState, EvacState);
		SpecialMissionHUD = `PRES.GetSpecialMissionHUD();
		SpecialMissionHUD.m_kTurnCounter2.Hide();
		`TACTICALRULES.SubmitGameState(NewGameState);
	}

	return ELR_NoInterrupt;
}

function EventListenerReturn OnEvacRequested(Object EventData, Object EventSource, XComGameState GameState, Name EventID, Object CallbackData)
{
	UpdateEvacTimer(false);
	return ELR_NoInterrupt;
}