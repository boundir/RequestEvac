class X2Ability_RequestEvac extends X2Ability config(RequestEvac);

var config int ActionCost;
var config int DistanceFromXComSquad;
var config bool EvacInLOS;
var config bool AlwaysOrientAlongLOP;
var config bool FreeAction;
var config bool ShouldBreakConcealment;

var config bool RandomizeEvacTurns;
var config bool PlaceEvac;
var config int TurnsBeforeEvac;
var config int MinimumTurnBeforeEvac;
var config int MaximumTurnsBeforeEvac;

var config bool bLog;

static final function PatchEvacAbilityTemplate(X2AbilityTemplate Template)
{
	local X2AbilityCost_ActionPoints ActionPointCost;
	
	// Targeting
	if (default.PlaceEvac)
	{
		Template.AbilityTargetStyle = new class'X2AbilityTarget_Cursor';
		Template.TargetingMethod = class'X2TargetingMethod_EvacZone';
	}
	else
	{
		Template.AbilityTargetStyle = default.SelfTarget;
		Template.TargetingMethod = class'X2TargetingMethod_TopDown';
	}

	// Cost
	ActionPointCost = new class'X2AbilityCost_ActionPoints';
	ActionPointCost.iNumPoints = default.ActionCost;
	ActionPointCost.bFreeCost = default.FreeAction;
	Template.AbilityCosts.AddItem(ActionPointCost);

	// State and Vis
	Template.CustomFireAnim = 'HL_SignalPoint';
	Template.Hostility = eHostility_Neutral;
	Template.BuildNewGameStateFn = RequestEvac_BuildGameState;
	Template.BuildVisualizationFn = RequestEvac_BuildVisualization;

	Template.ConcealmentRule = default.ShouldBreakConcealment ? eConceal_Never : eConceal_Always;
}

static private function XComGameState RequestEvac_BuildGameState(XComGameStateContext Context)
{
	local XComGameState					NewGameState;
	local XComGameState_Unit			UnitState;	
	local XComGameState_Ability			AbilityState;	
	local XComGameStateContext_Ability	AbilityContext;
	local X2AbilityTemplate				AbilityTemplate;
	local XComGameStateHistory			History;
	local Vector						EvacLocation;
	local XComGameState_RequestEvac		EvacState;

	History = `XCOMHISTORY;
	//Build the new game state frame
	NewGameState = History.CreateNewGameState(true, Context);	

	AbilityContext = XComGameStateContext_Ability(NewGameState.GetContext());	
	AbilityState = XComGameState_Ability(History.GetGameStateForObjectID(AbilityContext.InputContext.AbilityRef.ObjectID, eReturnType_Reference));	
	AbilityTemplate = AbilityState.GetMyTemplate();

	UnitState = XComGameState_Unit(NewGameState.ModifyStateObject(class'XComGameState_Unit', AbilityContext.InputContext.SourceObject.ObjectID));
	//Apply the cost of the ability
	AbilityTemplate.ApplyCost(AbilityContext, AbilityState, UnitState, none, NewGameState);

	if (default.PlaceEvac)
	{
		EvacLocation = AbilityContext.InputContext.TargetLocations[0];
		EvacState = class'XComGameState_RequestEvac'.static.InitiateEvacZoneDeployment(NewGameState, EvacLocation);
	}
	else
	{
		EvacState = class'XComGameState_RequestEvac'.static.InitiateEvacZoneDeployment(NewGameState);
	}

	// Put the Request Evac ability on cooldown that's equal to the delay before Skyranger arrives + delay after Skyranger leaves.
	SetGlobalCooldown('PlaceEvacZone', EvacState.GetCountdown() + EvacState.TurnsBeforeEvacExpires, UnitState.ControllingPlayer.ObjectID, NewGameState);

	//Return the game state we have created
	return NewGameState;
}

static private function RequestEvac_BuildVisualization(XComGameState VisualizeGameState)
{
	local XComGameStateContext_Ability	AbilityContext;
	local VisualizationActionMetadata	ActionMetadata;
	local VisualizationActionMetadata	EmptyMetadata;
	local XComGameStateHistory			History;
	local X2Action_PlaySoundAndFlyOver	SoundAndFlyover;
	local X2Action_TimedWait			TimedWait;
	local X2Action						CommonParent;
	local X2Action_PlayEffect			EvacSpawnerEffectAction;
	local X2Action_PlayNarrative		NarrativeAction;
	local XComGameState_EvacZone		EvacZone;
	local X2Action_RevealArea			RevealAreaAction;
	local XComGameState_RequestEvac		EvacState;

	History = `XCOMHISTORY;
	AbilityContext = XComGameStateContext_Ability(VisualizeGameState.GetContext());

	if (!`XPROFILESETTINGS.Data.bEnableZipMode)
	{
		TypicalAbility_BuildVisualization(VisualizeGameState);
	}
	
	// ## Set up track for the soldier
	ActionMetadata.StateObject_OldState = History.GetGameStateForObjectID(AbilityContext.InputContext.SourceObject.ObjectID,, VisualizeGameState.HistoryIndex - 1);
	ActionMetadata.StateObject_NewState = VisualizeGameState.GetGameStateForObjectID(AbilityContext.InputContext.SourceObject.ObjectID);
	ActionMetadata.VisualizeActor = History.GetVisualizer(AbilityContext.InputContext.SourceObject.ObjectID);

	CommonParent = class'X2Action_MarkerNamed'.static.AddToVisualizationTree(ActionMetadata, AbilityContext);

	SoundAndFlyOver = X2Action_PlaySoundAndFlyOver(class'X2Action_PlaySoundAndFlyover'.static.AddToVisualizationTree(ActionMetadata, AbilityContext,, CommonParent));

	// Use some RNG to choose the voiceline to say; base game does the same thing.
	if (`SYNC_RAND_STATIC(100) < 10)
	{
		SoundAndFlyOver.CharSpeech = 'MissionAbortRequest';
	}
	else
	{
		SoundAndFlyOver.CharSpeech = 'EVACrequest';
	}

	// Add some wait time to let the Soldier speak before Firebrand can answer the call.
	TimedWait =  X2Action_TimedWait(class'X2Action_TimedWait'.static.AddToVisualizationTree(ActionMetadata, AbilityContext,, CommonParent));
	TimedWait.DelayTimeSec = 2.0f;

	// ## Set up track for the evac zone

	foreach VisualizeGameState.IterateByClassType(class'XComGameState_RequestEvac', EvacState)
	{
		break;
	}
	if (EvacState == none)
		return;

	if (EvacState.GetCountdown() > 0)
	{
		ActionMetadata = EmptyMetadata;
		ActionMetadata.StateObject_OldState = EvacState;
		ActionMetadata.StateObject_NewState = EvacState;

		//  drop a flare at the point the evac zone will appear.
		EvacSpawnerEffectAction = X2Action_PlayEffect(class'X2Action_PlayEffect'.static.AddToVisualizationTree(ActionMetadata, AbilityContext, false, TimedWait));
		EvacSpawnerEffectAction.EffectName = "BDRequestEvac.P_EvacZone_Flare";
		EvacSpawnerEffectAction.EffectLocation = EvacState.GetLocation();
		EvacSpawnerEffectAction.bStopEffect = false;

		if (default.PlaceEvac)
		{
			// Don't take control of the camera, the player knows where they put the zone.
			EvacSpawnerEffectAction.CenterCameraOnEffectDuration = 0;
		}
		else
		{
			EvacSpawnerEffectAction.CenterCameraOnEffectDuration = `CONTENT.LookAtCamDuration;
		}

		NarrativeAction = X2Action_PlayNarrative(class'X2Action_PlayNarrative'.static.AddToVisualizationTree(ActionMetadata, AbilityContext, false, TimedWait));
		NarrativeAction.Moment = XComNarrativeMoment(`CONTENT.RequestGameArchetype("X2NarrativeMoments.TACTICAL.General.SKY_Gen_EvacRequested_02"));
		NarrativeAction.WaitForCompletion = false;
	}
	else
	{	
		foreach VisualizeGameState.IterateByClassType(class'XComGameState_EvacZone', EvacZone)
		{
			break;
		}
		if (EvacZone == none)
			return;

		ActionMetadata = EmptyMetadata;
		ActionMetadata.StateObject_OldState = EvacZone;
		ActionMetadata.StateObject_NewState = EvacZone;
		ActionMetadata.VisualizeActor = EvacZone.GetVisualizer();

		class'X2Action_PlaceEvacZone'.static.AddToVisualizationTree(ActionMetadata, AbilityContext, false);

		CommonParent = ActionMetadata.LastActionAdded;

		NarrativeAction = X2Action_PlayNarrative(class'X2Action_PlayNarrative'.static.AddToVisualizationTree(ActionMetadata, AbilityContext, false, CommonParent));
		NarrativeAction.Moment = XComNarrativeMoment(`CONTENT.RequestGameArchetype("BDRequestEvac.Firebrand_Arrived"));
		NarrativeAction.WaitForCompletion = false;

		RevealAreaAction = X2Action_RevealArea(class'X2Action_RevealArea'.static.AddToVisualizationTree(ActionMetadata, AbilityContext, false, CommonParent));
		RevealAreaAction.ScanningRadius = class'XComWorldData'.const.WORLD_StepSize * 5.0f;
		RevealAreaAction.TargetLocation = EvacState.GetLocation();
		RevealAreaAction.bDestroyViewer = false;
		RevealAreaAction.AssociatedObjectID = EvacZone.ObjectID;
	}
}


// Keeping these two functions here to avoid having to deal with config variables.
static final function int GenerateEvacDelay()
{
	local int Idx, Delay;
	local array<int> EvacNumbers;

	if (default.RandomizeEvacTurns)
	{
		for (Idx = default.MinimumTurnBeforeEvac; Idx <= default.MaximumTurnsBeforeEvac; Idx++)
		{
			EvacNumbers.AddItem(Idx);
		}
		Delay = EvacNumbers[`SYNC_RAND_STATIC(EvacNumbers.Length)];
	}
	else
	{
		Delay = default.TurnsBeforeEvac;
	}

	return Delay;
}

static final function vector GenerateEvacLocation()
{
	local int					IdealSpawnTilesOffset;
	local int					SearchAttempts;
	local XComAISpawnManager	SpawnManager;
	local vector				XCOMLocation;
	local vector				GeneratedLocation;
	local TTile					SpawnTile;
	local XComWorldData			WorldData;

	WorldData = `XWORLD;
	SpawnManager = `SPAWNMGR;
	
	XCOMLocation = SpawnManager.GetCurrentXComLocation();
	SearchAttempts = 0;
	
	while (true)
	{
		IdealSpawnTilesOffset = `SYNC_RAND_STATIC(default.DistanceFromXComSquad);
		`RELOG("Searching Valid Evac Location:" @ `ShowVar(IdealSpawnTilesOffset));

		if (SearchAttempts > 100)
		{
			`RELOG("WARNING :: Failed to find a valid evac location in 100 attempts, breaking to avoid a crash.");
			return vect(0, 0, 0);
		}
		else if (SearchAttempts > 10)
		{
			IdealSpawnTilesOffset = `SYNC_RAND_STATIC(50);
			GeneratedLocation = SpawnManager.SelectReinforcementsLocation(none, XCOMLocation, IdealSpawnTilesOffset, false, false, true /*bRequiresVerticalClearance*/, default.AlwaysOrientAlongLOP);

			`RELOG("Failed to find a valid evac location in XCOM LOS in 10 attempts, searching everywhere on the map.");
		}
		else
		{
			GeneratedLocation = SpawnManager.SelectReinforcementsLocation(none, XCOMLocation, IdealSpawnTilesOffset, default.EvacInLOS, false, true /*bRequiresVerticalClearance*/, default.AlwaysOrientAlongLOP);
		}

		`RELOG(`ShowVar(GeneratedLocation));
	
		if (!WorldData.Volume.EncompassesPoint(GeneratedLocation))
		{
			`RELOG("This location is not encompassed by world volume, skipping.");
			continue;
		}

		SpawnTile = `XWORLD.GetTileCoordinatesFromPosition(GeneratedLocation);
		if (class'X2TargetingMethod_EvacZone'.static.ValidateEvacArea(SpawnTile, false))
		{
			`RELOG("This is a valid evac location.");
			return GeneratedLocation;
		}

		`RELOG("This location is not valid for evac, skipping.");
		SearchAttempts++;
	}

	return GeneratedLocation;
}


// --------------------------------------------------------------------------------------------------------------
// Helper method

static private function SetGlobalCooldown(const name AbilityName, const int Cooldown, const int SourcePlayerID, optional XComGameState UseGameState)
{
	local XComGameState			NewGameState;
	local XComGameState_Player	PlayerState;

	if (UseGameState != none)
	{
		PlayerState = XComGameState_Player(UseGameState.GetGameStateForObjectID(SourcePlayerID));
		if (PlayerState == none)
		{
			PlayerState = XComGameState_Player(`XCOMHISTORY.GetGameStateForObjectID(SourcePlayerID));
			if (PlayerState == none) return;

			PlayerState = XComGameState_Player(UseGameState.ModifyStateObject(PlayerState.Class, PlayerState.ObjectID));
			PlayerState.SetCooldown(AbilityName, Cooldown);
		}
		else
		{
			PlayerState.SetCooldown(AbilityName, Cooldown);
		}
	}
	else
	{
		PlayerState = XComGameState_Player(`XCOMHISTORY.GetGameStateForObjectID(SourcePlayerID));
		if (PlayerState == none) return;

		NewGameState = class'XComGameStateContext_ChangeContainer'.static.CreateChangeState(AbilityName @ "set global cooldown:" @ Cooldown);
		PlayerState = XComGameState_Player(NewGameState.ModifyStateObject(PlayerState.Class, PlayerState.ObjectID));
		PlayerState.SetCooldown(AbilityName, Cooldown);
		`GAMERULES.SubmitGameState(NewGameState);
	}
}