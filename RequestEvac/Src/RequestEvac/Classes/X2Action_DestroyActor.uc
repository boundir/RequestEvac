class X2Action_DestroyActor extends X2Action;

simulated state Executing
{
	begin:

		`RELOG("Destroying actor:" @ Metadata.VisualizeActor != none);

		if (Metadata.VisualizeActor != none)
		{
			Metadata.VisualizeActor.Destroy();
		}

		CompleteAction();
}
