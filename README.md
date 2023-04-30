# TPF2-LineManager

A mod for Transport Fever 2 to automatically manage the number of vehicles on lines.

Steam Workshop link: [https://steamcommunity.com/workshop/filedetails/?id=2581894757]

Taking into account usage, demand, rate, frequency, capacity, and other factors, this mod will automatically
add/remove vehicles to lines according to configurable rules (comes with sensible default rules out-of-the-box).
This mod will greatly assist in reducing/eliminating vehicle micro management, and will let you focus on
the overall design of your transport network(s) instead.

Source code and manual is located here: [https://github.com/TommyC81/TPF2-LineManager], any issues should be raised on GitHub.
Created by [https://github.com/TommyC81] with contribution from [https://github.com/RusteyBucket].
This mod uses:

* [https://github.com/rxi/lume] created by [https://github.com/rxi], with additional updates made by [https://github.com/idbrii]
  available on [https://github.com/idbrii/lua-lume]

This mod is inspired by and uses code snippets from:

* TPF2-Timetables, created by Celmi, available here: [https://steamcommunity.com/workshop/filedetails/?id=2408373260]
  and source [https://github.com/IncredibleHannes/TPF2-Timetables]
* Departure Board, created by kryfield, available here: [https://steamcommunity.com/workshop/filedetails/?id=2692112427]

## Information and options

### General information

* This mod can be added/removed to existing games as desired - it only measures live data and
  adds/removes vehicles on applicable lines accordingly.
* This mod will by default automatically manage the number of vehicles on all PASSENGER and CARGO lines utilizing
  trucks/buses, trams, aircraft, trains, and ships.
* When adding a vehicle to a line, an existing vehicle is (effectively) cloned. There is no evaluation of which vehicle
  will be cloned, so it is therefore recommended to keep a single type of vehicle per line.
* When removing a vehicle from a line, if there are empty vehicles on the line then the oldest of the empty vehicle will be removed,
  otherwise the oldest vehicle of all vehicles on the line will be removed regardless if it has cargo.
  Additionally, the mod will ensure at least 1 vehicle remains on each line, unless rule `[X]` is used.
* Sensible rules for both PASSENGER and CARGO lines are used by default (if automatic vehicle management is enabled for the
  respective category of lines). However, if this doesn't work as desired, see the "Line rules" section below for more information.
* The mod is primarily tested with lines running with "Load if available" station settings i.e. free-running lines. Although good
  results have been reported for other types of line/station settings, results could vary.
* Using any other in-game date progression (date speed) than 1x is _EXPERIMENTAL_ - it is likely that things will break in some way
  or simply not work as expected. Suggest to avoid this unless you know what you are doing and like to figure things out
  including digging into the code (including rules.lua) to tweak things.

### In-game menu

The mod has in in-game menu, that can be accessed via the "[LM]" text in the bottom in-game status bar.
The following LineManager options area available in the in-game menu:

* **LineManager enabled** - Enables/disables processing of the mod.
* **Congestion control** - Enables/disables congestion control features. This will stop the automatic addition of vehicles
  to lines when congestion is detected. In case of extreme congestion, this feature will also remove vehicles to unclog
  the congestion.
* **Automatically reverse trains with no path** - When adding trains, the depot finding can sometimes cause a train to
  be unable to find a path (in simple terms). The manual solution of this is to select the train and reverse it
  once or twice to re-trigger route/path finding. But instead of doing it manually, the mod can do it for you automatically!
* **Use OS time based sampling** - By default, a sample/update is triggered when in-game month changes. This spreads
  sampling/updates out in a reasonable way to collect sensible line data, regardless of in-game speed. However, if you,
  for instance, use a mod that freezes game time, then you can select this option - updates will then be triggered
  at regular intervals, around every 30 seconds. NOTE: Using any other in-game date progression (date speed) than 1x is _EXPERIMENTAL_.
* **PASSENGER/CARGO - ROAD/TRAM/RAIL/WATER/AIR** - Enables/disables automatic line vehicle management for an entire
  category. Select as desired. By default, automatic line vehicle management is enabled for everything.
* **Debugging** - Enables/disables additional debugging output in the in-game console.
* **Show extended line info** - Enables/disables additional line information output in the in-game console. This currently
  shows which lines that are either Manually (i.e. line rule set in the line name), Automatically (i.e. management of a category
  of lines enabled, and no manual rule has been assigned for the lines), or Ignored (i.e. lines for which neither a manual rule
  has been set nor automatic management enabled for the line category).
* **Force Sample** - Triggers a sampling to begin immediately, including associated update. Restarts an ongoing sampling
  if already in progress.
* **Show notification window** - This will show the LINEMANAGER NOTIFICATION window. This window is otherwise
  only shown on the first run of a game with LineManager in use, or after a significant LineManager update.

### Line rules

* **`[P]` - PASSENGER**: Default PASSENGER line rule, assigned automatically to all managed PASSENGER lines.
  To assign manually, add `[P]` to the name of the line (anywhere in the line name).
* **`[C]` - CARGO**: Default CARGO line rule, assigned automatically to all managed CARGO lines.
  To assign manually, add `[C]` to the name of the line (anywhere in the line name).
* **`[M]` - MANUAL**: To disable automatic vehicle management on a specific line, add `[M]` to the name of
  the line (anywhere in the line name). LineManager will not amend any vehicles on this line.
* **`[R:<number>]` - RATE**: Line rate rules, adjusting number of vehicles to ensure line rate meets/exceeds the set rate.
  To use, add `[R:xxx]` to the name of the line (anywhere in the line name). Note that xxx is to be replaced with the
  desired rate. You can optionally add a second parameter by adding an additional number separate by a colon, this
  second parameter specifies an acceptable station overload in % relative to the average capacity per vehicle servicing the line.
  This allows capacity to grow upwards in case a station load exceeds this parameter, capacity will however never be reduced
  below the set rate.
* **`[PR]` - PASSENGER (RusteyBucket)**: Alternative PASSENGER line rules created by RusteyBucket. These rules will more
  aggressively manage vehicles upwards. This can be useful for unevenly balanced passenger lines. Perhaps a line feeding a
  main route and it is acceptable that it runs less optimally to ensure the main route has maximum/optimal load. To use,
  add `[PR]` to the name of the line (anywhere in the line name).
* **`[X]` - REMOVE**: Used to dis-establish a line. Vehicles will no longer be added, and all empty vehicles will be removed.
  For this to function optimally, also manually amend the line to prevent loading of new cargo.

Note 1: If multiple rules have been added to a line, only the first one will be processed.
Note 2: The default [P] and [C] rules will try to maintain a maximum interval of 12 minutes. I.e. if the line is long and
there are insufficient vehicles on the line to maintain a maximum interval of 12 minutes, then more vehicles will be added.

Examples of line naming:

* Line name `BUS ABC-1` - none of the specific syntax is used, this line will be automatically managed with default rules.
  If automatic management has been enabled for the type of line.
* Line name `BUS ABC-1 [P]` - this line is managed according to default **(P) - PASSENGER** line rules.
* Line name `BUS ABC-1 [PR]` - this line is managed according to **(PR) - PASSENGER (RusteyBucket)** line rules.
* Line name `BUS ABC-1 [M]` - this line is **MANUALLY** managed (no automatic vehicle management).
* Line name `TRUCK ABC-1 [C]` - this line is managed according to default **(C) - CARGO** line rules.
* Line name `TRUCK ABC-1 [R:100]` - this line is managed according to **(R) - RATE** line rules, to achieve a rate of 100.
* Line name `TRUCK ABC-1 [R:100:200]` - this line is managed according to **(R) - RATE** line rules, to achieve a rate of 100.
  Additionally, a second (and optional) parameter specifies that capacity should be increased in case a station load exceeds
  200% of the average capacity per vehicle on the line.
* Line name `TRUCK ABC-1 [M]` - this line is **MANUALLY** managed (no automatic vehicle management).

Other ways to manage vehicles is to disable automatic management of some line categories (or all) and only
assign rules manually where needed. Manually assigned rules are always processed, regardless of the automatic setting.

Additionally, you can (relatively) easily dig into the code and create your own rules, see 'rules.lua' within the source code.

## Quick start

1. Create a bus line.
2. Add one bus to the bus line.
3. Make sure a depot is accessible for the bus on the bus line.
4. Make sure you have cash available for buying additional buses (when the mod determines it required).

## Quick tips for best results

* In the early game, it's a good idea to manage lines manually i.e. assign rules manually where required, and avoid automatic
  line management for categories of lines. In general limit the use of LineManager to keep track of your money. Once the number
  of lines and vehicles start has increased to become time consuming, then start enabling LineManager for different line
  categories. At this point you likely have enough money to not rely on very careful and individual decisions on when/where
  to expand/optimize your transport network.
* Only use one type of vehicle per line (this makes addition of new vehicles more predictable).
* Don't mix PASSENGER and CARGO on the same line. Although it may work, results will most likely not be optimal.
* If you need to update/upgrade vehicle type on a line, replace all vehicles at the same time (see above
  related item).
* Using a smaller vehicle size (less capacity per vehicle) can allow for better automatic fine-tuning of the line capacity.
  For instance; truck/bus lines are relatively easy to manage as adding/removing a vehicle only achieves small changes to capacity.
  Whereas lines with large trains with big capacities will change capacity significantly when adding or removing a vehicle - the latter
  can cause oscillations over time as capacity gets adjusted up and down whilst the optimal is somewhere between. Consider managing
  tricky lines manually (`[M]`), use rate rule (`[R:xxx]`),  or make use of smaller trains to more easily optimize the line.
* Even though LineManager is managing a lines vehicles, you can still manually buy/sell vehicles to accelerate known required
  vehicle adjustments. For instance, when starting a new line, you may want to buy some "starting" vehicles (at least 1 vehicle
  is required for LineManager to work at all), and then let LineManager adjust from there - when adding "starting" vehicles,
  consider adding only about half the vehicles you think are needed to avoid some initial vehicle number oscillations.
* Avoid using "WAIT FOR FULL LOAD" stops for managed lines, this will potentially disrupt data and calculations and lead to
  less than ideal results. Use **`[M]` - MANUAL** line management (see Information and and options above) if required.
* Make sure depots are readily available and accessible (from all directions) to ensure depots can be located and new vehicles added.
  Without accessible depots, no new vehicles.
* LineManager produces lots of informative console messages, learn how to enable the in-game console and check the messages.
  It is very likely that for whatever issue you may experience, the cause/solution is captured in the console output.

## What the mod does

* The mod will add/remove vehicles (of the same type as already utilized on the line) according to rules, as money permits.
* When rule criteria are met, a vehicle will be added/removed accordingly to each managed line.
* When a vehicle is sold, it will sell the oldest vehicle on the line.
* The mod will additionally ensure there is at least 1 vehicle remaining on the line.

## What the mod does NOT do

* This mod will not fix poorly designed transports networks. For instance, if you have a PASSENGER line that has highly
  uneven demand along the route, you will have to fix that yourself - there is no software that can fix this for you.
  If no vehicles are added despite a single station being overloaded along the route - it is probably a sign of poor
  route design, split the route up into evenly balanced (demand) sections.
* To optimize efficiency and your intended outcome, or as an alternative to improving the route network, you can manually
  set and use the available line rules or **`[M]` - MANUAL** line management (see Information and and options above).

## Performance

* Every in-game month (or time period), the mod takes a sample followed by an update.
* Workload associated with processing the sample is spread out over several game ticks.
* Once a sampling run is completed, any identified ADD/REMOVE actions are executed on the line.
* Thus, performance impact should be minimal. This has not been studied in-depth, but no noticeable impact of the
  sampling/updates has been observed in games with hundreds of lines/buses/trams/aircraft/ships/trains.

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

### Bounty hunt

These items are of specific interest to resolve, any guidance would be greatly appreciated and will ensure your name forever
captured in the credits! :)

* Find a suitable depot for a line (without using current workaround - send an existing line vehicle to depot, then use that
  depot when adding more vehicles).
* Get cost estimate for new vehicle before purchasing it (this will help avoiding interfering with lines when cost for new
  vehicles is more than can be afforded or preferred).
* Extensively test and adapt for usage with date speed other than 1x.

### Recommended tools

* **GitHub account** (sign up for a free account here: <https://github.com/>)
* **Github Desktop** (free, also requires a free GitHub account: <https://desktop.github.com/>)
* **Visual Studio Code** (free, <https://code.visualstudio.com/>), with the following free extensions
  * **Lua** (by sumneko, link: <https://marketplace.visualstudio.com/items?itemName=sumneko.lua>)
  * **vscode-lua-format** (by Koihik, link: <https://marketplace.visualstudio.com/items?itemName=Koihik.vscode-lua-format>)
  * **GitLens - Git supercharged** (by GitKraken, link: <https://marketplace.visualstudio.com/items?itemName=eamodio.gitlens>)
  * **Code Spell Checker** (by Street Side Software, link: <https://marketplace.visualstudio.com/items?itemName=streetsidesoftware.code-spell-checker>)
  * **markdownlint** (by David Anson, link: <https://marketplace.visualstudio.com/items?itemName=DavidAnson.vscode-markdownlint>)
* **CommonApi2** (by eis_os, link: <https://www.transportfever.net/filebase/index.php?entry/4806-commonapi2/>, Steam: <https://steamcommunity.com/sharedfiles/filedetails/?id=1947572332>)
