# @homeTeamByOrder = @indexTeamByOrder @homeLineups
# @homeTeamById = @indexTeamById @homeLineups
# @awayTeamByOrder = @indexTeamByOrder @awayLineups
# @awayTeamById = @indexTeamById @awayLineups

# @plays = @getPlays @events
# @topPlays = _.filter @plays, @isTopHalf
# @bottomPlays = _.filter @plays, @isBottomHalf
# @logger.verbose "Plays - (#{@plays.length}) [Top - (#{@topPlays.length}), Bottom - (#{@bottomPlays.length})]"

# @lastPlay = @getLastPlay @plays
# @topLastPlay = @getLastPlay @topPlays
# @bottomLastPlay = @getLastPlay @bottomPlays
# @homeLastPlay = @getHomeLastPlay()
# @awayLastPlay = @getAwayLastPlay()
# @logger.verbose "Last play - (#{@lastPlay?.id}) [Home - (#{@homeLastPlay?.id}), Away - (#{@awayLastPlay?.id})]"

# @homeTeamData =
#   id: @homeTeamId
#   lastPlay: @homeLastPlay
#   teamByOrder: @homeTeamByOrder
#   teamById: @homeTeamById
#
# @awayTeamData =
#   id: @awayTeamId
#   lastPlay: @awayLastPlay
#   teamByOrder: @awayTeamByOrder
#   teamById: @awayTeamById

# there is no plays at the beginning of the match
# inningNumber = if @lastPlay then @lastPlay.inning else 0

# set default values
# result =
#   balls: 0
#   strikes: 0
#   playNumber: @plays.length
#   pitchNumber: 1
#   inningNumber: inningNumber
#   commercialBreak: false
#   outcomesList:
#     "#{@getTopHalfTeamId()}": @getOutcomes @topHalfs
#     "#{@getBottomHalfTeamId()}": @getOutcomes @bottomHalfs


#
#
#
# if @lastPitch
#
#   if @isFinishedPlay @lastPlay
#     @logger.verbose "Play is finished"
#     result.playNumber++
#
#     if @isFinishedHalf @lastPlay
#       @logger.verbose "Play is finished, half as well"
#
#       oppositeTeamData = if @homeLastPlay and @lastPlay.id is @homeLastPlay.id then @awayTeamData else @homeTeamData
#
#       if oppositeTeamData.lastPlay
#         # find the next batter of the opposite team
#         hitterId = oppositeTeamData.lastPlay['hitter_id']
#         hitter = oppositeTeamData.teamById[hitterId]
#         nextOrder = ((hitter.order) % 8) + 1
#         nextHitter = oppositeTeamData.teamByOrder[nextOrder]
#         @logger.verbose "Next hitter (#{nextHitter['player_id']}), order (#{nextHitter['order']})"
#
#         result.hitter = nextHitter
#       else
#         # get the first batter of the opposite team
#         result.hitter = oppositeTeamData.teamByOrder[1]
#
#       result.commercialBreak = true
#       result.onPitchTeamId = oppositeTeamData.id
#     else
#       @logger.verbose "Play is finished, half is not"
#
#       teamData = if @homeLastPlay and @lastPlay.id is @homeLastPlay.id then @homeTeamData else @awayTeamData
#
#       # find the next batter of the same team
#       hitterId = @lastPlay['hitter_id']
#       hitter = teamData.teamById[hitterId]
#       nextOrder = ((hitter.order) % 8) + 1
#       nextHitter = teamData.teamByOrder[nextOrder]
#       @logger.verbose "Next hitter (#{nextHitter['player_id']}), order (#{nextHitter['order']})"
#
#       result.hitter = nextHitter
#       result.onPitchTeamId = teamData.id
#   else
#     @logger.verbose "Play is in progress"
#
#     teamData = if @homeLastPlay and @lastPlay.id is @homeLastPlay.id then @homeTeamData else @awayTeamData
#     hitterId = @lastPlay['hitter_id']
#     hitter = teamData.teamById[hitterId]
#     @logger.verbose "Next hitter (#{hitter['player_id']}), order (#{hitter['order']})"
#
#     pitch = @getLastPitch @lastPlay
#
#     _.extend result,
#       hitter: hitter
#       pitch: pitch
#       pitchNumber: if pitch then pitch['count']['pitch_count'] + 1 else 1
#       balls: if pitch then pitch['count'].balls else 0
#       strikes: if pitch then pitch['count'].strikes else 0
#       onPitchTeamId: teamData.id
# else
#   @logger.verbose "It's the first play of the match"
#
#   teamData = if @getTopHalfTeamId() is @getHomeTeamId() then @homeTeamData else @awayTeamData
#
#   # no plays, select first player for "guest" team
#   result.hitter = teamData.teamByOrder[1]
#   result.playNumber = 1
#   result.commercialBreak = true
#   result.onPitchTeamId = teamData.id

  #propagateData: ->
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



      # getHomeTeamId: -> @game['teams'][0].teamId
      #
      # getAwayTeamId: -> @game['teams'][0].teamId
      #
      # getHomeLastPlay: ->
      #   if @getTopHalfTeamId() is @getHomeTeamId() then @topLastPlay else @bottomLastPlay
      #
      # getAwayLastPlay: ->
      #   if @getTopHalfTeamId() is @getAwayTeamId() then @topLastPlay else @bottomLastPlay

    # @homeTeamId = @getHomeTeamId()
    # @awayTeamId = @getAwayTeamId()

    # @homeLineups = @getHomeLineups @events
    # @awayLineups = @getAwayLineups @events
    #
    #
    #   getHomeLineups: (events) ->
    #     _.pluck (_.filter(events, @isHomeLineup)), 'batter'
    #
    #   getAwayLineups: (events) ->
    #     _.pluck (_.filter(events, @isAwayLineup)), 'batter'
    #
    #   isHomeLineup: (event) -> event['pbpDetailId'] is 96
    #   isAwayLineup: (event) -> event['pbpDetailId'] is 97

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

    # getTeams: (game) ->
    #   game['scoring']



            # @topHalfs = _.filter @halfs, @isTopHalf
            # @bottomHalfs = _.filter @halfs, @isBottomHalf

        # isTopHalf: (half) ->
        #   if half['inningDivision'] is 'Top'
        #     return true
        #
        # isBottomHalf: (half) ->
        #   if half['inningDivision'] is 'Bottom'
        #     return true

        # getOutcomes: (halfs) ->
        #   _.map halfs, (half) =>
        #     events = half['pbpDetails']
        #     plays = @getPlays events
        #     pitches = _.flatten _.map plays, @getPitches.bind(@)
        #     _.uniq _.pluck pitches, "outcome_id"

        # isPitch: (event) -> event['type'] is 'pitch'
        # isFinishedPlay: (play) -> @getLastPitch(play)?['flags']['is_ab_over']
        # isFinishedHalf: (play) -> @getLastPitch(play)?['count']['outs'] is 3
        # isFinishedInning: (play) -> @isFinishedHalf(play) and play.half is 'B'
