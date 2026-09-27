class UIScreenListener_RequestEvac extends UIScreenListener;

event OnInit(UIScreen Screen)
{
	class'X2Ability_RequestEvac'.static.UpdateEvacAbilityForCurrentMission();
}

defaultproperties
{
	ScreenClass = class'UITacticalHUD';
}
