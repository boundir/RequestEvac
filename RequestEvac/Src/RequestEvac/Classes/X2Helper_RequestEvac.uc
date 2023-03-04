class X2Helper_RequestEvac extends Object;

static function ReplaceEvacAbility()
{
	local X2CharacterTemplateManager CharacterManager;
	local X2CharacterTemplate CharacterTemplate;
	local array<X2DataTemplate> DataTemplates;
	local X2DataTemplate Template, DiffTemplate;

	CharacterManager = class'X2CharacterTemplateManager'.static.GetCharacterTemplateManager();

	foreach CharacterManager.IterateTemplates(Template, None)
	{
		CharacterManager.FindDataTemplateAllDifficulties(Template.DataName, DataTemplates);

		foreach DataTemplates(DiffTemplate)
		{
			CharacterTemplate = X2CharacterTemplate(DiffTemplate);

			if (CharacterTemplate == none)
			{
				continue;
			}

			if(CharacterTemplate.Abilities.Find('PlaceEvacZone') != INDEX_NONE)
			{
				CharacterTemplate.Abilities.RemoveItem('PlaceEvacZone');
				CharacterTemplate.Abilities.AddItem('RequestEvacZone');
			}
		}
	}
}

static function bool IsDLCLoaded(coerce name DLCIdentifier)
{
	local XComOnlineEventMgr OnlineEventMgr;
	local int Index;

	OnlineEventMgr = `ONLINEEVENTMGR;

	for(Index = 0; Index < OnlineEventMgr.GetNumDLC(); Index++)
	{
		if (DLCIdentifier == OnlineEventMgr.GetDLCNames(Index))
		{
			return true;
		}
	}

	return false;
}

static function int GetEvacDelayConfig()
{
	local array<int> EvacNumbers;
	local int Idx;

	if(class'X2Ability_RequestEvac'.default.RandomizeEvacTurns)
	{
		for(Idx = class'X2Ability_RequestEvac'.default.MinimumTurnBeforeEvac; Idx <= class'X2Ability_RequestEvac'.default.MaximumTurnsBeforeEvac; Idx++)
		{
			EvacNumbers.AddItem(Idx);
		}

		return EvacNumbers[Rand(EvacNumbers.Length)];
	}

	return class'X2Ability_RequestEvac'.default.TurnsBeforeEvac;
}