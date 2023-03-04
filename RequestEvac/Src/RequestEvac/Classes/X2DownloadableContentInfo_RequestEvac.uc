class X2DownloadableContentInfo_RequestEvac extends X2DownloadableContentInfo;

static event OnPostTemplatesCreated()
{
	local X2AbilityTemplateManager AbilityMgr;
	local X2AbilityTemplate Template;

	AbilityMgr = class'X2AbilityTemplateManager'.static.GetAbilityTemplateManager();

	Template = AbilityMgr.FindAbilityTemplate('PlaceEvacZone');

	class'X2Ability_RequestEvac'.static.PatchEvacAbilityTemplate(Template);
}

//exec function TestEvacZone()
//{
//	local WorldInfo WWorldInfo;
//	local Actor FoundActor;
//	local X2Actor_EvacZone EvacZone;
//
//	class'Helpers'.static.OutputMsg("Evac zone currently exists:" @ class'XComGameState_EvacZone'.static.GetEvacZone() != none @ "it is removed:" @ class'XComGameState_EvacZone'.static.GetEvacZone().bRemoved);
//
//
//	WWorldInfo = class'WorldInfo'.static.GetWorldInfo();
//
//	foreach WWorldInfo.AllActors(class'Actor', FoundActor) 
//	{
//		EvacZone = X2Actor_EvacZone(FoundActor);
//		if (EvacZone == none)
//			continue;
//
//		class'Helpers'.static.OutputMsg("Found an Evac Zone actor.");
//	}
//	class'Helpers'.static.OutputMsg("Current History Index:" @ `XCOMHISTORY.GetCurrentHistoryIndex());
//}