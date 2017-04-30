_ = require "underscore"
moment = require "moment"

module.exports = class
  constructor: (dependencies) ->
    @logger = dependencies.logger

  getPlay: (game) ->
    @game = game
    @innings = @getInnings()

    if game['old']
      @old = @game['old']
    else
      @old =
        commercialBreak: false

    #Is the game live?
    if @innings.length > 1

      @events = @getEvents()
      @currentAtBat = @getLast @events
      @halfs = @getHalfs()

      if @currentAtBat['pitchDetails']
        @lastPitch = @currentAtBat['pitchDetails']

        if @old['lastCount']
          diff = @lastPitch.length - @old['lastCount'].length
          @logger.verbose "[#{@events.length}] #{diff}"
          if diff < 0
            @logger.verbose "New play!"
            @updateOld()
          else if diff is 1
            @logger.verbose "One New play!"
            @updateOld()
          else if diff > 1
            @logger.verbose "Missed a play?!"
            @updateOld()
          # @updateOld()
          # unless diff is 0
          #   @logger.verbose "Same old play!"


          # What is different?
          # Update last count

          # if @isDifferentBatter @currentAtBat['batter']['playerId']
          #   @logger.verbose "At Bat is finished"
            # Find the next batter
            # Reset counter

            # if @isDifferentHalf @halfs
            #   @logger.verbose "End of Half"
            #   result.commercialBreak = true

    else
      @logger.verbose "Play is in progress"


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

  isDifferent: (old, current) ->
    list = []
    _.map old, (key, value) ->
      oldValue = old[value]
      currentValue = current[value]
      if not _.isEqual(oldValue, currentValue)
        list.push value
    return list

  isDifferentBatter: (current) ->
    if @old['playerId']
      result = @isDifferent(@old['playerId'], current)
      # @logger.verbose result

  isDifferentHalf: (current) ->
    # Has the number of half increased?
    # if new > old['halfs']

  updateOld: () ->
    # @logger.verbose "\n \n First \n"
    # @logger.verbose @old
    # @old.sequence = @getLast @currentAtBat['sequence']
    @old.lastUpdated = new Date()
    @old.lastCount = @lastPitch
    @old.events = @events.length
    # @old.hitter = @currentAtBat['batter']
    # @old.playerId = @currentAtBat['batter']['playerId']
    # @old.outs = @game['eventStatus']['outs']
    # @old.halfs = @halfs.length
    # @old.inning = @game['eventStatus']['inning']

    result = @old
    # @logger.verbose "\n \n Second \n"
    # @logger.verbose @old.lastCount
    # result.old = @old
    # result.details = @getDetails @game
    # result.plays = @getPlayResults @plays
    result

  getDetails: (game) ->
    users: game.users or []
    nonActive: game.nonActive or []
    registered: game.registered or []

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
