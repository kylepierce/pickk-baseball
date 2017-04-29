_ = require "underscore"
moment = require "moment"

module.exports = class
  constructor: (dependencies) ->
    @logger = dependencies.logger

  getPlay: (game) ->
    @game = game
    @innings = @getInnings()

    #Is the game live?
    if @innings.length > 1
      # @propagateData()

      @halfs = @getHalfs()
      @topHalfs = _.filter @halfs, @isTopHalf
      @bottomHalfs = _.filter @halfs, @isBottomHalf
      @homeTeamId = @getHomeTeamId()
      @awayTeamId = @getAwayTeamId()
      @events = @getEvents()

      # @lineups = @getLineups @events
      @homeLineups = @getHomeLineups @events
      @awayLineups = @getAwayLineups @events
      # @logger.verbose "Lineups - [Home - (#{@homeLineups.length}), Away - (#{@awayLineups.length})]"

      # @plays = @getPlays @events
      @currentAtBat = @getLastBatter @events
      @lastPitch = @getLastPitch @currentAtBat

      # is the last batter still in pitch?
      # Did the halfs increase?

      if @lastPitch

        if @isFinishedPlay @lastPlay
          @logger.verbose "Play is finished"
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
            result.onPitchTeamId = oppositeTeamData.id
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
            result.onPitchTeamId = teamData.id
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
            onPitchTeamId: teamData.id
      else
        @logger.verbose "It's the first play of the match"

        teamData = if @getTopHalfTeamId() is @getHomeTeamId() then @homeTeamData else @awayTeamData

        # no plays, select first player for "guest" team
        result.hitter = teamData.teamByOrder[1]
        result.playNumber = 1
        result.commercialBreak = true
        result.onPitchTeamId = teamData.id

      result.teams = @getTeams @game
      result.details = @getDetails @game
      result.plays = @getPlayResults @plays

      result
    else
      @logger.verbose "No Game Right Now"
      #no innings, no line ups, nothing to do

  getInnings: ->
    innings = @game['pbp'] or []

  getHalfs: ->
    _.flatten _.map @innings, (half) =>
      halfs = half or []

  isTopHalf: (half) ->
    if half['inningDivision'] is 'Top'
      return true

  isBottomHalf: (half) ->
    if half['inningDivision'] is 'Bottom'
      return true

  getEvents: -> _.flatten _.pluck @innings, 'pbpDetails'

  getPlays: (events) ->
    _.pluck (_.filter(events, @isPlay)), 'pitchDetails'

  getHomeLineups: (events) ->
    _.pluck (_.filter(events, @isHomeLineup)), 'batter'

  getAwayLineups: (events) ->
    _.pluck (_.filter(events, @isAwayLineup)), 'batter'

  propagateData: ->
    # for inning in @innings when inning['halfs']
    #   for half in inning['halfs'] when half['pbpDetails']
    #     for event in half['pbpDetails']
    #       for type, data of event
    #         _.extend data,
    #           inning: inning['number']
    #           half: half['inningDivision']
    #           type: type
    #
    #         # extend play events
    #         if type is 'at_bat' and data['pbpDetails']
    #           for pitch in data['pbpDetails']
    #             _.extend pitch,
    #               inning: inning['number']
    #               half: half['inningDivision']
    #               hitter_id: data['hitter_id']

  getHomeTeamId: -> @game['teams'][0].teamId

  getAwayTeamId: -> @game['teams'][0].teamId

  getHomeLastPlay: ->
    if @getTopHalfTeamId() is @getHomeTeamId() then @topLastPlay else @bottomLastPlay

  getAwayLastPlay: ->
    if @getTopHalfTeamId() is @getAwayTeamId() then @topLastPlay else @bottomLastPlay

  isHomeLineup: (event) -> event['pbpDetailId'] is 96
  isAwayLineup: (event) -> event['pbpDetailId'] is 97
  isPlay: (event) -> event['pbpDetailId'] isnt 96 or 97
  isPitch: (event) -> event['type'] is 'pitch'
  isFinishedPlay: (play) -> @getLastPitch(play)?['flags']['is_ab_over']
  isFinishedHalf: (play) -> @getLastPitch(play)?['count']['outs'] is 3
  isFinishedInning: (play) -> @isFinishedHalf(play) and play.half is 'B'

  getLastBatter: (plays) -> if plays.length then plays[plays.length - 1] or undefined

  getLastPitch: (play) ->
    # @logger.verbose "Pitch details: #{play['pitchDetails']}"
    # pitches = @getPitches play
    play['pitchDetails'].pop()

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
      events = half['pbpDetails']
      plays = @getPlays events
      pitches = _.flatten _.map plays, @getPitches.bind(@)
      _.uniq _.pluck pitches, "outcome_id"



  # isTopHalfEvent: (event) ->
  #   key = _.keys(event).pop()
  #   @isTopHalf event[key]

  # isBottomHalfEvent: (event) ->
  #   key = _.keys(event).pop()
  #   @isBottomHalf event[key]

  # getLineups: (events) ->
  #   _.pluck (_.filter(events, @isLineup)), 'batter'

  # indexTeamByOrder: (lineups) ->
  #   teams = {}
  #   # override order in case of replaces
  #   teams[lineup['order']] = lineup for lineup in lineups
  #   teams

  # indexTeamById: (lineups) ->
  #   _.indexBy lineups, 'player_id'

  # getPitches: (play) -> _.sortBy(_.filter(play['pbpDetails'], @isPitch), (pitch) -> moment(pitch['created_at']).toDate())

  # buildTeamInfo: (teamData) ->
  #   team =
  #     teamId: teamData.id
  #     pitcher: []
  #     battingLineUp: _.keys teamData.teamById
  #
  #   lastPlay = teamData.lastPlay
  #   if lastPlay
  #     lastBatter = teamData.teamById[lastPlay['hitter_id']]
  #     team.batterNum = lastBatter['order']
  #     team.batterNum-- if not @isFinishedPlay lastPlay
  #
  #   team

# getTopHalfTeamId: ->
#   if @lineups.length
#     @lineups[0]['team_id']
#   else
#     # away team is first by default
#     @getAwayTeamId()
#
# getBottomHalfTeamId: ->
#   if @lineups.length and @lineups[0]['team_id'] is @getHomeTeamId()
#     @getAwayTeamId()
#   else
#     # home team is first by default
#     @getHomeTeamId()
