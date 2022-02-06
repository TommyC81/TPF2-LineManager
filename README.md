# TPF2-LineManager

A mod for Transport Fever 2 to automatically manage the number of vehicles on lines.

Steam Workshop link: https://steamcommunity.com/workshop/filedetails/?id=2581894757

Taking into account the load-factor over time, demand, rate, and other factors, this mod will add/remove vehicles
to lines accordingly. This mod will greatly assist in reducing/eliminating vehicle micro management, and
will let you focus on the overall design of your transport network(s).

Source code and manual is located here: https://github.com/TommyC81/TPF2-LineManager, any issues should be raised on GitHub.
Created by https://github.com/TommyC81 with contribution from https://github.com/RusteyBucket.
This mod uses:
* https://github.com/rxi/lume created by https://github.com/rxi, with additional updates made by https://github.com/idbrii
  available on url=https://github.com/idbrii/lua-lume

This mod is inspired by and uses code snippets from:
* TPF2-Timetables, created by Celmi, available here: https://steamcommunity.com/workshop/filedetails/?id=2408373260
  and source https://github.com/IncredibleHannes/TPF2-Timetables
* Departure Board, created by kryfield, available here: https://steamcommunity.com/workshop/filedetails/?id=2692112427

## Information and options

* This mod can be added/removed to existing games as desired - it only measures live data and
  adds/removes vehicles on applicable lines accordingly.
* This mod will by default automatically manage the number of vehicles on all PASSENGER and CARGO lines utilizing
  trucks/buses, trams, aircraft, and ships. Additionally in the settings, you can also enable train management.
* There is an in-game menu with mod options, including the option to change sampling to be os time based (rather
  than in-game month based) and adjusting which lines are managed automatically. The menu is accessed by clicking the
  "[LM]" text in the bottom in-game status bar.
* Sensible default rules for both PASSENGER and CARGO lines are used by default. However, should this not work as desired,
  options as per below are available to tweak the functionality:
* **(M) - MANUAL**: To disable automatic vehicle management on a specific line, add "**(M)**" to the name of
  the line (anywhere in the line name).
* **(R:<number>) - RATE**: Line rate rules, adjusting number of vehicles to ensure line rate exceeds the set rate.
  To use, add "***(R:<number>)**" to the name of the line (anywhere in the line name).
* **(PR) - PASSENGER (RusteyBucket)**: Alternative PASSENGER line rules created by RusteyBucket. These rules will more
  aggressively manage vehicles upwards. To use, add "***(PR)**" to the name of the line (anywhere in the line name).

Examples of line naming:
* Line name "**BUS ABC-1**" - none of the specific syntax is used, this line will be automatically managed with default rules.
  according to default rules.
* Line name "**BUS ABC-1 (M)**" - this line is **MANUALLY** managed (no automatic vehicle management).
* Line name "**BUS ABC-1 (R:100)**" - this line is managed according to **(R) - RATE** line rules, achieving a rate of 100.

Other ways to manage lines is to disable automatic management of certain line types and assign rules manually where needed.

The following default rules are available:
* **(P) - PASSENGER**: Default PASSENGER line rules. To use, add "***(P)**" to the name of the line (anywhere in the line name).
* **(C) - CARGO**: Default CARGO line rules. To use, add "***(C)**" to the name of the line (anywhere in the line name).

Additionally, if you want to dig into the source and create your own rules, see 'rules.lua' within the source code.

## Quick start

1. Create a bus line.
2. Add one bus to the bus line.
3. Make sure a depot is accessible for the bus on the bus line.
4. Make sure you have cash available for buying additional buses (when the mod determines it required).

## Quick tips for best results

* Only use one type of vehicle per line (this makes addition of new vehicles more predictable).
* Don't mix PASSENGER and CARGO on the same line. Although it will work, results may not be optimal.
* If you need to update/upgrade vehicle type on a line, replace all vehicles at the same time (see above
  related item).
* Where appropriate, using a smaller vehicle size (less capacity per vehicle) allows better automatic
  fine-tuning of the line capacity.

## What the mod does

* The mod will add/remove vehicles (of the same type as already utilized on the line) according to rules, as money permits.
* When rule criteria are met, a vehicle will be added/removed accordingly to each managed line.
* When a vehicle is sold, it will sell the oldest vehicle on the line.
* The mod will additionally ensure there is at least 1 vehicle remaining on the line.

## What the mod does NOT do

* This mod will not fix poorly designed transports networks. If you have a bus line that has highly uneven demand
  along the route, you will have to fix that yourself - there is no software that can fix this for you. If no vehicles
  are added despite a single station being overloaded along the route - it is probably a sign of poor route design,
  split the route up into evenly balanced (demand) sections.
* As an alternative to improving the route network, you can try using the alternative **(R) - RATE** line rules
  or **(M) - MANUAL** line management (see Information and and options above).

## Performance

* Every in-game month (or time period), the mod takes a sample.
* Workload associated with processing the sample is spread out over several game ticks.
* Once a sampling run is complete, any identified ADD/REMOVE actions are actioned on the line.
* Thus, performance impact should be minimal. This has not been studied in-depth, but no noticeable impact of the
  sampling/updates has been observed in games with hundreds of lines/buses/trams/aircraft/ships/trains.

## Untested

* Nothing at the moment.

## Future plans

* No specific plans, except making this stable and add coding improvements as time permits
  (this is also dependent on contribution from users).

## How to Contribute

### General

* If you want to contribute to this project, open an issue on GitHub, or create a fork/branch of the project, and work on
  your fork/branch.
* When you are done with your changes and want to integrate it, open a Pull Request (PR) aimed at the main branch. You can
  of course open a PR early to get feedback if you like.
* After review and any required adjustments, the pull request can be merged into the main project. Make sure you
  continuously (re)base your fork/branch on the main branch/repository, or merge in changes from the main
  branch/repository, to ensure your fork/branch is up-to-date and can be merged without conflicts.
* Squash your commits as required to maintain a clean commit history.

### Recommended tools:

* **GitHub account** (sign up for a free account here: https://github.com/)
* **Github Desktop** (free, also requires a free GitHub account: https://desktop.github.com/)
* **Visual Studio Code** (free, https://code.visualstudio.com/), with the following free extensions
    * **Lua** (by sumneko, link: https://marketplace.visualstudio.com/items?itemName=sumneko.lua)
    * **vscode-lua-format** (by Koihik, link: https://marketplace.visualstudio.com/items?itemName=Koihik.vscode-lua-format)
    * **GitLens - Git supercharged** (by GitKraken, link: https://marketplace.visualstudio.com/items?itemName=eamodio.gitlens)
    * **Code Spell Checker** (by Street Side Software, link: https://marketplace.visualstudio.com/items?itemName=streetsidesoftware.code-spell-checker)
