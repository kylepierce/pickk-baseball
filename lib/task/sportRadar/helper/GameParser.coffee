_ = require "underscore"
moment = require "moment"

module.exports = class
  constructor: (dependencies) ->
    @logger = dependencies.logger

  getPlay: (game) ->
    @game = game
    old = game['old']
    @innings = @getInnings()

    #Is the game live?
    if @innings.length > 1

      @events = @getEvents()
      @currentAtBat = @getLast @events
      @halfs = @getHalfs()

      result =
        lastUpdated: new Date()

      if @currentAtBat isnt undefined
        # @logger.verbose "Play is finished"
        @lastPitch = @getLast @currentAtBat['pitchDetails']
      else
        @logger.verbose "Has the game really started yet?"

      # Is the pitch count larger then previous?
      if @isDifferentPlay()
          @logger.verbose "Play is finished"
          # What is different?
          # Update last count

        if @isDifferentBatter()
          @logger.verbose "At Bat is finished"
          # Find the next batter
          # Reset counter

          if @isDifferentHalf()
            @logger.verbose "End of Half"
            result.commercialBreak = true

            if @isDifferentInning()
              @logger.verbose "End of Inning"
      else
        @logger.verbose "Play is in progress"

    # How to compare to the next play
    old =
      commercialBreak: false
      lastCount: @currentAtBat['pitches']
      events: @events.length
      hitter: @currentAtBat['batter']
      playerId: @currentAtBat['batter']['playerId']
      outs: @game['eventStatus']['outs']
      halfs: @halfs.length
      inning: @game['eventStatus']['inning']

    result.old = old
    result.details = @getDetails @game
    # result.plays = @getPlayResults @plays

    result
    else
      @logger.verbose "No Game Right Now"

  getInnings: ->
    innings = @game['pbp'] or []

  getHalfs: ->
    _.flatten _.map @innings, (half) =>
      halfs = half or []

  getEvents: -> _.flatten _.pluck @innings, 'pbpDetails'

  getPlays: (events) ->
    _.pluck (_.filter(events, @isPlay)), 'pitchDetails'

  isPlay: (event) -> event['pbpDetailId'] isnt 96 or 97
  getLast: (plays) -> if plays.length then plays[plays.length - 1] or undefined

  isDifferentPlay: (new) -> _.isEqual(old['lastCount'], new)

  isDifferentBatter: (new) ->

  isDifferentHalf: (new) ->

  isDifferentInning: (new) ->

  getDetails: (game) ->
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
