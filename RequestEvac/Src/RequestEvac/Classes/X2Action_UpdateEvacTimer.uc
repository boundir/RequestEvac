class X2Action_UpdateEvacTimer extends X2Action;

var private XComGameState_RequestEvac EvacState;

simulated state Executing
{
	begin:

		EvacState = XComGameState_RequestEvac(`XCOMHISTORY.GetSingleGameStateObjectForClass(class'XComGameState_RequestEvac', true));
		if (EvacState != none && !EvacState.bRemoved)
		{
			EvacState.UpdateEvacTimer();
		}

		CompleteAction();
}
