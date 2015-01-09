@echo off
:: "C:\Program Files (x86)\Steam\steamapps\common\GarrysMod\bin\gmpublish.exe" create -addon "R:\Addon hooks Conflict Finder.gma" -icon "C:\Program Files (x86)\Steam\steamapps\common\GarrysMod\garrysmod\addons\Addon hooks Conflict Finder\Addon hooks Conflict Finder.jpg"
set /P changes=Motif de la mise … jour : 
"C:\Program Files (x86)\Steam\steamapps\common\GarrysMod\bin\gmpublish.exe" update -addon "R:\Addon hooks Conflict Finder.gma" -id "368857085" -changes "%changes%"
pause
