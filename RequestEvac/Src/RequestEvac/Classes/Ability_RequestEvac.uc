class Ability_RequestEvac extends X2Ability config(RequestEvac);


var config int ActionCost; // in tiles
var config int GlobalCooldown; // in tiles
var config bool FreeAction; // in tiles
var config bool ShouldBreakConcealment; // in tiles

var const config float BiasConeAngleInDegrees;
// if specified, will use SpawnLocation as a centerpoint around which a spawn within these bounds
// will be spawned
var config int MinimumTilesFromLocation; // in tiles
var config int MaximumTilesFromLocation; // in tiles
var config bool BiasAwayFromXComSpawn; // if true, will attempt to pick an evac location further away from the xcom spawn

static function array<X2DataTemplate> CreateTemplates()
{
	local array<X2DataTemplate> Templates;

	`log("RequestEvac loaded");
	Templates.AddItem(RequestEvac());

	return Templates;
}


static function X2AbilityTemplate RequestEvac()
{
	local X2AbilityTemplate                 Template;
	local X2AbilityCost_ActionPoints        ActionPointCost;
	local X2AbilityCooldown_Global          Cooldown;

	`CREATE_X2ABILITY_TEMPLATE(Template, 'PlaceEvacZone');

	Template.RemoveTemplateAvailablility(Template.BITFIELD_GAMEAREA_Multiplayer); // Do not allow "Evac Zone Placement" in MP!

	Template.Hostility = eHostility_Neutral;
	Template.bCommanderAbility = true;
	Template.eAbilityIconBehaviorHUD = eAbilityIconBehavior_AlwaysShow;
	Template.ShotHUDPriority = class'UIUtilities_Tactical'.const.PLACE_EVAC_PRIORITY;
	Template.IconImage = "img:///UILibrary_PerkIcons.UIPerk_evac";
	Template.AbilitySourceName = 'eAbilitySource_Commander';

	Template.AbilityToHitCalc = default.DeadEye;
	Template.AbilityShooterConditions.AddItem(default.LivingShooterProperty);
	Template.AbilityTriggers.AddItem(default.PlayerInputTrigger);

	Template.AbilityTargetStyle = default.SelfTarget;

	if(default.ShouldBreakConcealment)
	{
		Template.ConcealmentRule = eConceal_Never;
	}

	ActionPointCost = new class'X2AbilityCost_ActionPoints';
	ActionPointCost.iNumPoints = default.ActionCost;
	ActionPointCost.bFreeCost = default.FreeAction;
	Template.AbilityCosts.AddItem(ActionPointCost);

	Cooldown = new class'X2AbilityCooldown_Global';
	Cooldown.iNumTurns = default.GlobalCooldown;
	Template.AbilityCooldown = Cooldown;

	Template.BuildNewGameStateFn = RequestEvac_BuildGameState;
	Template.BuildVisualizationFn = RequestEvac_BuildVisualization;

	Template.bDontDisplayInAbilitySummary = true;

	return Template;
}

simulated function XComGameState RequestEvac_BuildGameState( XComGameStateContext Context )
{
	local XComGameState NewGameState;
	local XComGameState_Unit UnitState;	
	local XComGameState_Ability AbilityState;	
	local XComGameStateContext_Ability AbilityContext;
	local X2AbilityTemplate AbilityTemplate;
	local XComGameStateHistory History;

	local Vector ActualSpawnLocation; // actually used spawn location, out parameter

	History = `XCOMHISTORY;
	//Build the new game state frame
	NewGameState = History.CreateNewGameState(true, Context);	

	AbilityContext = XComGameStateContext_Ability(NewGameState.GetContext());	
	AbilityState = XComGameState_Ability(History.GetGameStateForObjectID(AbilityContext.InputContext.AbilityRef.ObjectID, eReturnType_Reference));	
	AbilityTemplate = AbilityState.GetMyTemplate();

	ActualSpawnLocation = GetSpawnLocation();

	UnitState = XComGameState_Unit(NewGameState.ModifyStateObject(class'XComGameState_Unit', AbilityContext.InputContext.SourceObject.ObjectID));
	//Apply the cost of the ability
	AbilityTemplate.ApplyCost(AbilityContext, AbilityState, UnitState, none, NewGameState);

	class'GameState_RequestEvac'.static.RequestEvac(NewGameState, ActualSpawnLocation, UnitState.GetTeam());

	//Return the game state we have created
	return NewGameState;	
}

simulated function RequestEvac_BuildVisualization(XComGameState VisualizeGameState)
{
	local GameState_RequestEvac EvacState;

	foreach VisualizeGameState.IterateByClassType(class'GameState_RequestEvac', EvacState)
	{
		break;
	}
	`assert(EvacState != none);

	EvacState.BuildVisualizationForSpawnerCreation(VisualizeGameState);
}


private function Vector GetSpawnLocation()
{
	local XComWorldData WorldData;
	local XComGroupSpawn Spawn;
	local XComParcelManager ParcelManager;
	local XComTacticalMissionManager MissionManager;
	local Vector ObjectiveLocation;
	local float TilesFromSpawn;
	local array<XComGroupSpawn> SpawnsInRange;
	local vector SoldierSpawnToObjectiveNormal;
	local float BiasHalfAngleDot;
	local float SpawnDot;
	local TTile SpawnTile;

	local XComAISpawnManager SpawnManager;
	local vector XCOMLocation;

	SpawnManager = `SPAWNMGR;
	XCOMLocation = SpawnManager.GetCurrentXComLocation();

	// `LOG("DEBUG : MinimumTilesFromLocation:" @ default.MinimumTilesFromLocation, , 'RequestEvac');
	// `LOG("DEBUG : MaximumTilesFromLocation:" @ default.MaximumTilesFromLocation, , 'RequestEvac');

	if(default.MinimumTilesFromLocation < 0 && default.MaximumTilesFromLocation < 0)
	{
		// simple case, this isn't a ranged check and we just want to use the exact location
		return XCOMLocation;
	}

	if(default.MinimumTilesFromLocation >= default.MaximumTilesFromLocation)
	{
		`Redscreen("SeqAct_SpawnEvacZone: The minimum zone distance is further than the maximum, this makes no sense!");
		return XCOMLocation;
	}

	// find all group spawns that lie within the the specified limits
	WorldData = `XWORLD;
	foreach `BATTLE.AllActors(class'XComGroupSpawn', Spawn)
	{
		TilesFromSpawn = VSize(Spawn.Location - XCOMLocation) / class'XComWorldData'.const.WORLD_StepSize;
		// TilesFromSpawn = VSize(ParcelManager.SoldierSpawn.Location) / class'XComWorldData'.const.WORLD_StepSize;
		// `LOG("DEBUG : TilesFromSpawn:" @ TilesFromSpawn, , 'RequestEvac');

		// Too close
		if (TilesFromSpawn < default.MinimumTilesFromLocation)
			continue;

		// Too far
		if (TilesFromSpawn > default.MaximumTilesFromLocation)
			continue;

		// not within the game board
		if (!WorldData.Volume.EncompassesPoint(Spawn.Location))
			continue;

		// validate the actual location (in case floor tiles have been destroyed)
		SpawnTile = `XWORLD.GetTileCoordinatesFromPosition( Spawn.Location );
		if (!class'X2TargetingMethod_EvacZone'.static.ValidateEvacArea( SpawnTile, false ))
			continue;

		SpawnsInRange.AddItem(Spawn);
	}

	if(SpawnsInRange.Length == 0)
	{
		// couldn't find any spawns in range!
		`Redscreen("SeqAct_SpawnEvacZone: Couldn't find any spawns in range, spawning at the centerpoint!");
		return XCOMLocation;
	}
	// `LOG("DEBUG : SpawnsInRange" @ SpawnsInRange.Length, , 'RequestEvac');
	// now pick a spawn.
	if(default.BiasAwayFromXComSpawn)
	{
		// `LOG("DEBUG : PICK A SPAWN", , 'RequestEvac');
		ParcelManager = `PARCELMGR;
		MissionManager = `TACTICALMISSIONMGR;
		if(MissionManager.GetLineOfPlayEndpoint(ObjectiveLocation))
		{
			// randomize the array so we can just take the first one that is on the opposite side of the objectives
			// from the xcom spawn
			SpawnsInRange.RandomizeOrder();

			SoldierSpawnToObjectiveNormal = Normal(ParcelManager.SoldierSpawn.Location - ObjectiveLocation);
			BiasHalfAngleDot = cos((180.0f - (BiasConeAngleInDegrees * 0.5)) * DegToRad); // negated since it's on the opposite side of the spawn
			foreach SpawnsInRange(Spawn)
			{
				SpawnDot = SoldierSpawnToObjectiveNormal dot Normal(Spawn.Location - ObjectiveLocation);
				if(SpawnDot < BiasHalfAngleDot)
				{
					return Spawn.Location;
				}
			}
		}
	}

	// random pick
	// `LOG("DEBUG : RANDOM PICK", , 'RequestEvac');
	return SpawnsInRange[`SYNC_RAND(SpawnsInRange.Length)].Location;
}