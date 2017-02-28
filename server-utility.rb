require 'set'

#Keep from calculating analytics until all data is ready
$how_much_data = {} #eventcodes keyed to {match numbers keyed to integers}
#Any time matchscout or scorescout is received for a match, the counter increases
#And if the counter is at least 8, triggers analytics for all 6
def triggerAnalytics(eventcode, matchnumber)
	qualdata = JSON.parse(reqapi("schedule/#{eventcode}?tournamentLevel=qual"))
	qualiteams = qualdata['Schedule'].select{|key, hash| #search through the match hashes
		hash['matchNumber'] == matchnumber #if match number matches, select it
	}
	teams = []
	qualiteams['Teams'].each do |qualiteam|
		teams << qualiteam['number'] #get just the team numbers
	end
	teams.each do |team|
		analyzeTeamAtEvent(team, eventcode) #trigger analytics
	end
end

################################################
##############BEGIN FILE HANDLING###############
################################################

#Filename format:
#Eventcode_Objecttype_Teamnum.json
#Objecttype: Pit, TeamMatch, Match, ScoreScout
#Teamnum: The word "Team" followed by team number

def retrieveJSON(filename) #return JSON of a file
	txtfile = File.open(filename,'r')
	content = ''
	txtfile.each do |line|
		content << line
	end
	txtfile.close
	JSON.parse(content)
end

def saveEventsData(frcEvents)
	frcEvents.each do |event|
		filename = "public/Events/" + event.sEventCode + ".json"
        if(File.exist? filename)
            puts("Overwriting existing file #{filename}")
        else
            puts("Creating new file #{filename}")
        end
        jsonfile = File.open(filename,'w')
		jsonfile << event.to_json(options = {})
		jsonfile.close
		puts "Successfully saved " + filename
	end
end

def saveTeamMatchInfo(jsondata)
	jsondata = JSON.parse(jsondata)
	eventcode = jsondata['sEventCode']
	teamnumber = jsondata['iTeamNumber']
	matchnumber = jsondata['iMatchNumber']
	filename = "public/TeamMatches/"+eventcode+"_TeamMatch"+matchnumber.to_s+"_Team"+teamnumber.to_s+".json"
	jsonfile = File.open(filename,'w')
	jsonfile << jsondata.to_json #array of all MatchEvent objects into file. maybe?
	jsonfile.close

	#Triggering analytics:
	#If there is at least 8 data (6 match scouts 2 score scouts) analyze everything
	$how_much_data[eventcode] = {} unless $how_much_data[eventcode]
	$how_much_data[eventcode][matchnumber] = 0 unless $how_much_data[eventcode][matchnumber]
	$how_much_data[eventcode][matchnumber]++
	triggerAnalytics(eventcode, matchnumber) if $how_much_data[eventcode][matchnumber] >= 8

	#Possible extra task: compare existing json to saved json in case of double-saving
	puts "Successfully saved " + filename	
end

def saveTeamPitInfo(jsondata)
	jsondata = JSON.parse(jsondata)
	eventcode = jsondata['sEventCode']
	teamnumber = jsondata['iTeamNumber']
	filename = "public/Teams/#{teamnumber}/#{eventcode}_Pit_Team#{teamnumber}.json"
	
	#existingjson = '{}'
	#if File.exists? filename
	#	existingjson = retrieveJSON(filename)
	#end
	
	jsonfile = File.open(filename,'w')
	jsonfile << jsondata.to_json
	jsonfile.close
end

def saveScoreScoutInfo(jsondata)
	jsondata = JSON.parse(jsondata)
	eventcode = jsondata['sEventCode']
	matchnumber = jsondata['iMatchNumber']
	side = "Null"
	side = "Blue" if jsondata['bColor'] == true
	side = "Red" if jsondata['bColor'] == false
	filename = "public/Scores/#{eventcode}_Score#{matchnumber}_Side#{side}"
	jsonfile = File.open(filename,'w')
	jsonfile << jsondata.to_json
	jsonfile.close

	#Trigger analytics for all 6 teams if we have enough data
	$how_much_data[eventcode] = {} unless $how_much_data[eventcode]
	$how_much_data[eventcode][matchnumber] = 0 unless $how_much_data[eventcode][matchnumber]
	$how_much_data[eventcode][matchnumber]++
	triggerAnalytics(eventcode, matchnumber) if $how_much_data[eventcode][matchnumber] >= 8
end

def saveCalculateHeatMapData(eventcode, teamnumber, sortedevents, haccuracylist, laccuracylist, hloclist, lloclist)
	#Processing data
	gearMapPointList = makePointList(sortedevents['GEAR_SCORE'])
	lowGoalMapPointList = lloclist #instead of making a point list, we have to use a specific order to match float lists
	highGoalMapPointList = hloclist
	climbMapPointList = makePointList(sortedevents['CLIMB_SUCCESS']) + makePointList(sortedevents['CLIMB_FAIL'])
	hopperMapPointList = makePointList(soredevents['LOAD_HOPPER'])
	climbMapBoolList = []
	sortedevents['CLIMB_SUCCESS'].each do |matchevent|
		climbMapBoolList << true
	end
	sortedevents['CLIMB_FAIL'].each do |matchevent|
		climbMapBoolList << false
	end
	lowGoalMapFloatList, highGoalMapFloatList = laccuracylist, haccuracylist

	#Prepping data
	jsondata = {
		gearMapPointList: gearMapPointList,
		lowGoalMapFloatList: lowGoalMapFloatList,
		lowGoalMapPointList: lowGoalMapPointList,
		highGoalMapFloatList: highGoalMapFloatList,
		highGoalMapPointList: highGoalMapPointList,
		climbMapBoolList: climbMapBoolList,
		climbMapPointList: climbMapPointList,
		hopperMapPointList: hopperMapPointList
	}

	#Saving data
	filename = "public/Teams/#{teamnumber}/#{eventcode}_HeatMaps.json"
	jsonfile = File.open(filename,'w')
	jsonfile << jsondata
	jsonfile.close
end

def pickEightRandomScouts(eventcode, peopleresponsible)
	#eventcode is used as a seed for the pseudorandom number gen
	result = [] #eight unique scouts (peopleresponsible)
	numbers = Set.new #eight unique index
	return -1 if peopleresponsible.length < 8

	#Setup PRNG
	min = 0
	max = peopleresponsible.length - 1
	seed = 1
	eventcode.each_byte do |c|
		seed += c
	end
	prng = Random.new(seed)

	peopleresponsible.each_with_index do |person, index|
		if person.include? "!" && numbers.length > 7
			puts "A !priority scout has been detected. #{person} will be scouting every match."
			numbers.add(index)
		end
	end

	#Generate numbers
	while numbers.length < 8 do
		numbers.add(prng.rand(min..max))
	end
	numbers.each do |numbr|
		result << peopleresponsible[numbr]
	end

	return result
end

def saveCalculateScoutSchedule(jsondata, eventcode)
	#create a scout schedule, then save it
	qualscoutschedule = []
	scoutschedule = [] #ScheduleItems
	#sPersonResponsible, sItemType, sEventCod, iMatchNumber, iTeamNumber, iStationNumber, bColor

	#Data from post request
	jsondata = JSON.parse(jsondata)
	peopleresponsible = jsondata

	#Data from API
	qualdata = JSON.parse(reqapi("schedule/#{eventcode}?tournamentLevel=qual"))
	qualschedule = qualdata['Schedule']
	numquals = qualschedule.length
	numquals.times do |matchnum|
		currentmatch = qualschedule[matchnum]
		scouts = pickEightRandomScouts(eventcode, peopleresponsible)
		tempcounter = 0 #0 through 7 of scout
		scouts.each do |scout|
			scheduleitem = {
				sPersonResponsible: scout,
				sEventCode: eventcode,
				iMatchNumber: matchnum,
			}
			if tempcounter < 5
				currentteam = currentmatch['Teams'][tempcounter]
				scheduleitem['iTeamNumber'] = currentteam['number']
				station = currentteam['station']
				currentcolor, stationnumber = station[0, station.length-1], station[station.length-1, station.length]
				scheduleitem['iStationNumber'] = stationnumber.to_i
				scheduleitem['bColor'] = (currentcolor === "Blue" ? true : false) #blue is true
				scheduleitem['sItemType'] = 'matchscout'
			else
				scheduleitem['sItemType'] = 'scorescout'
				bColor = (tempcounter == 6 ? true : false)
			end
			tempcounter++
			scoutschedule << scheduleitem
		end
	end

	filename = "public/Events/#{eventcode}.json"
	jsondata = retrieveJSON(filename) #Read what was previously in the file
	jsondata['scheduleItemList'] = scoutschedule #Add to what was read in preparation for re-saving
	jsonfile = File.open(filename, 'w') #Wipes the file for writing
	jsonfile << jsondata #Re-writes the file
	jsonfile.close 
end

def getSimpleTeamList(eventcode)
	output = []
	tempjson = JSON.parse(reqapi('teams?eventCode=' + eventcode))
	tempjson['teams'].each do |team|
		output << SimpleTeam.new(team['nameShort'].to_s,team['teamNumber'].to_i).to_json
	end	
	output.to_json
end

def makePointList(matchevents = [])
	pointList = []
	matchevents = [] unless matchevents
	matchevents.each do |matchevent|
		pointList << matchevent['loc']
	end
end

################################################
##############BEGIN API RETRIEVAL###############
################################################

$scoresjson = {} #'CASJ': [{match},{match}]
$qualdetailsjson = {}
$playoffetailsjson = {}
$ranksjson = {}
#For all of these, format as {'CASJ': {}, 'ABCA': {}, etc}

def updateEventFromAPI(eventcode)
	#reqapi for all the latest data
	#then overwrite all data, in case a correction was made, as it's all the same call anyway
	#finally, return a success/failure message
	updateScores(eventcode)
	updateRanks(eventcode)
end

def updateScores(eventcode)
	puts "Begin update scores"
	matchresults = reqapi("matches/#{eventcode}",true) #Provides scores, teams
	puts "We got matches look #{matches}"
	#qualdetails = reqapi("scores/#{eventcode}/qual") 
	#playoffdetails = reqapi("scores/#{eventcode}/playoff") #Data sweet data! Subject to change.
	#puts "We got qualdetails look #{qualdetails}"
	$scoresjson["#{eventcode}"] = []
	matchresults["Matches"].each do |matchresult|
		$scoresjson["#{eventcode}"] << JSON.parse(matchresult)
	end
	#$qualdetailsjson[eventcode] = JSON.parse(qualdetails)
	#$playoffdetailsjson[eventcode] = JSON.parse(playoffdetails)
	
	#If-Modified-Since is very important here if we can implement it
	#So is the parameter start= for matches we already have

	#INCOMPLETE: This method cannot be finished until the 2017 API is complete
	$scoresjson["#{eventcode}"]
end

def getScores(eventcode)
	if $scoresjson["#{eventcode}"] #We already have scores
		return $scoresjson["#{eventcode}"]
	elsif updateScores("#{eventcode}") #No scores yet so we will update from API
		return $scoresjson["#{eventcode}"]
	else #No scores saved nor available on API
		return '{}'
	end
end

def updateRanks(eventcode)
	ranks = reqapi("rankings/#{eventcode}",true)
	$ranksjson["#{eventcode}"] = JSON.parse(ranks)
end

################################################
#############BEGIN RAWDATA SORTING##############
################################################

def sortMatchEvents(matchevents = [])
	#Receives an array of match events
	#Returns a hash of arrays of match events
	#sort using sEventName
	puts "Sort match events"
	sortedevents = {}
	autoevents = []
	matchevents.each do |matchevent|
		key = matchevent['sEventName']
		val = matchevent
		unless sortedevents[key]
			sortedevents[key] = [] #Initialize array to hold multiple matchevents
		end
		sortedevents[key] << val #Add matchevent to array
		puts "We now have #{key}: #{sortedevents[key]}"
		if val['bInAutonomous']
			autoevents << val
		end
	end
	sortedevents["AUTOSTUFF"] = autoevents if autoevents.length > 0 #Additional separate array to isolate autonomous
	sortedevents
	
	#sortedevents['GEAR_SCORE'] => [matchevent1, matchevent2, ...] etc
end

################################################
##############BEGIN FUEL GUESSING###############
################################################

def addSubscoreScout(data, arrayname, val, scorehash)
	data[arrayname].each do |ms|
		scorehash[ms] = 0 unless scorehash[ms]
		scorehash[ms] += val
	end
end

def scoreMatchEvents(sortedevents, scorehash)
	sortedevents.each do |eventarray|
		eventarray.each do |matchevent|
			timestamp = matchevent['iTimeStamp']
			scorehash[timestamp] = [] unless scorehash[timestamp]
			#Option 1: Define a hash at the top with the constants, and key matchevent names to score values
			#Option 2: Gigantic case switch, like in the main analytics method, in which accurate but longer calculations are made
			#So... efficiency? Or accuracy?
		end
	end
end

def getIncreaseOneTimeList(eventcode, matchnumber, matchcolor = true)
	filename = "public/Scores/#{eventcode}_Score#{matchnumber}_Side#{matchcolor}.json"
	scorescout = retrieveJSON(filename)
	return scorescout['increase1TimeList']
end

def analyzeScoreScouting(eventcode, matchnumber, matchcolor = true)
	#Prepare scorescouting for guessing fuel
	#Should return {'# milliseconds': score difference}
	#Lots of approximation, since 4 scouts will have different reaction times
	descrepancies = {}

	matchevents = [] #We need all the matchevents that happened in the match
	sortedmatchevents = {}
	Dir.glob("public/TeamMatches/#{eventcode}_TeamMatch#{matchnumber}_*.json") do |filename|
		tempjson = retrieveJSON(filename)
		break unless tempjson['bColor'] == matchcolor #blue is true
		
		if tempjson['MatchEvents']
			tempjson['MatchEvents'].each do |matchevent|
				matchevents << matchevent
			end
		end
	end
	sortedmatchevents = sortMatchEvents(matchevents)

	scorescout = '{}'
	side = "Null"
	side = "Blue" if matchcolor == true
	side = "Red" if matchcolor == false
	filename = "public/Scores/#{eventcode}_Score#{matchnumber}_Side#{side}.json"
	scorescout = retrieveJSON(filename)
	#bColor, increase(1,5,40,50,60)TimeList []

	#Time to calculate the differences.
	#Idea: do this like a simulation for a game
	#Each millisecond is a 'turn' and each event is a 'move'
	scoutedscore = 0
	matchscore = 0
	
	#Testing idea 1
	#combine them all into one big hash, with the points and timestamp?
	addscores = {} #points the scorescout says there are
	addSubscoreScout(scorescout, 'increase1TimeList', 1, addscores)
	addSubscoreScout(scorescout, 'increase5TimeList', 5, addscores)
	addSubscoreScout(scorescout, 'increase40TimeList', 40, addscores)
	addSubscoreScout(scorescout, 'increase50TimeList', 50, addscores)
	addSubscoreScout(scorescout, 'increase60TimeList', 60, addscores)
	addSubscoreScout(scorescout, 'decrease50TimeList', -50, addscores)

	nonfuel = {} #points the matchscouts say there are
	#ian stuff

	#order by time, add scouted scores, match scores,
	#difference for .. each second? each millisecond?
end