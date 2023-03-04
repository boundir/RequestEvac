//---------------------------------------------------------------------------------------
//  FILE:   XComDownloadableContentInfo_RequestEvac.uc                                    
//           
//	Use the X2DownloadableContentInfo class to specify unique mod behavior when the 
//  player creates a new campaign or loads a saved game.
//  
//---------------------------------------------------------------------------------------
//  Copyright (c) 2016 Firaxis Games, Inc. All rights reserved.
//---------------------------------------------------------------------------------------

class X2DownloadableContentInfo_RequestEvac extends X2DownloadableContentInfo;

static event OnPostTemplatesCreated()
{
	class'X2Helper_RequestEvac'.static.ReplaceEvacAbility();
}