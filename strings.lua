function data()
  return {
    en = {
      Name = 'LineManager',
      Description = 'A mod to automatically manage the number of buses/trams on passenger lines.\n'
                 .. '\n'
                 .. 'Taking into account the load-factor over time, and demand on the line, this mod will buy/sell buses/trams accordingly, effectively increasing/decreasing capacity on a line as per the actual demand.\n'
				 .. 'This mod will greatly assist in addressing the tedious micro-management of bus/tram lines when updating road/tram infrastructure, adding more destinations, and in general updating the overall transport network. The mod in fact completely eliminates the bus/tram micro-management and will let you focus on the more fun overall design of the transport network.\n'
                 .. 'This mod can be added/removed to new and existing games as desired without issue.\n'
				 .. '\n'
				 .. 'Quick start:\n'
				 .. '1. Create a bus/tram line.\n'
				 .. '2. Add one bus/tram to the bus/tram line.\n'
				 .. '3. Make sure a depot is accessible for the bus/tram on the line.\n'
				 .. '4. Make sure you have cash available for buying further buses/trams (when the mod determines it required).\n'
				 .. '\n'
				 .. 'What the mod does:\n'
				 .. '* The mod will add/remove i.e. buy/sell buses/trams of the same type according to line utilization and demand.\n'
				 .. '* When line utilization (load-factor over time) goes above/below different thresholds along with sufficient/insufficient demand on the route, a line vehicle will be bought/sold accordingly.\n'
				 .. '* When a vehicle is sold, it will sell the oldest vehicle on the line. The mod will ensure there is at least 1 vehicle remaining on a line.\n'
				 .. '\n'
				 .. 'Troubleshooting and what the mod does NOT do:\n'
				 .. '* This mod will not fix poorly designed transports networks. If you have a bus/tram line with highly uneven demand along the route, you will have to fix that yourself - there is no software that can fix this for you.\n'
				 .. '* If no vehicles are added despite a single station being overloaded along the route - it is probably a sign of poor route design, split the route up into evenly balanced (demand) segments i.e. split the existing line into 2 or more new lines with even demand.\n'
				 .. '\n'
				 .. 'Performance:\n'
				 .. '* The mod takes one usage, rate and demand sample per line per in-game month.\n'
				 .. '* Every second in-game month, lines are updated to add/remove vehicles as appropriate.\n'
				 .. '* Thus, performance impact should be negligble. This has not been studied in-depth, but no effect of the sampling/updates has been observed in games with hundreds of lines/buses/trams.\n'
				 .. '\n'
				 .. 'Untested:\n'
				 .. '* If there is not enough cash available to add/buy a bus/tram to a line - not sure what will happen, but assume a silent failure.\n'
				 .. '* If a vehicle type is no longer available (old) when it is time to add/buy a bus/tram - not sure what will happen, but assume a silent failure.\n'
				 .. '\n'
				 .. 'Future plans:\n'
				 .. '* None, except making this stable and add some general coding improvements.\n'
				 .. '\n'
                 .. 'The source code can be found [url=https://github.com/TommyC81/TPF2-LineManager]here[/url].',
    }
  }
end