_ = require "underscore"
moment = require "moment"

module.exports = class
  constructor: (dependencies) ->
    @logger = dependencies.logger
    
    @HOME_TEAM_MARKER = "B"
    @AWAY_TEAM_MARKER = "T"

    @teamsByOrder = {}
    @teamsById = {}

  getPitchById: (game, id) ->
    innings = game['innings']
    halfs = _.flatten _.pluck innings, 'halfs'
    events = _.flatten _.pluck halfs, 'events'
    plays = _.pluck _.filter(events, @isPlay), 'at_bat'
    playEvents = _.flatten _.pluck plays, 'events'
    pitches = _.filter playEvents, @isPitch
    _.indexBy(pitches, 'id')[id]

  getPlay: (game) ->
    innings = game['innings']
    @logger.log "Number of innings - #{innings.length}"

    if innings.length
      @innings = innings = _.sortBy(innings, @byNumber)
      halfs = _.flatten _.pluck _.sortBy(innings, @byNumber), 'halfs'
      @logger.log "Number of halfs - #{halfs.length}"

      groupedHalfs = _.groupBy halfs, @byTeam
      @logger.log "Number of (#{@HOME_TEAM_MARKER}) halfs - #{groupedHalfs[@HOME_TEAM_MARKER].length}"
      @logger.log "Number of (#{@AWAY_TEAM_MARKER}) halfs - #{groupedHalfs[@AWAY_TEAM_MARKER].length}"
  
      homeEvents = _.flatten _.pluck groupedHalfs[@HOME_TEAM_MARKER], 'events'
      @logger.log "Number of home events - #{homeEvents.length}"
      awayEvents = _.flatten _.pluck groupedHalfs[@AWAY_TEAM_MARKER], 'events'
      @logger.log "Number of away events - #{awayEvents.length}"
  
      homePlays = _.sortBy _.pluck(_.filter(homeEvents, @isPlay), 'at_bat'), @byDate
      @logger.log "Number of home plays - #{homePlays.length}"
      homeLineups = _.pluck(_.filter(homeEvents, @isLineup), 'lineup')
      @logger.log "Number of home lineups - #{homeLineups.length}"
      awayPlays = _.sortBy _.pluck(_.filter(awayEvents, @isPlay), 'at_bat'), @byDate
      @logger.log "Number of away plays - #{awayPlays.length}"
      awayLineups = _.pluck(_.filter(awayEvents, @isLineup), 'lineup')
      @logger.log "Number of away lineups - #{awayLineups.length}"
  
      @buildTeam @HOME_TEAM_MARKER, homeLineups
      @buildTeam @AWAY_TEAM_MARKER, awayLineups
      @logger.log @teamsByOrder
      @logger.log @teamsById
  
      @lastPlay = lastPlay = @getLastPlay(homePlays.concat awayPlays)
      @lastPlays = lastPlays = {}

      result =
        balls: 0
        strikes: 0

      if lastPlay
        @logger.log "lastPlay", lastPlay
        lastPlays[@HOME_TEAM_MARKER] = @getLastPlay homePlays
        lastPlays[@AWAY_TEAM_MARKER] = @getLastPlay awayPlays
        @logger.log "lastPlays", lastPlays

        if @isFinishedPlay lastPlay
          if @isFinishedHalf lastPlay
            @logger.log "Play is finished, half as well"

            oppositeMarker = if lastPlay.id is lastPlays[@AWAY_TEAM_MARKER].id then @HOME_TEAM_MARKER else @AWAY_TEAM_MARKER
            @logger.log "oppositeMarker", oppositeMarker

            oppositeLastPlay = lastPlays[oppositeMarker]
            @logger.log "oppositeLastPlay", oppositeLastPlay


            if oppositeLastPlay
              hitterId = oppositeLastPlay['hitter_id']
              @logger.log "hitterId", hitterId

              hitter = @teamsById[oppositeMarker][hitterId]
              @logger.log "hitter", hitter

              nextOrder = ((hitter.order) % 8) + 1
              @logger.log "nextOrder", nextOrder

              nextPlayer = @teamsByOrder[oppositeMarker][nextOrder]
              @logger.log "nextPlayer", nextPlayer

              result.hitter = nextPlayer
            else
              result.hitter = @getFirstPlayerForTeam oppositeMarker
          else
            @logger.log "Play is finished, half is not"

            marker = if lastPlay.id is lastPlays[@HOME_TEAM_MARKER].id then @HOME_TEAM_MARKER else @AWAY_TEAM_MARKER
            @logger.log "marker", marker

            hitterId = lastPlay['hitter_id']
            @logger.log "hitterId", hitterId

            hitter = @teamsById[marker][hitterId]
            @logger.log "hitter", hitter

            nextOrder = ((hitter.order) % 8) + 1
            @logger.log "nextOrder", nextOrder

            nextPlayer = @teamsByOrder[marker][nextOrder]
            @logger.log "nextPlayer", nextPlayer

            result.hitter = nextPlayer
        else
          @logger.log "Play is in progress"

          marker = if lastPlays[@HOME_TEAM_MARKER] and (lastPlay.id is lastPlays[@HOME_TEAM_MARKER].id) then @HOME_TEAM_MARKER else @AWAY_TEAM_MARKER
          hitterId = lastPlay['hitter_id']
          @logger.log "hitterId", hitterId

          hitter = @teamsById[marker][hitterId]
          @logger.log "hitter", hitter

          @lastPitch = pitch = @getLastPitch lastPlay

          _.extend result,
            hitter: hitter
            pitch: pitch
            balls: pitch['count'].balls
            strikes: pitch['count'].strikes
      else
        @logger.log "It's the first play of the match"

        # no plays, select first player for "guest" team
        result.hitter = @getFirstPlayerForTeam @AWAY_TEAM_MARKER

      result.teams = @getTeams game
      result.players = @getPlayers()
      result.details = @getDetails game

      result
    else
      # no innings, no line ups, nothing to do

  getFirstPlayerForTeam: (team) -> @teamsByOrder[team][1]

  isLineup: (event) -> event['lineup']
  isPlay: (event) -> event['at_bat']
  isPitch: (event) -> event['type'] is 'pitch'
  isFinishedPlay: (play) -> @getLastPitch(play)['flags']['is_ab_over']
  isFinishedHalf: (play) -> @getLastPitch(play)['count']['outs'] is 3
  byTeam: (half) -> half['half']
  byDate: (play) -> moment(play['events'][0]['created_at']).toDate()
  byNumber: (inning) -> inning['number']

  buildTeam: (marker, lineups) ->
    @teamsByOrder[marker] = {}
    @teamsByOrder[marker][lineup['order']] = lineup for lineup in lineups
    @teamsById[marker] = {}
    @teamsById[marker][lineup['player_id']] = lineup for lineup in lineups

  getLastPlay: (plays) -> _.sortBy(plays, @byDate).pop()

  getLastPitch: (play) ->
    pitches = _.sortBy(_.filter(play['events'], @isPitch), (pitch) -> moment(pitch['created_at']).toDate())
    @logger.log "Number of pitches - #{pitches.length}"
    pitches.pop()

  getTeams: (game) ->
    game['scoring']

  getPlayers: ->
    _.flatten _.map _.values(@teamsById), (team) -> _.values team

  getDetails: (game) ->
    lastInning = @innings[@innings.length - 1]

    home = @buildTeamInfo game, @HOME_TEAM_MARKER
    away = @buildTeamInfo game, @AWAY_TEAM_MARKER

    bases =
      first: false
      seconds: false
      third: false

    outs = 0
    if @lastPlay
      lastPitch = @getLastPitch @lastPlay
      outs = lastPitch['count']['outs'] % 3

      if not @isFinishedHalf @lastPlay
        runners = lastPitch['runners']
        bases.first = !!(_.findWhere runners, {ending_base: 1, out: 'false'})
        bases.second = !!(_.findWhere runners, {ending_base: 2, out: 'false'})
        bases.third = !!(_.findWhere runners, {ending_base: 3, out: 'false'})

    dateCreated: moment.utc(game.scheduled).startOf('day').toDate()
    name: "#{game['scoring']['home']['name']} vs #{game['scoring']['away']['name']}"
    live: game.status is 'inprogress'
    completed: game.status is 'closed'
    commercial: false
    gameDate: moment.utc(game.scheduled).format('MMM Do LT')
    tv: game['broadcast']['network']
    teams: [home, away]
    outs: outs
    inning: lastInning['number']
    topOfInning: lastInning.halfs.length isnt 2
    playersOnBase: bases
    users: game.users or []
    nonActive: game.nonActive or []

  buildTeamInfo: (game, marker) ->
    teamKey = if marker is @HOME_TEAM_MARKER then 'home' else 'away'

    team =
      teamId: game.scoring[teamKey].id
      pitcher: []
      battingLineUp: _.keys @teamsById[marker]

    lastPlay = @lastPlays[marker]
    if lastPlay
      lastBatter = @teamsById[marker][lastPlay['hitter_id']]
      team.batterNum = lastBatter['order']
      team.batterNum-- if not @isFinishedPlay lastPlay

    team