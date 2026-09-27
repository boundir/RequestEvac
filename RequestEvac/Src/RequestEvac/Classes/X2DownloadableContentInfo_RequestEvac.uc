class X2DownloadableContentInfo_RequestEvac extends X2DownloadableContentInfo;

static event OnPostTemplatesCreated()
{
	class'X2Ability_RequestEvac'.static.PatchEvacAbilityTemplates();
}