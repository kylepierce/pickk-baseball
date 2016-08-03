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
    innings = game['innings'] or []
    @logger.verbose "Number of innings - #{innings.length}"

    if innings.length
      # propagate data down
      for inning in innings when inning['halfs']
        for half in inning['halfs'] when half['events']
          for event in half['events']
            for type, data of event
              _.extend data,
                inning: inning['number']
                half: half['half']
                type: type

              # extend play events
              if type is 'at_bat' and data['events']
                for pitch in data['events']
                  _.extend pitch,
                    inning: inning['number']
                    half: half['half']
                    hitter_id: data['hitter_id']

      @innings = innings = _.sortBy(innings, @byNumber)
      halfs = _.flatten _.pluck _.sortBy(innings, @byNumber), 'halfs'
      @logger.verbose "Number of halfs - #{halfs.length}"

      groupedHalfs = _.groupBy halfs, @byTeam
      homeHalfs = groupedHalfs[@HOME_TEAM_MARKER]
      awayHalfs = groupedHalfs[@AWAY_TEAM_MARKER]
      @logger.verbose "Number of (#{@HOME_TEAM_MARKER}) halfs - #{homeHalfs.length}"
      @logger.verbose "Number of (#{@AWAY_TEAM_MARKER}) halfs - #{awayHalfs.length}"

      homeTeamId = game['scoring']['home'].id
      @logger.verbose "homeTeamId - #{homeTeamId}"
      awayTeamId = game['scoring']['away'].id
      @logger.verbose "awayTeamId - #{awayTeamId}"

      allEvents = _.flatten _.pluck halfs, 'events'
      @logger.verbose "Number of home events - #{allEvents.length}"
      splitHomeEvents = _.pluck groupedHalfs[@HOME_TEAM_MARKER], 'events'
      homeEvents = _.flatten splitHomeEvents
      @logger.verbose "Number of home events - #{homeEvents.length}"
      splitAwayEvents = _.pluck groupedHalfs[@AWAY_TEAM_MARKER], 'events'
      awayEvents = _.flatten splitAwayEvents
      @logger.verbose "Number of away events - #{awayEvents.length}"

      allLineups = _.pluck (_.filter(allEvents, @isLineup)), 'lineup'
      homeLineups = _.filter allLineups, @ofTeam(homeTeamId)
      @logger.verbose "Number of home lineups - #{homeLineups.length}"
      awayLineups = _.filter allLineups, @ofTeam(awayTeamId)
      @logger.verbose "Number of away lineups - #{awayLineups.length}"

      homePlays = _.sortBy _.pluck(_.filter(homeEvents, @isPlay), 'at_bat'), @byDate
      @logger.verbose "Number of home plays - #{homePlays.length}"
      awayPlays = _.sortBy _.pluck(_.filter(awayEvents, @isPlay), 'at_bat'), @byDate
      @logger.verbose "Number of away plays - #{awayPlays.length}"

      @buildTeam @HOME_TEAM_MARKER, homeLineups
      @buildTeam @AWAY_TEAM_MARKER, awayLineups
      @logger.verbose @teamsByOrder
      @logger.verbose @teamsById
  
      plays = _.sortBy homePlays.concat(awayPlays), @byDate
      @lastPlay = lastPlay = @getLastPlay(plays)
      @lastPlays = lastPlays = {}

      inningNumber = @lastPlay?.inning or 0

      result =
        balls: 0
        strikes: 0
        playNumber: plays.length
        pitchNumber: 1
        inningNumber: inningNumber
        commercialBreak: false
        outcomesList:
          "#{homeTeamId}": @getOutcomesForHalfs splitHomeEvents
          "#{awayTeamId}": @getOutcomesForHalfs splitAwayEvents

      if lastPlay
        @logger.verbose "lastPlay", lastPlay
        lastPlays[@HOME_TEAM_MARKER] = @getLastPlay homePlays
        lastPlays[@AWAY_TEAM_MARKER] = @getLastPlay awayPlays
        @logger.verbose "lastPlays", lastPlays

        if @isFinishedPlay lastPlay
          result.playNumber++

          if @isFinishedHalf lastPlay
            @logger.verbose "Play is finished, half as well"

            oppositeMarker = if lastPlay.id is lastPlays[@AWAY_TEAM_MARKER].id then @HOME_TEAM_MARKER else @AWAY_TEAM_MARKER
            @logger.verbose "oppositeMarker", oppositeMarker

            oppositeLastPlay = lastPlays[oppositeMarker]
            @logger.verbose "oppositeLastPlay", oppositeLastPlay

            if oppositeLastPlay
              hitterId = oppositeLastPlay['hitter_id']
              @logger.verbose "hitterId", hitterId

              hitter = @teamsById[oppositeMarker][hitterId]
              @logger.verbose "hitter", hitter

              nextOrder = ((hitter.order) % 8) + 1
              @logger.verbose "nextOrder", nextOrder

              nextPlayer = @teamsByOrder[oppositeMarker][nextOrder]
              @logger.verbose "nextPlayer", nextPlayer

              result.hitter = nextPlayer
            else
              result.hitter = @getFirstPlayerForTeam oppositeMarker

            result.commercialBreak = @isFinishedInning lastPlay
            @logger.verbose "---- INNING HAS BEEN FINISHED ----" if result.commercialBreak
          else
            @logger.verbose "Play is finished, half is not"

            marker = if lastPlay.id is lastPlays[@HOME_TEAM_MARKER]?.id then @HOME_TEAM_MARKER else @AWAY_TEAM_MARKER
            @logger.verbose "marker", marker

            hitterId = lastPlay['hitter_id']
            @logger.verbose "hitterId", hitterId

            @logger.verbose "@teamsById[marker]", @teamsById[marker]
            hitter = @teamsById[marker][hitterId]
            @logger.verbose "hitter", hitter

            nextOrder = ((hitter.order) % 8) + 1
            @logger.verbose "nextOrder", nextOrder

            nextPlayer = @teamsByOrder[marker][nextOrder]
            @logger.verbose "nextPlayer", nextPlayer

            result.hitter = nextPlayer
        else
          @logger.verbose "Play is in progress"

          marker = if lastPlays[@HOME_TEAM_MARKER] and (lastPlay.id is lastPlays[@HOME_TEAM_MARKER].id) then @HOME_TEAM_MARKER else @AWAY_TEAM_MARKER
          hitterId = lastPlay['hitter_id']
          @logger.verbose "hitterId", hitterId

          hitter = @teamsById[marker][hitterId]
          @logger.verbose "hitter", hitter

          @lastPitch = pitch = @getLastPitch lastPlay

          _.extend result,
            hitter: hitter
            pitch: pitch
            pitchNumber: @getPitches(lastPlay).length + 1
            balls: if pitch then pitch['count'].balls else 0
            strikes: if pitch then pitch['count'].strikes else 0
      else
        @logger.verbose "It's the first play of the match"

        # no plays, select first player for "guest" team
        result.hitter = @getFirstPlayerForTeam @AWAY_TEAM_MARKER
        result.playNumber = 1

      result.teams = @getTeams game
      result.players = @getPlayers()
      result.details = @getDetails game
      result.plays = @getPlayResults plays

      result
    else
      # no innings, no line ups, nothing to do

  getFirstPlayerForTeam: (team) -> @teamsByOrder[team][1]

  isLineup: (event) -> event['lineup']
  isPlay: (event) -> event['at_bat']
  isPitch: (event) -> event['type'] is 'pitch'
  isFinishedPlay: (play) -> @getLastPitch(play)?['flags']['is_ab_over']
  isFinishedHalf: (play) -> @getLastPitch(play)?['count']['outs'] is 3
  isFinishedInning: (play) -> @isFinishedHalf(play) and play.half is 'B'
  byTeam: (half) -> half['half']
  byDate: (play) -> moment(play['events'][0]['created_at']).toDate()
  byNumber: (inning) -> inning['number']

  buildTeam: (marker, lineups) ->
    @teamsByOrder[marker] = {}
    @teamsByOrder[marker][lineup['order']] = lineup for lineup in lineups
    @teamsById[marker] = {}
    @teamsById[marker][lineup['player_id']] = lineup for lineup in lineups

  getLastPlay: (plays) -> _.sortBy(plays, @byDate).pop()

  getPitches: (play) -> _.sortBy(_.filter(play['events'], @isPitch), (pitch) -> moment(pitch['created_at']).toDate())

  getLastPitch: (play) ->
    pitches = @getPitches play
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
      second: false
      third: false

    outs = 0
    if @lastPlay
      lastPitch = @getLastPitch @lastPlay
      outs = lastPitch['count']['outs'] % 3 if lastPitch

      if lastPitch and not @isFinishedHalf @lastPlay
        runners = lastPitch['runners']
        bases.first = !!(_.findWhere runners, {ending_base: 1, out: 'false'})
        bases.second = !!(_.findWhere runners, {ending_base: 2, out: 'false'})
        bases.third = !!(_.findWhere runners, {ending_base: 3, out: 'false'})

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

  getPlayResults: (plays) ->
    nonEmptyPlays = _.filter plays, (play) => @getPitches(play).length

    for play in nonEmptyPlays
      pitches = @getPitches play

      id: play.id
      pitches: @getPitchOutcome pitches.slice(0, number) for number in [1..pitches.length]
      outcome: @getPlayOutcomeByPlay play

  getPlayOutcomeByPlay: (play) ->
    pitch = @getLastPitch play
    
    return 'Walk' if pitch['count']['balls'] is 4

    runners = pitch['runners']
    batter = _.findWhere runners, {starting_base: 0}
    return 'Out' if not batter

    end = batter['ending_base']

    switch end
      when 1 then 'Single'
      when 2 then 'Double'
      when 3 then 'Triple'
      when 4 then 'Home Run'

  getPitchOutcome: (pitches) ->
    last = pitches.pop()
    previous = pitches.pop() or {count: {balls: 0, strikes: 0, outs: 0}}
    
    return 'Foul Ball' if last['outcome_id'] is 'kF' and previous['count']['strikes'] is 2
    return 'Ball' if last['count']['balls'] isnt previous['count']['balls']
    return 'Strike Out' if (last['count']['strikes'] is 3) and (last['count']['outs'] isnt previous['count']['outs'])
    return 'Strike' if last['count']['strikes'] isnt previous['count']['strikes']
    return 'Out' if last['count']['outs'] isnt previous['count']['outs']
    'Hit'

  ofTeam: (teamId) ->
    (lineup) -> lineup['team_id'] is teamId

  getOutcomesForHalfs: (halfs) ->
    _.map halfs, (events) =>
      plays = _.pluck _.filter(events, @isPlay), 'at_bat'
      pitches = _.filter _.flatten(_.pluck(plays, 'events')), (event) -> event.type is 'pitch'
      _.uniq _.pluck pitches, "outcome_id"
