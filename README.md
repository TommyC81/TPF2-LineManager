# TPF2-LineManager
 A mod for Transport Fever 2 to automatically manage the number of vehicles on bus lines in accordance with load factor and demand.
 GitHub repository is located here: https://github.com/TommyC81/TPF2-LineManager.
 Inspired by and uses some functionality from https://github.com/IncredibleHannes/TPF2-Timetables.

This mod can be added/removed to existing games as desired - it only measures load factor and demand and adds/removes vehicles on bus lines accordingly. Only live data is used.
 
## Quick start
 1. Create a bus line.
 2. Add one bus to the bus line.
 3. Make sure a depot is accessible for the buses on the bus line
 4. Make sure you have cash available for buying buses (when the mod determines it required).

## What the mod does
 * The mod will add/remove i.e. buy/sell buses of the same type according to line utilization and demand.
 * When utilization (loadfactor over time) goes above/below different thresholds along with sufficient/insufficient demand on the route, a vehicle will be added/removed accordingly.

## What the mod does NOT do
 * This mod won't fix poorly designed transports networks. If you have a bus line that has highly uneven demand along the route, you'll have to fix that yourself - there's no software that can fix this for you. If no vehicles are added despite a single station being overloaded along the route - it is probably a sign of poor route design, split the route up into evenly balanced (demand) sections.
 
## Untested
 * If there's not enough cash available to add/buy a bus to a line - I'm not sure what will happen, but assume a silent failure.
 * If a vehicle type is no longer available (old) when it's time to add/buy a bus - I'm not sure what will happen, but assume a silent failure.

## Future plans
 * None, except making this stable and add some general coding improvements.