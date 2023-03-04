class X2EventListener_RequestEvac extends X2EventListener config(Infiltration);

struct DelayedEvacInfiltration
{
	var int Progress;
	var int Delay;
};

var config array<DelayedEvacInfiltration> InfiltrationEvacModifiers;

static function array<X2DataTemplate> CreateTemplates()
{
	local array<X2DataTemplate> Templates;

	Templates.AddItem(CreateEvacDelayListener());

	return Templates;
}

static function CHEventListenerTemplate CreateEvacDelayListener()
{
	local CHEventListenerTemplate Template;

	`CREATE_X2TEMPLATE(class'CHEventListenerTemplate', Template, 'RequestEvac_Tactical');

	Template.AddCHEvent('GetEvacTurnsDelay', OnEvacRequested, ELD_Immediate);

	Template.RegisterInTactical = true;

	return Template;
}

static function EventListenerReturn OnEvacRequested(Object EventData, Object EventSource, XComGameState GameState, Name EventID, Object CallbackData)
{
	local XComLWTuple Tuple;

	Tuple = XComLWTuple(EventData);

	if(Tuple == none)
	{
		return ELR_NoInterrupt;
	}

	if(Tuple.Id != 'GetEvacTurnsDelay')
	{
		return ELR_NoInterrupt;
	}

	if(Tuple.Data[0].kind != XComLWTVInt)
	{
		return ELR_NoInterrupt;
	}

	if(class'X2Helper_RequestEvac'.static.IsDLCLoaded('CovertInfiltration'))
	{
		Tuple.Data[0].i = GetInfiltrationModifier();
	}
	else
	{
		Tuple.Data[0].i = class'X2Helper_RequestEvac'.static.GetEvacDelayConfig();
	}

	if(Tuple.Data[0].i < 1)
	{
		Tuple.Data[0].i = 1;
	}
	
	return ELR_NoInterrupt;

}

static function int GetInfiltrationModifier()
{
	local XComGameState_MissionSiteInfiltration InfiltrationState;
	local int CurrentInfiltration, Delay, Idx;

	Delay = class'X2Helper_RequestEvac'.static.GetEvacDelayConfig();

	InfiltrationState = XComGameState_MissionSiteInfiltration(`XCOMHISTORY.GetGameStateForObjectID(`XCOMHQ.MissionRef.ObjectID));

	if(InfiltrationState == none)
	{
		return Delay;
	}

	CurrentInfiltration = InfiltrationState.GetCurrentInfilInt();

	for(Idx = default.InfiltrationEvacModifiers.Length - 1; Idx <=0; Idx--)
	{
		if(CurrentInfiltration >= default.InfiltrationEvacModifiers[Idx].Progress)
		{
			Delay += default.InfiltrationEvacModifiers[Idx].Delay;
		}
	}

	return Delay;
}