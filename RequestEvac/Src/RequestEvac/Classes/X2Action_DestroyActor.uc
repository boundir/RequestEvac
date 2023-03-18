class X2Action_DestroyActor extends X2Action;

simulated state Executing
{
	begin:

		`RELOG(GetFuncName() @ "destroying actor" @ Metadata.VisualizeActor != none);
		
		Metadata.VisualizeActor.Destroy();

		// Stop the EvacZoneFlare environmental SFX (chopper blades/exhaust)
		//WorldInfo.StopAkSound(WorldInfo.PlayAkSound("SoundEnvironment.EvacZoneFlares"));

		CompleteAction();
}
