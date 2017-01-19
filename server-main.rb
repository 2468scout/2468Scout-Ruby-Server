#set SSL_CERT_FILE=D:/ScoutAppServer/2468Scout-Python-Server/human/cacert.pem

################################################
################TABLE OF CONTENTS###############
################################################
# Initialization
# Class Definition
# Request Handling
# Number Crunching
# Analytics


################################################
##############BEGIN INITIALIZATION##############
################################################

#Gems (imports) the server needs
require 'sinatra' #Web server
require 'json'    #Send & receive JSON data
require 'open-uri'#Wrapper for Net::HTTP (interact with FRC API and client)
require 'uri'     #Uniform Resource Identifiers (interact with FRC API and client)
require 'openssl' #Not sure if we need this but we've been having some SSL awkwardness

set :bind, '0.0.0.0' #localhost
set :port, 8080   #DO NOT CHANGE without coordination w/client

Dir.mkdir 'public' unless File.exists? 'public' #Sinatra will be weird otherwise
Dir.mkdir 'public/data' unless File.exists? 'public/data' #Data is to be gitignored. The server will have to create a folder for itself.

$server = 'https://frc-api.firstinspires.org/v2.0/'+Time.now.year.to_s+'/' #Provides matches, events for us.. put -staging after "frc" for practice matches
$token = open('human/apitoken.txt').read #Auth token from installation
$requests = {} #Requests from our server to the API

#OpenSSL::SSL::VERIFY_PEER = OpenSSL::SSL::VERIFY_NONE

def api(path) #Returns the FRC API file for the specified path in JSON format.
  begin
  	puts "I am accessing the API at path #{path}"
    open("#{$server}#{path}", #https://frc-api. ... .org/v.2.0/ ... /the thing we want
      "User-Agent" => "https://github.com/2468scout/2468Scout-Ruby-Server", #Dunno what this is but Isaac did it
      "Authorization" => "Basic #{$token}", #Standard procedure outlined by their API
      "accept" => "application/json" #We want JSON files, so we will ask for JSON
    ).read
  rescue => e
  	puts "Something went wrong #{e.class}, message is #{e.message}"
    return '{}' #If error, return empty JSON-ish.
  end
end

def reqapi(path) #Make sure we don't ask for the same thing too often
	begin
    	req = path
    	if $requests[req] && ($requests[req][:time] + 120 > Time.now.to_f) 
    	  $requests[req][:data] #we requested the same thing within 2 minutes
    	else
    	  $requests[req] = {
    	    data: api(req),
    	    time: Time.now.to_f
    	  }
    	  $requests[req][:data] #new request so we make a new one and return its data
    	end
  	rescue
    	#status 404
    	return '{}'
  	end
end

$events = reqapi('events/') #Get all the events from the API so we don't have to keep bothering them

#OPTIONAL PROJECT FOR LATER:
#use eventcodes matrix to verify that a user-submitted event code is valid
#$eventcodes = []
#$events.each do |event|
#	$eventcodes << event['code']
#end


################################################
#############BEGIN CLASS DEFINITION#############
################################################

class FRCEvent #one for each event
	def initialize(eventName, eventCode, tNameList, tMatchList, mList, namesByMatchList)
		@sEventName = eventName #the long name of the event
		@sEventCode = eventCode #the event code
		@teamNameList = tNameList #array of all teams attending
		@teamMatchList = tMatchList #array of all TeamMatch objects, 6 per match
		@matchList = mList #array of all Match objects containing score, rp, some sht
		@listNamesByTeamMatch = namesByMatchList
	end
	def to_json
		{'sEventName' => @sEventName, 'sEventCode' => @sEventCode, 'teamNameList' => @teamNameList, 'teamMatchList' => @teamMatchList, 'matchList' => @matchList, 'listNamesByTeamMatch' => @listNamesByTeamMatch}
	end
end

class Match #one for each match in an event
	#ian wants us to check scores for every single match in the API every 5 minutes... that's gonna be a (very) low-priority task
	def initialize(matchNum, redMP, blueMP, redRP, blueRP, complevel, eventCode, tMatchList)
		@iMatchNumber = matchNum #match ID
		@iRedScore = redMP #points earned by red (from API)
		@iBlueScore = blueMP #points earned by blue (from API)
		@iRedRankingPoints = redRP #ranking points earned by red (from API)
		@iBlueRankingPoints = blueRP #ranking points earned by blue (from API)
		@sCompetitionLevel = complevel #the event.. level??? ffs thats a different api call entirely
		@sEventCode = eventCode #the event code
		@teamMatchList = tMatchList #array of 6 TeamMatch objects
	end
	def to_json
		{'iMatchNumber' => @iMatchNumber, 'iRedScore' => @iRedScore, 'iBlueScore' => @iBlueScore, 'iRedRankingPoints' => @iRedRankingPoints, 'iBlueRankingPoints' => @iBlueRankingPoints, 'sCompetitionLevel' => @sCompetitionLevel, 'sEventCode' => @sEventCode, 'teamMatchList' => @teamMatchList}
	end
end

class Team #one for each team .. ever
	def initialize(teamName, teamNum, awardsArray, gearspermatch, highpermatch, lowpermatch, avgrp)
		@sTeamName = teamName
		@iTeamNumber = teamNum
		@awardsList = awardsArray
		@avgGearsPerMatch = gearspermatch
		@avgHighFuelPerMatch = highpermatch
		@avgLowFuelPerMatch = lowpermatch
		@avgRankingPoints = avgrp
	end
	def to_json
		{'sTeamName' => @sTeamName, 'iTeamNumber' => @iTeamNumber, 'awardsList' => @awardsList, 'avgGearsPerMatch' => @avgGearsPerMatch, 'avgHighFuelPerMatch' => @avgHighFuelPerMatch, 'avgLowFuelPerMatch' => @avgLowFuelPerMatch, 'avgRankingPoints' => @avgRankingPoints}.to_json
	end
end

class MatchEvent #many per match
	def initialize(timStamp, pointVal, cnt, isauto, eventname, location)
		@iTimeStamp = timStamp #how much time
		@iPointValue = pointVal #how many point earned
		@iCount = cnt #how many time
		@bInAutonomous = isauto #happened in autonomous yes/no
		@sEventName = eventName #wtf why do we need an event name for every single piece of a match
		@loc = location #Point object
	end
	def to_json
		{'iTimeStamp' => @iTimeStamp, 'iPointValue' => @iPointValue, 'iCount' => @iCount, 'bInAutonomous' => @bInAutonomous, 'sEventName' => @sEventName, 'loc' => @loc}.to_json
	end
end

class Point
	def initialize(myx, myy)
		@x = myx
		@y = myy
	end
	def to_json
		{'x' => @x, 'y' => @y}.to_json
	end
end

class SimpleTeam
	def initialize(teamname, teamnumber)
		@sTeamName = teamname
		@iTeamNumber = teamnumber
	end
	def to_json
		{'sTeamName' => @sTeamName, 'iTeamNumber' => @iTeamNumber}.to_json
	end
end


################################################
#############BEGIN REQUEST HANDLING#############
################################################
#GET - Client requests data from a specified resource
#POST - Client submits data to be processed to a specified resource
#request.body - where the JSON things are

###GET REQUESTS

get '/getevents' do #Return a JSON of the events we got directly from the API, as well as an identifier
	content_type :json
 	$events
end

get '/getsimpleteamlist' do
	output = []
	tempeventcode = params['eventCode']
	tempjson = JSON.parse(reqapi('teams?eventCode=' + tempeventcode))
	tempjson['teams'].each do |team|
		output << SimpleTeam.new(team['nameShort'].to_s,team['teamNumber'].to_i).to_json
	end	
	content_type :json
	output.to_json
end

get '/getmatchlist' do
	content_type :json
	'{"test":"Success"}'
end

get '/getTeamMatch' do #Return a JSON of match data for a particular team?? (idk.. Ian vult)
	puts "I got a get request"
	begin
		content_type :json
		eventcode = params['eventCode']
		teamnumber = params['teamNumber']
		matchnumber = params['matchNumber']
		filename = "public/data/"+eventcode+"_Match"+matchnumber.to_s+"_Team"+teamnumber.to_s+".json"
		retrieveJSON(filename)
	rescue => e
		puts e
		status 400
		return '{}'
	end	
end

###POST REQUESTS

post '/postpit' do #Pit scouting (receive team data) #input is an actual string
	begin
  		#Congration u done it
  		testvar = params['test']
  		puts testvar
    	status 200
	rescue => e
    	puts e
    	status 400
	end
end

post '/postTeamMatch' do #eventcode, teamnuber, matchnumber, all matchevents
	begin
  		saveTeamMatchInfo(request.body)
  		#EXPERIMENTAL: saveMatchInfo(??) for simulations
		status 200
	rescue => e
		puts e
		status 400
	end
end


################################################
#############BEGIN NUMBER CRUNCHING#############
################################################

##Helpful stuff##
#params['param']
#JSON.parse
#to_json
#File.open('public/data/_____','r' or 'w')
#File.close

def retrieveJSON(filename) #return JSON of a file to make it available for rewrite
	txtfile = File.open(filename,'r')
	content = ''
	txtfile.each do |line|
		content << line
	end
	txtfile.close
	JSON.parse(content)
end

def saveTeamMatchInfo(jsondata)
	jsondata = JSON.parse(jsondata)
	eventcode = jsondata['sEventCode']
	teamnumber = jsondata['iTeamNumber']
	matchnumber = jsondata['iMatchNumber']
	filename = "public/data/"+eventcode+"_Match"+matchnumber.to_s+"_Team"+teamnumber.to_s+".json"
	jsonfile = File.open(filename,'w')
	jsonfile << jsondata #array of all MatchEvent objects into file. maybe?
	jsonfile.close
	#Possible extra task: compare existing json to saved json in case of double-saving
	puts "Successfully saved " + filename
end

def saveTeamPitInfo(jsondata)
	jsondata = JSON.parse(jsondata)
	filename = "public/data/"+eventcode+"_Pit_Team"+teamnumber.to_s+".json"
	existingjson = '{}'
	#if File.exists? filename
	#	existingjson = retrieveJSON(filename)
	#end
	jsonfile = File.open(filename,'w')
	jsonfile << jsondata
	jsonfile.close
	puts "Successfully saved " + filename
end


################################################
################BEGIN ANALYTICS#################
################################################

def analyzeTeamMatchInfo(matcheventname)
	#JSON.parse
	#.each do ||
	#an array for each? sad boi
end

#Match scouting (send list of matches, alliances, teams)
#Match scouting (receive match scout data)
#Analytics home (send relevant statistics)
#Analytics specific (send specific statistics)
#Team profile (send statistics for a given team, AS WELL AS relevant matches)