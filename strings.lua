function data()
  return {
    en = {
      Name = 'LineManager',
      Description = 'A mod to automatically manage the number of buses on bus lines.\n'
                 .. '\n'
                 .. 'Taking into account the loadfactor over time, and demand on the line, this mod will buy/sell buses accordingly.\n'
				 .. 'This mod will greatly assist in addressing the tedious micro-management of bus lines when updating road infrastructure, adding more destinations, and in general updating the overall transport network. The mod in fact completely eliminates the bus micro-management and will let you focus on the more fun overall design of the transport network.\n'
                 .. 'This mod can be added/removed to new and existing games as desired without issue.\n'
				 .. '\n'
				 .. 'Quick start:\n'
				 .. '1. Create a bus line.\n'
				 .. '2. Add one bus to the bus line.\n'
				 .. '3. Make sure a depot is accessible for the buses on the bus line.\n'
				 .. '4. Make sure you have cash available for buying buses (when the mod determines it required).\n'
				 .. '\n'
				 .. 'What the mod does:\n'
				 .. '* The mod will add/remove i.e. buy/sell buses of the same type according to line utilization and demand.\n'
				 .. '* When line utilization (loadfactor over time) goes above/below different thresholds along with sufficient/insufficient demand on the route, a line vehicle will be bought/sold accordingly.\n'
				 .. '* When a vehicle is sold, it will sell the oldest vehicle on the line. The mod will ensure there is at least 1 vehicle remaining on a line.\n'
				 .. '\n'
				 .. 'Troubleshooting and what the mod does NOT do:\n'
				 .. '* This mod will not fix poorly designed transports networks. If you have a bus line with highly uneven demand along the route, you will have to fix that yourself - there is no software that can fix this for you.\n'
				 .. '* If no vehicles are added despite a single station being overloaded along the route - it is probably a sign of poor route design, split the route up into evenly balanced (demand) segments i.e. split the existing line into 2 or more new lines with even demand.\n'
				 .. '\n'
				 .. 'Untested:\n'
				 .. '* If there is not enough cash available to add/buy a bus to a line - not sure what will happen, but assume a silent failure.\n'
				 .. '* If a vehicle type is no longer available (old) when it is time to add/buy a bus - not sure what will happen, but assume a silent failure.\n'
				 .. '\n'
				 .. 'Future plans:\n'
				 .. '* None, except making this stable and add some general coding improvements.\n'
				 .. '\n'
                 .. 'The source code can be found [url=https://github.com/TommyC81/TPF2-LineManager]here[/url].',
    }
  }
end