class X2Ability_RequestEvac extends X2Ability config(RequestEvac);

var config name EvacAbilityName;

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

struct EvacTemplateBackup
{
	var X2AbilityTemplate Template;
	var X2AbilityTemplate VanillaCopy;
};

// Marked config purely so a static function is allowed to assign to `default.` at all.
var private config array<EvacTemplateBackup> TemplateBackups;

static final function PatchEvacAbilityTemplates()
{
	local X2AbilityTemplateManager		AbilityMgr;
	local array<X2DataTemplate>			DataTemplates;
	local X2DataTemplate				DataTemplate;
	local X2AbilityTemplate				Template;
	local array<EvacTemplateBackup>		Backups;
	local EvacTemplateBackup			Backup;

	AbilityMgr = class'X2AbilityTemplateManager'.static.GetAbilityTemplateManager();
	AbilityMgr.FindDataTemplateAllDifficulties(default.EvacAbilityName, DataTemplates);

	foreach DataTemplates(DataTemplate)
	{
		Template = X2AbilityTemplate(DataTemplate);

		if (Template == none)
		{
			continue;
		}

		Backup.Template		= Template;
		Backup.VanillaCopy	= new class'X2AbilityTemplate';

		Backup.VanillaCopy.AbilityTargetStyle	= Template.AbilityTargetStyle;
		Backup.VanillaCopy.TargetingMethod		= Template.TargetingMethod;
		Backup.VanillaCopy.AbilityCosts			= Template.AbilityCosts;
		Backup.VanillaCopy.CustomFireAnim		= Template.CustomFireAnim;
		Backup.VanillaCopy.Hostility			= Template.Hostility;
		Backup.VanillaCopy.ConcealmentRule		= Template.ConcealmentRule;
		Backup.VanillaCopy.BuildNewGameStateFn	= Template.BuildNewGameStateFn;
		Backup.VanillaCopy.BuildVisualizationFn	= Template.BuildVisualizationFn;

		Backups.AddItem(Backup);
	}

	default.TemplateBackups = Backups;

	`RELOG("Found" @ Backups.Length @ "variant(s) of ability" @ default.EvacAbilityName);

	if (Backups.Length == 0)
	{
		`Redscreen("[WOTC] Request Evac: could not find the '" $ default.EvacAbilityName $ "' ability template, the mod will have no effect. If another mod renames the evac ability, set EvacAbilityName in XComRequestEvac.ini.");
		return;
	}

	ApplyEvacAbilityPatch();
}

static final function ApplyEvacAbilityPatch()
{
	local EvacTemplateBackup Backup;

	RestoreEvacAbilityTemplates();

	foreach default.TemplateBackups(Backup)
	{
		PatchEvacAbilityTemplate(Backup.Template);
	}

	`RELOG("Applied the Request Evac patch to" @ default.TemplateBackups.Length @ "template(s).");
}

static final function RestoreEvacAbilityTemplates()
{
	local EvacTemplateBackup Backup;

	foreach default.TemplateBackups(Backup)
	{
		if (Backup.Template == none || Backup.VanillaCopy == none)
		{
			continue;
		}

		Backup.Template.AbilityTargetStyle = Backup.VanillaCopy.AbilityTargetStyle;
		Backup.Template.TargetingMethod = Backup.VanillaCopy.TargetingMethod;
		Backup.Template.AbilityCosts = Backup.VanillaCopy.AbilityCosts;
		Backup.Template.CustomFireAnim = Backup.VanillaCopy.CustomFireAnim;
		Backup.Template.Hostility = Backup.VanillaCopy.Hostility;
		Backup.Template.ConcealmentRule = Backup.VanillaCopy.ConcealmentRule;
		Backup.Template.BuildNewGameStateFn = Backup.VanillaCopy.BuildNewGameStateFn;
		Backup.Template.BuildVisualizationFn = Backup.VanillaCopy.BuildVisualizationFn;
	}
}

static final function bool IsTutorialMission()
{
	local XComTacticalGRI TacticalGRI;

	TacticalGRI = XComTacticalGRI(class'WorldInfo'.static.GetWorldInfo().GRI);

	if (TacticalGRI == none)
	{
		return false;
	}

	return XComTutorialMgr(TacticalGRI.ReplayMgr) != none;
}

// Called on every tactical start.
static final function UpdateEvacAbilityForCurrentMission()
{
	if (IsTutorialMission())
	{
		`RELOG("Tutorial mission detected - standing down for this mission.");
		RestoreEvacAbilityTemplates();
	}
	else
	{
		ApplyEvacAbilityPatch();
	}
}

static final function PatchEvacAbilityTemplate(X2AbilityTemplate Template)
{
	local X2AbilityCost_ActionPoints	ActionPointCost;
	local int							Idx;

	if (Template == none)
	{
		return;
	}

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

	for (Idx = Template.AbilityCosts.Length - 1; Idx >= 0; Idx--)
	{
		if (X2AbilityCost_ActionPoints(Template.AbilityCosts[Idx]) != none)
		{
			Template.AbilityCosts.Remove(Idx, 1);
		}
	}

	ActionPointCost = new class'X2AbilityCost_ActionPoints';
	ActionPointCost.iNumPoints = default.ActionCost;
	ActionPointCost.bFreeCost = default.FreeAction;
	Template.AbilityCosts.AddItem(ActionPointCost);

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
	NewGameState = History.CreateNewGameState(true, Context);

	AbilityContext = XComGameStateContext_Ability(NewGameState.GetContext());
	AbilityState = XComGameState_Ability(History.GetGameStateForObjectID(AbilityContext.InputContext.AbilityRef.ObjectID, eReturnType_Reference));
	AbilityTemplate = AbilityState.GetMyTemplate();

	UnitState = XComGameState_Unit(NewGameState.ModifyStateObject(class'XComGameState_Unit', AbilityContext.InputContext.SourceObject.ObjectID));
	AbilityTemplate.ApplyCost(AbilityContext, AbilityState, UnitState, none, NewGameState);

	if (default.PlaceEvac && AbilityContext.InputContext.TargetLocations.Length > 0)
	{
		EvacLocation = AbilityContext.InputContext.TargetLocations[0];
		EvacState = class'XComGameState_RequestEvac'.static.InitiateEvacZoneDeployment(NewGameState, EvacLocation,, true);
	}
	else
	{
		EvacState = class'XComGameState_RequestEvac'.static.InitiateEvacZoneDeployment(NewGameState);
	}

	// Put the Request Evac ability on cooldown that's equal to the delay before Skyranger arrives + delay after Skyranger leaves.
	SetGlobalCooldown(AbilityTemplate.DataName, Max(EvacState.GetCountdown(), 0) + EvacState.TurnsBeforeEvacExpires, UnitState.ControllingPlayer.ObjectID, NewGameState);

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
	if (Rand(100) < 10)
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
	{
		return;
	}

	if (EvacState.GetCountdown() > 0)
	{
		ActionMetadata = EmptyMetadata;
		ActionMetadata.StateObject_OldState = EvacState;
		ActionMetadata.StateObject_NewState = EvacState;

		// drop a flare at the point the evac zone will appear.
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
		{
			return;
		}

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
	local int MinDelay, MaxDelay;

	if (!default.RandomizeEvacTurns)
	{
		return Max(default.TurnsBeforeEvac, 0);
	}

	MinDelay = Max(default.MinimumTurnBeforeEvac, 0);
	MaxDelay = Max(default.MaximumTurnsBeforeEvac, MinDelay);

	return MinDelay + `SYNC_RAND_STATIC(MaxDelay - MinDelay + 1);
}

static final function vector GenerateEvacLocation(optional out int OutFoundValidLocation)
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
	OutFoundValidLocation = 0;

	for (SearchAttempts = 0; SearchAttempts <= 100; SearchAttempts++)
	{
		if (SearchAttempts > 10)
		{
			IdealSpawnTilesOffset = `SYNC_RAND_STATIC(50);
			GeneratedLocation = SpawnManager.SelectReinforcementsLocation(none, XCOMLocation, IdealSpawnTilesOffset, false, false, true /*bRequiresVerticalClearance*/, default.AlwaysOrientAlongLOP);
		}
		else
		{
			IdealSpawnTilesOffset = `SYNC_RAND_STATIC(Max(default.DistanceFromXComSquad, 1));
			GeneratedLocation = SpawnManager.SelectReinforcementsLocation(none, XCOMLocation, IdealSpawnTilesOffset, default.EvacInLOS, false, true /*bRequiresVerticalClearance*/, default.AlwaysOrientAlongLOP);
		}

		`RELOG("Attempt" @ SearchAttempts @ `ShowVar(IdealSpawnTilesOffset) @ `ShowVar(GeneratedLocation));

		if (!WorldData.Volume.EncompassesPoint(GeneratedLocation))
		{
			`RELOG("This location is not encompassed by world volume, skipping.");
			continue;
		}

		SpawnTile = WorldData.GetTileCoordinatesFromPosition(GeneratedLocation);

		if (class'X2TargetingMethod_EvacZone'.static.ValidateEvacArea(SpawnTile, false))
		{
			`RELOG("This is a valid evac location.");
			OutFoundValidLocation = 1;
			return GeneratedLocation;
		}

		`RELOG("This location is not valid for evac, skipping.");
	}

	`RELOG("WARNING :: Failed to find a valid evac location in 100 attempts, giving up.");

	return GeneratedLocation;
}


// --------------------------------------------------------------------------------------------------------------
// Helper method

static private function SetGlobalCooldown(const name AbilityName, const int Cooldown, const int SourcePlayerID, optional XComGameState UseGameState)
{
	local XComGameState			NewGameState;
	local XComGameState_Player	PlayerState;

	if (XComGameState_Player(`XCOMHISTORY.GetGameStateForObjectID(SourcePlayerID)) == none)
	{
		`RELOG("WARNING :: No player state for object ID" @ SourcePlayerID @ "- cannot set global cooldown for" @ AbilityName);
		return;
	}

	NewGameState = UseGameState;

	if (NewGameState == none)
	{
		NewGameState = class'XComGameStateContext_ChangeContainer'.static.CreateChangeState(AbilityName @ "set global cooldown:" @ Cooldown);
	}

	PlayerState = XComGameState_Player(NewGameState.GetGameStateForObjectID(SourcePlayerID));

	if (PlayerState == none)
	{
		PlayerState = XComGameState_Player(NewGameState.ModifyStateObject(class'XComGameState_Player', SourcePlayerID));
	}

	PlayerState.SetCooldown(AbilityName, Cooldown);

	// Only submit the state if we're the ones who created it.
	if (UseGameState == none)
	{
		`GAMERULES.SubmitGameState(NewGameState);
	}
}