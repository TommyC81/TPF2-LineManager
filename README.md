# TPF2-LineManager

A mod for Transport Fever 2 to automatically manage the number of buses/trams/aircraft/ships on passenger lines.

Taking into account the load-factor over time, and demand on the line, this mod will buy/sell
buses/trams/aircraft/ships accordingly, effectively increasing/decreasing capacity on a line as per the actual
demand. This mod will greatly assist in addressing the tedious micro-management of bus/tram/aircraft/ship lines
when updating road/tram infrastructure, adding more destinations, and in general updating the overall passenger
transport network. The mod in fact completely eliminates the bus/tram/aircraft/ship passenger line
micro-management and will let you focus on the more fun overall design of the transport network.

Source code is located here: https://github.com/TommyC81/TPF2-LineManager.
Created by https://github.com/TommyC81 with contribution from https://github.com/RusteyBucket.
This mod is inspired by and uses some functionality from:
* TPF2-Timetables, created by Celmi, available here: https://steamcommunity.com/workshop/filedetails/?id=2408373260 and source https://github.com/IncredibleHannes/TPF2-Timetables
* Departure Board, created by kryfield, available here: https://steamcommunity.com/workshop/filedetails/?id=2692112427

## Information and options

* This mod can be added/removed to existing games as desired - it only measures load factor and demand and
  adds/removes vehicles on applicable lines accordingly. Only live data is used.
* This mod will by default automatically manage the number of vehicles on all passenger lines utilizing
  buses, trams, aircraft, or ships.
* Tested and sensible default rules are used to determine the number of required vehicles on a line.
  However, should this not work as desired, two options as per below are available to tweak the functionality:
* **(M) - MANUAL**: To disable automatic vehicle management on a specific line, add "**(M)**" to the name of
  the line (anywhere in the line name).
* **(R) - RATE****: To use alternative line rate rules for a specific line, adjusting number of
  vehicles strictly to ensure rate exceeds demand (this is more aggressive scaling, effectively ignoring
  load factor), add "***(R)**" to the name of the line (anywhere in the line name). Note that this
  is somewhat experimental and the rules may change, please provide feedback..

Examples of line naming:
* Line name "**BUS ABC-1**" - none of the specific syntax is used, this line will be automatically managed
  according to default rules.
* Line name "**BUS ABC-1 (M)**" - this line is **MANUALLY** managed (no automatic vehicle management).
* Line name "**BUS ABC-1 (R)**" - this line is managed according to alternative, and more aggressive,
  **(R) - RATE** line rules (disregarding load factor).

## Quick start

1. Create a bus line.
2. Add one bus to the bus line.
3. Make sure a depot is accessible for the bus on the bus line.
4. Make sure you have cash available for buying additional buses (when the mod determines it required).

## Quick tips for best results

* Only use one type of vehicle per line (this makes addition of new vehicles more predictable).
* If you need to update/upgrade vehicle type on a line, replace all vehicles at the same time (see above
  related item).
* Where appropriate, using a smaller vehicle size (less capacity per vehicle) allows better automatic
  fine-tuning of the line capacity.

## What the mod does

* The mod will add/remove i.e. buy/sell buses (of the same type as already utilized on the line) according to line
  utilization and demand, as money permits.
* When utilization (load factor over time) goes above/below different thresholds along with excessive/insufficient
  demand on the route, a vehicle will be added/removed accordingly.
* When a vehicle is sold, it will sell the oldest vehicle on the line. The mod will additionally ensure there is at
  least 1 vehicle remaining on the line.

## What the mod does NOT do

* This mod will not fix poorly designed transports networks. If you have a bus line that has highly uneven demand
  along the route, you will have to fix that yourself - there is no software that can fix this for you. If no vehicles
  are added despite a single station being overloaded along the route - it is probably a sign of poor route design,
  split the route up into evenly balanced (demand) sections.
* As an alternative to improving the route network, you can try using the alternative **(R) - RATE** line rules
  or **(M) - MANUAL** line management (see Information and and options above).

## Performance

* Every in-game month, the mod takes one usage, rate and demand sample per applicable line.
* Every second in-game month, the mod updates managed lines to add/remove vehicles as appropriate.
* Thus, performance impact should be negligible. This has not been studied in-depth, but no effect of the
  sampling/updates has been observed in games with hundreds of lines/buses/trams/aircraft/ships.

## Untested

* If a vehicle type is no longer available (outdated) when it is time to add/buy a bus - a silent failure is assumed.

## Future plans

* No specific plans, except making this stable and add coding improvements as time permits
  (this is also dependent on contribution from users).

## What you can do by mucking around in the mod file

* The `helper.lua` file contains much of the identification logic such as:
    * `helper.moreVehiclesConditions()` contains the rules that determine if there should be another vehicle added to a
      line.
    * `helper.lessVehiclesConditions()` contains the rules that determine if there are too many vehicles on a line.
    * `helper.supportedRoute()` contains the categories of vehicles supported by this mod (we're not entirely sure what
      number is what as of yet, though we're on it).
* The `linemanager.lua` file contains the execution functions that actually make things work. If you're determined, you
  can change stuff there.
    * Uncomment the line `log.setLevel(log.levels.DEBUG)` to avail additional in-game console debugging output by default.
    * A simple in-game menu is available; in the bottom bar of the game gui, look for `[LM]`. In this menu you can
      enable/disable *Debugging* and *Verbose Debugging* (additional information) as required.
* Any changes made to the code could obviously cause the game to crash on loading or on reaching the clause that breaks
  the code. Maybe even worse, who knows.

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
