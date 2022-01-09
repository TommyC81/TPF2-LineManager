function data()
  return {
    en = {
      Name = 'LineManager',
      Description = '[h1]A mod to automatically manage the number of buses/trams/aircraft/ships on passenger lines[/h1]\n' ..
                    '[hr]\n' ..
                    'Taking into account the load-factor over time, and line demand and rate, this mod will buy/sell buses/trams/aircraft/ships accordingly, effectively increasing/decreasing capacity on a line as per the actual demand.\n' ..
                    'This mod will greatly assist in addressing the tedious micro-management of bus/tram/aircraft/ship lines when updating road/tram infrastructure, adding more destinations, and in general updating the overall transport network. The mod in fact completely eliminates the bus/tram/aircraft/ship micro-management and will let you focus on the more fun overall design of the transport network.\n' ..
                    '[hr]\n' ..
                    '[h1]Information and options[/h1]\n' ..
                    '[list]\n' ..
                    '[*]This mod can be added/removed to existing games as desired - it only measures load factor, rate, and demand, adding/removing vehicles on applicable lines accordingly. Only live data is used.\n' ..
                    '[*]This mod will by default automatically manage the number of vehicles on [u]all passenger lines utilizing buses, trams, aircraft, or ships[/u].\n' ..
                    '[*]Tested and sensible default rules are used to determine the number of required vehicles on a line. However, should this not work as desired, two options as per below are available to tweak the functionality:\n' ..
                    '[*][b](M) - MANUAL[/b]: To [u]disable automatic vehicle management[/u] on a specific line, add "[b](M)[/b]" to the name of the line (anywhere in the line name).\n' ..
                    '[*][b](R) - RATE[/b]: To use [u]line rate rules[/u] for a specific line, adjusting number of vehicles strictly to ensure line rate exceeds demand (this is more aggressive scaling, effectively ignoring load factor), add "[b](R)[/b]" to the name of the line (anywhere in the line name). [i]Note that this is somewhat experimental and the rules may change, please provide feedback.[/i]\n' ..
                    '[*][b](RC) - CONSERVATIVE RATE[/b]: To use [u]conservative line rate rules[/u] for a specific line, increasing number of vehicles to as close as possible match line rate to demand, whilst using default rules to reduce vehicles. [i]Note that this is somewhat experimental and the rules may change, please provide feedback.[/i]\n' ..
                    '[*][b](T) - TEST[/b]: To use [u]test rate rules[/u] for a specific line, dynamically comparing usage vs rate/demand ratio to scale up/down the number of vehicles. [i]Note that this is somewhat experimental and the rules may change, please provide feedback.[/i]\n' ..
                    '[/list]\n' ..
                    '\n' ..
                    'Examples of line naming:\n' ..
                    '[list]\n' ..
                    '[*]Line name "[b]BUS ABC-1[/b]" - none of the specific syntax is used, this line will be automatically managed according to default rules.\n' ..
                    '[*]Line name "[b]BUS ABC-1 [u](M)[/u][/b]" - this line is [b]MANUALLY[/b] managed (no automatic vehicle management).\n' ..
                    '[*]Line name "[b]BUS ABC-1 [u](R)[/u][/b]" - this line is managed according to [b](R) - RATE[/b] line rules.\n' ..
                    '[*]Line name "[b]BUS ABC-1 [u](RC)[/u][/b]" - this line is managed according to [b](RC) - CONSERVATIVE RATE[/b] line rules.\n' ..
                    '[*]Line name "[b]BUS ABC-1 [u](T)[/u][/b]" - this line is managed according to [b](T) - TEST[/b] line rules.\n' ..
                    '[/list]\n' ..
                    '\n' ..
                    '[hr]\n' ..
                    '[h1]Quick start[/h1]\n' ..
                    '[olist]\n' ..
                    '[*]Create a bus line.\n' ..
                    '[*]Add one bus to the bus line.\n' ..
                    '[*]Make sure a depot is accessible for the bus on the bus line.\n' ..
                    '[*]Make sure you have cash available for buying additional buses (when the mod determines it required).\n' ..
                    '[/olist]\n' ..
                    '\n' ..
                    '[h1]Quick tips for best results[/h1]\n' ..
                    '[list]\n' ..
                    '[*]Only use one type of vehicle per line (this makes addition of new vehicles more predictable).\n' ..
                    '[*]If you need to update/upgrade vehicle type on a line, replace all vehicles at the same time (see above related item).\n' ..
                    '[*]Where appropriate, using a smaller vehicle size (less capacity per vehicle) allows better automatic fine-tuning of the line capacity.\n' ..
                    '[*]Having depots available close to automatically managed lines will speed up capacity increase when required.\n' ..
                    '[/list]\n' ..
                    '\n' ..
                    '[h1]What the mod does[/h1]\n' ..
                    '[list]\n' ..
                    '[*]The mod will add/remove i.e. buy/sell buses (of the same type as already utilized on the line) according to line utilization and demand, as money permits.\n' ..
                    '[*]When utilization (load factor over time) goes above/below different thresholds along with excessive/insufficient demand on the route, a vehicle will be added/removed accordingly.\n' ..
                    '[*]When a vehicle is sold, it will sell the oldest vehicle on the line. The mod will additionally ensure there is at least 1 vehicle remaining on the line.\n' ..
                    '[/list]\n' ..
                    '\n' ..
                    '[h1]What the mod does [u]NOT[/u] do[/h1]\n' ..
                    '[list]\n' ..
                    '[*]This mod will not fix poorly designed transports networks. If you have a bus line that has highly uneven demand along the route, you will have to fix that yourself - there is no software that can fix this for you. If no vehicles are added despite a single station being overloaded along the route - it is probably a sign of poor route design, split the route up into evenly balanced (demand) sections.\n' ..
                    '[*]As an alternative to improving the route network, you can try using the alternative [b](R) - RATE[/b] line rules, [b](RC) - CONSERVATIVE RATE[/b] line rules, [b](T) - TEST[/b] line rules, or [b](M) - MANUAL[/b] line management (see Information and and options above).\n' ..
                    '[/list]\n' ..
                    '\n' ..
                    '[h1]Performance[/h1]\n' ..
                    '[list]\n' ..
                    '[*]Every in-game month, the mod takes one usage, rate and demand sample per applicable line.\n' ..
                    '[*]Every second in-game month, the mod updates managed lines to add/remove vehicles as appropriate.\n' ..
                    '[*]Thus, performance impact should be negligible. This has not been studied in-depth, but no effect of the sampling/updates has been observed in games with hundreds of lines/buses/trams/aircraft/ships.\n' ..
                    '[/list]\n' ..
                    '\n' ..
                    '[h1]Untested[/h1]\n' ..
                    '[list]\n' ..
                    '[*]If a vehicle type is no longer available (outdated) when it is time to add/buy a bus - a silent failure is assumed.\n' ..
                    '[/list]\n' ..
                    '\n' ..
                    '[h1]Future plans[/h1]\n' ..
                    '[list]\n' ..
                    '[*]No specific plans, except making this stable and add coding improvements as time permits (this is also dependent on contribution from users).\n' ..
                    '[/list]\n' ..
                    '\n' ..
                    '[h1]Code[/h1]' ..
                    'Source code and further information is available on the [url=https://github.com/TommyC81/TPF2-LineManager]GitHub repository[/url].\n' ..
                    'Mod created by [url=https://github.com/TommyC81]TommyC81[/url] with contribution from [url=https://github.com/RusteyBucket]RusteyBucket[/url].\n' ..
                    'This mod is inspired by and uses some functionality from:\n',
                    '[list]\n' ..
                    '[*][url=https://steamcommunity.com/workshop/filedetails/?id=2408373260]TPF2-Timetables (Steam Workshop)[/url] created by Celmi. Source code available on [url=https://github.com/IncredibleHannes/TPF2-Timetables]GitHub[/url].',
                    '[*][url=https://steamcommunity.com/workshop/filedetails/?id=2692112427]Departure Board (Steam Workshop)[/url] created by kryfield.',
                    '[/list]\n',
    },
  }
end
