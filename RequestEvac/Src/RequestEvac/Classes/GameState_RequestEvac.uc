class GameState_RequestEvac extends XComGameState_BaseObject config(RequestEvac);

var config bool RandomizeEvacTurns;
var config bool DisplayFlareBeforeEvacSpawn;
var config int TurnsBeforeEvac;
var config int MinimumTurnBeforeEvac;
var config int MaximumTurnsBeforeEvac;
var config int TurnsBeforeEvacExpires;

var int EvacCounter;
var int TurnsToEvac;
var() protectedwrite Vector EvacLocation;
var() protectedwrite ETeam Team;
var Actor FOWViewer;

static function GameState_RequestEvac RequestEvac(XComGameState NewGameState, Vector SpawnLocation, optional ETeam InTeam = eTeam_XCom, optional string InBlueprintMapOverride)
{
	local XComGameState_EvacZone EvacState;
	local X2Actor_EvacZone EvacZoneActor;
	local GameState_RequestEvac CallEvacState;
	local GameState_RequestEvac OldGameState;
	local XComGameStateHistory History;

	// If we have requested the evac again, and there is an evac zone on the map, remove it
	EvacState = class'XComGameState_EvacZone'.static.GetEvacZone(InTeam);
	if (EvacState != none)
	{
		EvacZoneActor = X2Actor_EvacZone( EvacState.GetVisualizer() );
		if (EvacZoneActor != none)
		{
			EvacZoneActor.Destroy();
		}

		NewGameState.RemoveStateObject(EvacState.ObjectID);
	}

	History = `XCOMHISTORY;

	// If we have requested the evac again, remove the previous listener
	foreach History.IterateByClassType(class'GameState_RequestEvac', OldGameState)
	{
		if(OldGameState != none)
		{
			OldGameState.UnRegisterListener();
		}
	}

	CallEvacState = GameState_RequestEvac(NewGameState.CreateNewStateObject(class'GameState_RequestEvac'));
	CallEvacState.Team = InTeam;

	CallEvacState.EvacCounter = 0;
	CallEvacState.EvacLocation = SpawnLocation;
	NewGameState.AddStateObject(CallEvacState);

	CallEvacState.RegisterListener();

	return CallEvacState;
}

function RegisterListener()
{
	local Object ThisObj;
	local XComGameState_Player PlayerState;

	GetTurnsToEvac();

	// `log("DEBUG : RegisterListener", , 'RequestEvac');
	ThisObj = self;
	PlayerState = class'XComGameState_Player'.static.GetPlayerState(eTeam_XCom);
	`XEVENTMGR.RegisterForEvent(ThisObj, 'PlayerTurnBegun', OnTurnBegun, ELD_OnStateSubmitted, , PlayerState);
}

function UnRegisterListener()
{
	local Object ThisObj;

	ThisObj = self;
	`XEVENTMGR.UnRegisterFromEvent(ThisObj, 'PlayerTurnBegun');
}

function GetTurnsToEvac()
{
	local int Idx;
	local array<int> EvacNumbers;

	if(default.RandomizeEvacTurns)
	{
		for(Idx = default.MinimumTurnBeforeEvac; Idx <= default.MaximumTurnsBeforeEvac; Idx++)
		{
			EvacNumbers.AddItem(Idx);
		}
		TurnsToEvac = EvacNumbers[Rand(EvacNumbers.Length)];
		// `log("DEBUG : RANDOMIZER" @ EvacNumbers[Rand(EvacNumbers.Length)], , 'RequestEvac');
	}
	else
	{
		TurnsToEvac = default.TurnsBeforeEvac;
	}
}

function EventListenerReturn OnTurnBegun(Object EventData, Object EventSource, XComGameState GameState, Name EventID, Object CallbackData)
{
	local XComGameState NewGameState;
	local X2GameRuleset Ruleset;
	local GameState_RequestEvac NewSpawnerState;
	local Object ThisObj;
	local XComGameState_EvacZone EvacState;
	local X2Actor_EvacZone EvacZoneActor;

	ThisObj = self;
	Ruleset = `XCOMGAME.GameRuleset;

	// `log("DEBUG : EvacCounter:" @ EvacCounter, , 'RequestEvac');
	// `log("DEBUG : TurnsBeforeEvac:" @ TurnsToEvac, , 'RequestEvac');

	if( EvacCounter >= 0 )
	{
		NewGameState = class'XComGameStateContext_ChangeContainer'.static.CreateChangeState("UpdateEvacCounter");
		NewSpawnerState = GameState_RequestEvac(NewGameState.CreateStateObject(class'GameState_RequestEvac', ObjectID));
		NewSpawnerState.EvacCounter++;

		if(NewSpawnerState.EvacCounter >= TurnsToEvac)
		{
			if(NewSpawnerState.EvacCounter == TurnsToEvac)
			{
				// `log("DEBUG : Should spawn evac zone", , 'RequestEvac');

				class'XComGameState_EvacZone'.static.PlaceEvacZone(NewGameState, EvacLocation, Team);
				XComGameStateContext_ChangeContainer(NewGameState.GetContext()).BuildVisualizationFn = BuildVisualizationForEvacSuccess;
			}
			else
			{
				if(NewSpawnerState.EvacCounter >= (TurnsToEvac + default.TurnsBeforeEvacExpires) )
				{
					// `log("DEBUG : Should destroy existing evac zone", , 'RequestEvac');

					EvacState = class'XComGameState_EvacZone'.static.GetEvacZone();
					if (EvacState != none)
					{
						// `log("DEBUG : Found evac zone to destroy", , 'RequestEvac');

						EvacZoneActor = X2Actor_EvacZone( EvacState.GetVisualizer() );
						if (EvacZoneActor != none)
						{
							// `log("DEBUG : Destroy it!", , 'RequestEvac');

							EvacZoneActor.Destroy();
							DestroyRevealedArea(NewGameState);
						}

						NewGameState.RemoveStateObject(EvacState.ObjectID);
					}
					NewGameState.RemoveStateObject(NewSpawnerState.ObjectID);
					`XEVENTMGR.UnRegisterFromEvent(ThisObj, 'PlayerTurnBegun');
				}
			}

			Ruleset.SubmitGameState(NewGameState);
		}
		else
		{
			if( (default.DisplayFlareBeforeEvacSpawn) && (NewSpawnerState.EvacCounter == TurnsToEvac - 1) )
			{
				SetupWarmupFlare(NewGameState);
			}
			NewGameState.AddStateObject(NewSpawnerState);
			Ruleset.SubmitGameState(NewGameState);
		}
	}

	return ELR_NoInterrupt;
}

function BuildVisualizationForSpawnerCreation(XComGameState VisualizeGameState)
{
	local GameState_RequestEvac SpawnerState;

	SpawnerState = GameState_RequestEvac(`XCOMHISTORY.GetGameStateForObjectID(ObjectID));

	if(EvacCounter == TurnsToEvac)
	{
		return; // we've completed the evac spawn
	}

	SetupNarrative(VisualizeGameState, SpawnerState);
	DestroyRevealedArea(VisualizeGameState);
}

function BuildVisualizationForEvacSuccess(XComGameState VisualizeGameState)
{
	local VisualizationActionMetadata SyncMetadata;
	local XComGameState_EvacZone EvacZone;
	local X2Action_CameraLookAt CameraAction;
	local X2Action_RevealArea RevealAreaAction;
	local X2Action_PlayEffect FlareEffectAction;

	// `log("DEBUG : EvacZone spawning", , 'RequestEvac');

	foreach VisualizeGameState.IterateByClassType(class'XComGameState_EvacZone', EvacZone)
	{
		SyncMetadata.StateObject_OldState = EvacZone;
		SyncMetadata.StateObject_NewState = EvacZone;
		SyncMetadata.VisualizeActor = EvacZone.GetVisualizer();

		class'X2Action_SyncVisualizer'.static.AddToVisualizationTree(SyncMetadata, VisualizeGameState.GetContext());

		// `log("DEBUG : AssociatedObjectID:" @ EvacZone.ObjectID, , 'RequestEvac');
		if(default.DisplayFlareBeforeEvacSpawn)
		{
			FlareEffectAction = X2Action_PlayEffect( class'X2Action_PlayEffect'.static.AddToVisualizationTree(SyncMetadata, VisualizeGameState.GetContext()) );
			FlareEffectAction.EffectName = "DelayedEvac_Assets.DelayedEvac_WarmupFlare";
			FlareEffectAction.EffectLocation = EvacLocation;
			FlareEffectAction.bStopEffect = true;
		}

		RevealAreaAction = X2Action_RevealArea(class'X2Action_RevealArea'.static.AddToVisualizationTree(SyncMetadata, VisualizeGameState.GetContext()));
		RevealAreaAction.ScanningRadius = class'XComWorldData'.const.WORLD_StepSize * 5.0f;
		RevealAreaAction.TargetLocation = EvacLocation;
		RevealAreaAction.bDestroyViewer = false;
		RevealAreaAction.AssociatedObjectID = EvacZone.ObjectID;

		CameraAction = class'WorldInfo'.static.GetWorldInfo().Spawn(class'X2Action_CameraLookAt');
		CameraAction = X2Action_CameraLookAt(class'X2Action_CameraLookAt'.static.AddToVisualizationTree(SyncMetadata, VisualizeGameState.GetContext()));
		CameraAction.LookAtLocation = EvacLocation;
		CameraAction.LookAtDuration = 4.0;
		CameraAction.SnapToFloor = true;

	}
}

function SetupNarrative(XComGameState GameState, GameState_RequestEvac SpawnerState)
{
	local VisualizationActionMetadata ActionMetadata;
	local array<string> NarrativePaths;
	local string NarrativePath;
	local XComNarrativeMoment NarrativeMoment;
	local X2Action_PlayNarrative Narrative;

	NarrativePaths.AddItem("DelayedEvac_Assets.DelayedEvac_Confirmed_Firebrand_01");
	NarrativePaths.AddItem("DelayedEvac_Assets.DelayedEvac_Confirmed_Firebrand_02");

	NarrativePath = NarrativePaths[Rand(2)];

	ActionMetadata.StateObject_OldState = SpawnerState;
	ActionMetadata.StateObject_NewState = SpawnerState;
	ActionMetadata.VisualizeActor = SpawnerState.GetVisualizer();

	class'Action_RequestEvac'.static.AddToVisualizationTree(ActionMetadata, GameState.GetContext());

	NarrativeMoment = XComNarrativeMoment(DynamicLoadObject(NarrativePath, class'XComNarrativeMoment'));
	Narrative = X2Action_PlayNarrative( class'X2Action_PlayNarrative'.static.AddToVisualizationTree(ActionMetadata, GameState.GetContext()) );

	Narrative.Moment = NarrativeMoment;
	Narrative.WaitForCompletion = false;
	Narrative.StopExistingNarrative = false;
}

function SetupWarmupFlare(XComGameState GameState)
{
	local VisualizationActionMetadata ActionMetadata;
	local GameState_RequestEvac SpawnerState;
	local X2Action_PlayEffect FlareEffectAction;
	local X2Action_CameraLookAt CameraAction;

	SpawnerState = GameState_RequestEvac(`XCOMHISTORY.GetGameStateForObjectID(ObjectID));

	FlareEffectAction = X2Action_PlayEffect( class'X2Action_PlayEffect'.static.AddToVisualizationTree(ActionMetadata, GameState.GetContext()) );

	FlareEffectAction.EffectName = "DelayedEvac_Assets.DelayedEvac_WarmupFlare";
	FlareEffectAction.EffectLocation = EvacLocation;
	FlareEffectAction.CenterCameraOnEffectDuration = 0;
	FlareEffectAction.bStopEffect = false;

	ActionMetadata.StateObject_OldState = SpawnerState;
	ActionMetadata.StateObject_NewState = SpawnerState;

	CameraAction = class'WorldInfo'.static.GetWorldInfo().Spawn(class'X2Action_CameraLookAt');
	CameraAction = X2Action_CameraLookAt(class'X2Action_CameraLookAt'.static.AddToVisualizationTree(ActionMetadata, GameState.GetContext()));
	CameraAction.LookAtLocation = EvacLocation;
	CameraAction.LookAtDuration = 2.0;
	CameraAction.SnapToFloor = true;
}

function DestroyRevealedArea(XComGameState GameState)
{
	local VisualizationActionMetadata SyncMetadata;
	local XComGameState_EvacZone EvacZone;
	local X2Action_RevealArea RevealAreaAction;

	foreach GameState.IterateByClassType(class'XComGameState_EvacZone', EvacZone)
	{
		SyncMetadata.StateObject_OldState = EvacZone;
		SyncMetadata.StateObject_NewState = EvacZone;
		SyncMetadata.VisualizeActor = EvacZone.GetVisualizer();

		// `log("DEBUG Destroy AssociatedObjectID:" @ EvacZone.ObjectID, , 'RequestEvac');

		RevealAreaAction = X2Action_RevealArea(class'X2Action_RevealArea'.static.AddToVisualizationTree(SyncMetadata, GameState.GetContext()));
		RevealAreaAction.AssociatedObjectID = EvacZone.ObjectID;
		RevealAreaAction.bDestroyViewer = true;
	}
}

function OnEndTacticalPlay(XComGameState NewGameState)
{
	local X2EventManager EventManager;
	local Object ThisObj;

	super.OnEndTacticalPlay(NewGameState);

	EventManager = `XEVENTMGR;
	ThisObj = self;

	EventManager.UnRegisterFromEvent(ThisObj, 'PlayerTurnBegun');
}

DefaultProperties
{
	Team=eTeam_XCom
}