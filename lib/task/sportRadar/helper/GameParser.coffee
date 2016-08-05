_ = require "underscore"
moment = require "moment"

module.exports = class
  constructor: (dependencies) ->
    @logger = dependencies.logger
    
  getPlay: (game) ->
    @game = game

    @innings = @getInnings()
    @logger.verbose "Number of innings - #{@innings.length}"

    if @innings.length
      @propagateData()

      @halfs = @getHalfs()
      @topHalfs = _.filter @halfs, @isTopHalf
      @bottomHalfs = _.filter @halfs, @isBottomHalf
      @logger.verbose "Halfs - (#{@halfs.length}) [Top - (#{@topHalfs.length}), Bottom - (#{@bottomHalfs.length})]"

      @homeTeamId = @getHomeTeamId()
      @awayTeamId = @getAwayTeamId()
      @logger.verbose "Home team (#{@homeTeamId}), Away team (#{@awayTeamId})"

      @events = @getEvents()
      @topEvents = _.filter @events, @isTopHalfEvent.bind(@)
      @bottomEvents = _.filter @events, @isBottomHalfEvent.bind(@)
      @logger.verbose "Events - (#{@events.length}) [Top - (#{@topEvents.length}), Bottom - (#{@bottomEvents.length})]"

      @lineups = @getLineups @events
      @homeLineups = @getHomeLineups()
      @awayLineups = @getAwayLineups()
      @logger.verbose "Lineups - (#{@lineups.length}) [Home - (#{@homeLineups.length}), Away - (#{@awayLineups.length})]"

      @homeTeamByOrder = @indexTeamByOrder @homeLineups
      @homeTeamById = @indexTeamById @homeLineups
      @awayTeamByOrder = @indexTeamByOrder @awayLineups
      @awayTeamById = @indexTeamById @awayLineups

      @plays = @getPlays @events
      @topPlays = _.filter @plays, @isTopHalf
      @bottomPlays = _.filter @plays, @isBottomHalf
      @logger.verbose "Plays - (#{@plays.length}) [Top - (#{@topPlays.length}), Bottom - (#{@bottomPlays.length})]"

      @lastPlay = @getLastPlay @plays
      @topLastPlay = @getLastPlay @topPlays
      @bottomLastPlay = @getLastPlay @bottomPlays
      @homeLastPlay = @getHomeLastPlay()
      @awayLastPlay = @getAwayLastPlay()
      @logger.verbose "Last play - (#{@lastPlay?.id}) [Home - (#{@homeLastPlay?.id}), Away - (#{@awayLastPlay?.id})]"

      @homeTeamData =
        id: @homeTeamId
        lastPlay: @homeLastPlay
        teamByOrder: @homeTeamByOrder
        teamById: @homeTeamById

      @awayTeamData =
        id: @awayTeamId
        lastPlay: @awayLastPlay
        teamByOrder: @awayTeamByOrder
        teamById: @awayTeamById

      # there is no plays at the beginning of the match
      inningNumber = if @lastPlay then @lastPlay.inning else 0

      # set default values
      result =
        balls: 0
        strikes: 0
        playNumber: @plays.length
        pitchNumber: 1
        inningNumber: inningNumber
        commercialBreak: false
        outcomesList:
          "#{@getTopHalfTeamId()}": @getOutcomes @topHalfs
          "#{@getBottomHalfTeamId()}": @getOutcomes @bottomHalfs

      if @lastPlay

        if @isFinishedPlay @lastPlay
          result.playNumber++

          if @isFinishedHalf @lastPlay
            @logger.verbose "Play is finished, half as well"

            oppositeTeamData = if @homeLastPlay and @lastPlay.id is @homeLastPlay.id then @awayTeamData else @homeTeamData

            if oppositeTeamData.lastPlay
              # find the next batter of the opposite team
              hitterId = oppositeTeamData.lastPlay['hitter_id']
              hitter = oppositeTeamData.teamById[hitterId]
              nextOrder = ((hitter.order) % 8) + 1
              nextHitter = oppositeTeamData.teamByOrder[nextOrder]
              @logger.verbose "Next hitter (#{nextHitter['player_id']}), order (#{nextHitter['order']})"

              result.hitter = nextHitter
            else
              # get the first batter of the opposite team
              result.hitter = oppositeTeamData.teamByOrder[1]

            result.commercialBreak = true
          else
            @logger.verbose "Play is finished, half is not"

            teamData = if @homeLastPlay and @lastPlay.id is @homeLastPlay.id then @homeTeamData else @awayTeamData

            # find the next batter of the same team
            hitterId = @lastPlay['hitter_id']
            hitter = teamData.teamById[hitterId]
            nextOrder = ((hitter.order) % 8) + 1
            nextHitter = teamData.teamByOrder[nextOrder]
            @logger.verbose "Next hitter (#{nextHitter['player_id']}), order (#{nextHitter['order']})"

            result.hitter = nextHitter
        else
          @logger.verbose "Play is in progress"

          teamData = if @homeLastPlay and @lastPlay.id is @homeLastPlay.id then @homeTeamData else @awayTeamData
          hitterId = @lastPlay['hitter_id']
          hitter = teamData.teamById[hitterId]
          @logger.verbose "Next hitter (#{hitter['player_id']}), order (#{hitter['order']})"

          pitch = @getLastPitch @lastPlay

          _.extend result,
            hitter: hitter
            pitch: pitch
            pitchNumber: if pitch then pitch['count']['pitch_count'] + 1 else 1
            balls: if pitch then pitch['count'].balls else 0
            strikes: if pitch then pitch['count'].strikes else 0
      else
        @logger.verbose "It's the first play of the match"

        teamData = if @getTopHalfTeamId() is @getHomeTeamId() then @homeTeamData else @awayTeamData

        # no plays, select first player for "guest" team
        result.hitter = teamData.teamByOrder[1]
        result.playNumber = 1
        result.commercialBreak = true

      result.teams = @getTeams @game
      result.details = @getDetails @game
      result.plays = @getPlayResults @plays

      result
    else
      # no innings, no line ups, nothing to do

  getInnings: ->
    innings = @game['innings'] or []
    _.sortBy innings, 'number'

  getHalfs: ->
    _.flatten _.map @innings, (inning) =>
      halfs = inning['halfs'] or []
      _.sortBy halfs, @isBottomHalf

  isTopHalf: (half) -> half['half'] is 'T'

  isBottomHalf: (half) -> half['half'] is 'B'

  isTopHalfEvent: (event) ->
    key = _.keys(event).pop()
    @isTopHalf event[key]

  isBottomHalfEvent: (event) ->
    key = _.keys(event).pop()
    @isBottomHalf event[key]

  getEvents: -> _.flatten _.pluck @halfs, 'events'

  getLineups: (events) ->
    _.pluck (_.filter(events, @isLineup)), 'lineup'

  getPlays: (events) ->
    _.pluck (_.filter(events, @isPlay)), 'at_bat'

  getHomeLineups: ->
    _.filter @lineups, (lineup) => lineup['team_id'] is @getHomeTeamId()

  getAwayLineups: ->
    _.filter @lineups, (lineup) => lineup['team_id'] is @getAwayTeamId()

  propagateData: ->
    for inning in @innings when inning['halfs']
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

  getHomeTeamId: -> @game['scoring']['home'].id

  getAwayTeamId: -> @game['scoring']['away'].id

  getTopHalfTeamId: ->
    if @lineups.length
      @lineups[0]['team_id']
    else
      # away team is first by default
      @getAwayTeamId()

  getBottomHalfTeamId: ->
    if @lineups.length and @lineups[0]['team_id'] is @getHomeTeamId()
      @getAwayTeamId()
    else
      # home team is first by default
      @getHomeTeamId()

  getHomeLastPlay: ->
    if @getTopHalfTeamId() is @getHomeTeamId() then @topLastPlay else @bottomLastPlay

  getAwayLastPlay: ->
    if @getTopHalfTeamId() is @getAwayTeamId() then @topLastPlay else @bottomLastPlay

  isLineup: (event) -> event['lineup']
  isPlay: (event) -> event['at_bat']
  isPitch: (event) -> event['type'] is 'pitch'
  isFinishedPlay: (play) -> @getLastPitch(play)?['flags']['is_ab_over']
  isFinishedHalf: (play) -> @getLastPitch(play)?['count']['outs'] is 3
  isFinishedInning: (play) -> @isFinishedHalf(play) and play.half is 'B'

  indexTeamByOrder: (lineups) ->
    teams = {}
    # override order in case of replaces
    teams[lineup['order']] = lineup for lineup in lineups
    teams

  indexTeamById: (lineups) ->
    _.indexBy lineups, 'player_id'

  getLastPlay: (plays) -> if plays.length then plays[plays.length - 1] or undefined

  getPitches: (play) -> _.sortBy(_.filter(play['events'], @isPitch), (pitch) -> moment(pitch['created_at']).toDate())

  getLastPitch: (play) ->
    pitches = @getPitches play
    pitches.pop()

  getTeams: (game) ->
    game['scoring']

  getDetails: (game) ->
    inning = @innings[@innings.length - 1]

    home = @buildTeamInfo @homeTeamData
    away = @buildTeamInfo @awayTeamData

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
    inning: inning['number']
    topOfInning: inning.halfs.length isnt 2
    playersOnBase: bases
    users: game.users or []
    nonActive: game.nonActive or []

  buildTeamInfo: (teamData) ->
    team =
      teamId: teamData.id
      pitcher: []
      battingLineUp: _.keys teamData.teamById

    lastPlay = teamData.lastPlay
    if lastPlay
      lastBatter = teamData.teamById[lastPlay['hitter_id']]
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

  getOutcomes: (halfs) ->
    _.map halfs, (half) =>
      events = half['events']
      plays = @getPlays events
      pitches = _.flatten _.map plays, @getPitches.bind(@)
      _.uniq _.pluck pitches, "outcome_id"
