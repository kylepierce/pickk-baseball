_ = require "underscore"
moment = require "moment"

module.exports = class
  constructor: (dependencies) ->
    @logger = dependencies.logger
    
    @HOME_TEAM_MARKER = "B"
    @AWAY_TEAM_MARKER = "T"

    @teamsByOrder = {}
    @teamsById = {}

  getPlay: (game) ->
    innings = game['innings']
    @logger.verbose "Number of innings - #{innings.length}"

    if innings.length
      # perhaps _.sort for innings is needed!
      halfs = _.flatten _.pluck _.sortBy(innings, @byNumber), 'halfs'
      @logger.verbose "Number of halfs - #{halfs.length}"
  
      groupedHalfs = _.groupBy halfs, @byTeam
      @logger.verbose "Number of (#{@HOME_TEAM_MARKER}) halfs - #{groupedHalfs[@HOME_TEAM_MARKER].length}"
      @logger.verbose "Number of (#{@AWAY_TEAM_MARKER}) halfs - #{groupedHalfs[@AWAY_TEAM_MARKER].length}"
  
      homeEvents = _.flatten _.pluck groupedHalfs[@HOME_TEAM_MARKER], 'events'
      @logger.verbose "Number of home events - #{homeEvents.length}"
      awayEvents = _.flatten _.pluck groupedHalfs[@AWAY_TEAM_MARKER], 'events'
      @logger.verbose "Number of away events - #{awayEvents.length}"
  
      homePlays = _.sortBy _.pluck(_.filter(homeEvents, @isPlay), 'at_bat'), @byDate
      @logger.verbose "Number of home plays - #{homePlays.length}"
      homeLineups = _.pluck(_.filter(homeEvents, @isLineup), 'lineup')
      @logger.verbose "Number of home lineups - #{homeLineups.length}"
      awayPlays = _.sortBy _.pluck(_.filter(awayEvents, @isPlay), 'at_bat'), @byDate
      @logger.verbose "Number of away plays - #{awayPlays.length}"
      awayLineups = _.pluck(_.filter(awayEvents, @isLineup), 'lineup')
      @logger.verbose "Number of away lineups - #{awayLineups.length}"
  
      @buildTeam @HOME_TEAM_MARKER, homeLineups
      @buildTeam @AWAY_TEAM_MARKER, awayLineups
      @logger.verbose @teamsByOrder
      @logger.verbose @teamsById
  
      lastPlay = @getLastPlay(homePlays.concat awayPlays)

      if lastPlay
        @logger.verbose "lastPlay", lastPlay
        lastPlays = {}
        lastPlays[@HOME_TEAM_MARKER] = @getLastPlay homePlays
        lastPlays[@AWAY_TEAM_MARKER] = @getLastPlay awayPlays
        @logger.verbose "lastPlays", lastPlays

        if @isFinishedPlay lastPlay
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

              hitter: nextPlayer
              balls: 0
              strikes: 0
            else
              hitter: @getFirstPlayerForTeam oppositeMarker
              balls: 0
              strikes: 0
          else
            @logger.verbose "Play is finished, half is not"

            marker = if lastPlay.id is lastPlays[@HOME_TEAM_MARKER].id then @HOME_TEAM_MARKER else @AWAY_TEAM_MARKER
            @logger.verbose "marker", marker

            hitterId = lastPlay['hitter_id']
            @logger.verbose "hitterId", hitterId

            hitter = @teamsById[marker][hitterId]
            @logger.verbose "hitter", hitter

            nextOrder = ((hitter.order) % 8) + 1
            @logger.verbose "nextOrder", nextOrder

            nextPlayer = @teamsByOrder[marker][nextOrder]
            @logger.verbose "nextPlayer", nextPlayer

            hitter: nextPlayer
            balls: 0
            strikes: 0
        else
          @logger.verbose "Play is in progress"

          marker = if lastPlay.id is lastPlays[@HOME_TEAM_MARKER].id then @HOME_TEAM_MARKER else @AWAY_TEAM_MARKER
          hitterId = lastPlay['hitter_id']
          @logger.verbose "hitterId", hitterId

          hitter = @teamsById[marker][hitterId]
          @logger.verbose "hitter", hitter

          pitch = @getLastPitch lastPlay

          hitter: hitter
          balls: pitch['count'].balls
          strikes: pitch['count'].strikes
      else
        @logger.verbose "It's the first play of the match"

        # no plays, select first player for "guest" team
        hitter: @getFirstPlayerForTeam @AWAY_TEAM_MARKER
        balls: 0
        strikes: 0
    else
      # no innings, no line ups, nothing to do

  getFirstPlayerForTeam: (team) -> @teamsByOrder[team][1]

  isLineup: (event) -> event['lineup']
  isPlay: (event) -> event['at_bat']
  isFinishedPlay: (play) -> @getLastPitch(play)['flags']['is_ab_over']
  isFinishedHalf: (play) -> @getLastPitch(play)['count']['outs'] is 3
  byTeam: (half) -> half['half']
  byDate: (play) -> play['events'][0]['created_at']
  byNumber: (inning) -> inning['number']

  buildTeam: (marker, lineups) ->
    @teamsByOrder[marker] = {}
    @teamsByOrder[marker][lineup['order']] = lineup for lineup in lineups
    @teamsById[marker] = {}
    @teamsById[marker][lineup['player_id']] = lineup for lineup in lineups

  getLastPlay: (plays) -> _.sortBy(plays, @byDate).pop()

  getLastPitch: (play) ->
    pitches = _.sortBy(_.filter(play['events'], (event) -> event['type'] is 'pitch'), (pitch) -> moment(pitch['created_at']).toDate())
    @logger.verbose "Number of pitches - #{pitches.length}"
    pitches.pop()
