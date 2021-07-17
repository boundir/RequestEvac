class X2Ability_RequestEvac extends X2Ability config(RequestEvac);

var config int ActionCost; // in tiles
var config int GlobalCooldown; // in tiles
var config int DistanceFromXComSquad;
var config bool EvacInLOS;
var config bool AlwaysOrientAlongLOP;
var config bool FreeAction;
var config bool ShouldBreakConcealment;

var config bool RandomizeEvacTurns;
var config int TurnsBeforeEvac;
var config int MinimumTurnBeforeEvac;
var config int MaximumTurnsBeforeEvac;

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

	Template.CustomFireAnim = 'HL_SignalPoint';
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

	local int Delay;
	local Vector EvacLocation; // actually used spawn location, out parameter

	History = `XCOMHISTORY;
	//Build the new game state frame
	NewGameState = History.CreateNewGameState(true, Context);	

	AbilityContext = XComGameStateContext_Ability(NewGameState.GetContext());	
	AbilityState = XComGameState_Ability(History.GetGameStateForObjectID(AbilityContext.InputContext.AbilityRef.ObjectID, eReturnType_Reference));	
	AbilityTemplate = AbilityState.GetMyTemplate();

	// Use of AIReinforcementSpawner methods
	EvacLocation = GetEvacLocation();

	UnitState = XComGameState_Unit(NewGameState.ModifyStateObject(class'XComGameState_Unit', AbilityContext.InputContext.SourceObject.ObjectID));
	//Apply the cost of the ability
	AbilityTemplate.ApplyCost(AbilityContext, AbilityState, UnitState, none, NewGameState);

	Delay = GetEvacDelay();
	class'XComGameState_RequestEvac'.static.InitiateEvacZoneDeployment(Delay, EvacLocation, NewGameState);

	//Return the game state we have created
	return NewGameState;	
}

simulated function RequestEvac_BuildVisualization(XComGameState VisualizeGameState)
{
	local XComGameState_RequestEvac EvacState;

	if(!`XPROFILESETTINGS.Data.bEnableZipMode)
	{
		TypicalAbility_BuildVisualization(VisualizeGameState);
	}

	foreach VisualizeGameState.IterateByClassType(class'XComGameState_RequestEvac', EvacState)
	{
		break;
	}
	`assert(EvacState != none);

	EvacState.SoldierRequestEvac(VisualizeGameState);
}

function int GetEvacDelay()
{
	local int Idx, Delay;
	local array<int> EvacNumbers;

	if(default.RandomizeEvacTurns)
	{
		for(Idx = default.MinimumTurnBeforeEvac; Idx <= default.MaximumTurnsBeforeEvac; Idx++)
		{
			EvacNumbers.AddItem(Idx);
		}
		Delay = EvacNumbers[Rand(EvacNumbers.Length)];
	}
	else
	{
		Delay = default.TurnsBeforeEvac;
	}

	return Delay;
}

public function Vector GetEvacLocation()
{
	local int IdealSpawnTilesOffset, SearchAttempts;
	local XComAISpawnManager SpawnManager;
	local vector XCOMLocation, EvacLocation;
	local TTile SpawnTile;
	local bool LocationFound;
	local XComWorldData WorldData;

	WorldData = `XWORLD;
	SpawnManager = `SPAWNMGR;
	
	XCOMLocation = SpawnManager.GetCurrentXComLocation();
	LocationFound = false;
	SearchAttempts = 0;
	
	while(!LocationFound)
	{
		IdealSpawnTilesOffset = `SYNC_RAND(default.DistanceFromXComSquad);
		`LOG("Searching Valid Evac Location:" @ IdealSpawnTilesOffset, , 'RequestEvac');

		if(SearchAttempts > 10)
		{
			// We didn't find a valid location with 10 attempts. We will search a valid location on the map.
			IdealSpawnTilesOffset = `SYNC_RAND(50);
			EvacLocation = SpawnManager.SelectReinforcementsLocation(none, XCOMLocation, IdealSpawnTilesOffset, false, false, false, default.AlwaysOrientAlongLOP);
		}
		else
		{
			EvacLocation = SpawnManager.SelectReinforcementsLocation(none, XCOMLocation, IdealSpawnTilesOffset, default.EvacInLOS, false, false, default.AlwaysOrientAlongLOP);
		}

		SearchAttempts++;

		if (!WorldData.Volume.EncompassesPoint(EvacLocation))
		{
			continue;
		}

		// validate the actual location (in case floor tiles have been destroyed)
		SpawnTile = `XWORLD.GetTileCoordinatesFromPosition( EvacLocation );

		if (!class'X2TargetingMethod_EvacZone'.static.ValidateEvacArea( SpawnTile, false ))
		{
			continue;
		}
		LocationFound = true;
	}

	return EvacLocation;
}