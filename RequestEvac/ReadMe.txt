[h1]Description[/h1]

The ability to place the evac zone has been modified. No longer will you be able to place the evac zone wherever you want. No longer will it appear immediately either.
You will now request an evac, then Firebrand will place the evac zone when she is ready.

[h1]Changes[/h1]

By default, requesting an evac will break concealment. Firebrand will need at least 2 turns to find a location. A flare will show where the evac zone will spawn.
The evac zone will remain active for 3 turns.

All can be changed in the config folder in [u]XComRequestEvac.ini[/u]

[h1]Notes[/h1]

Do not use this mod if you're using the Tutorial. You won't be able to place the evac because I'm modifying the Place Evac ability.

[h1]Credits[/h1]

Thanks to Maluco Marinero and his Delayed Evac mod from where I took most of the code regarding delaying the time for the evac to spawn.
Thanks to Pavonis Interactive, tracktwo, Amineri for their implementation.
Thanks to Astral Descend for his help on finding how the missions handled evac spawn.

[h1]Troubleshooting[/h1]
https://www.reddit.com/r/xcom2mods/wiki/mod_troubleshooting
[url=steamcommunity.com/sharedfiles/filedetails/?id=683218526]Mods not working properly / at all[/url]
[url=steamcommunity.com/sharedfiles/filedetails/?id=625230005]Mod not working? Mods still have their effects after you disable them?[/url]


Changelog:

1. Rebuilt the mod from the ground up, got rid of unnececssary assets, cooked the remaining assets.
2. Added CHL config to inform people that Request Evac is incompatible with Long War of the Chosen, which has similar functionality built-in.
3. Reformatted XComRequestEvac.ini to no longer include potentially problematic inline comments.
4. Reorganized localization files and added Russian localization.
5. The mod no longer uses potentially problematic method of recreating the Place Evac Zone ability template, and instead patches the existing template.
6. If the location of the Evac Flare stops being a valid evac zone location (like the floor under it being destroyed), the mod will now automatically find new location for the evac and respawn the flare there. Previously the mod would just destroy the flare and reset the countdown. Same handling for the Evac Zone itself being destroyed.
7. Using Request Evac will now put it on cooldown until Skyranger arrives and leaves.
8. Maximum range between squad and randomly selected evac location reduced from 20 tiles to 10.
9. The delay before evac arrives is no longer random by default, and equals 2 turns.
10. Logging is now disabled by default and can be enabled in config.

Known issues: 

1. Sounds of Skyranger hovering do not disappear after evac has expired.

While working on this update, I also discovered a base game bug that causes the Evac Zone to reappear when loading a save that was after the Evac Zone was destroyed. It will require a Highlander fix, which will come, eventually, but for now the bandaid fix is already up in the Core Collection Meta Mod, which I suggest marking as a companion mod for Request Evac in its description.

[WOTC] Core Collection Meta Mod
https://steamcommunity.com/sharedfiles/filedetails/?id=2166295671