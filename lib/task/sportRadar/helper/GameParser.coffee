_ = require "underscore"
moment = require "moment"

module.exports = class
  constructor: (dependencies) ->
    @logger = dependencies.logger

  getPlay: (game) ->
    @game = game
    @logger.verbose game['eventStatus']
    @innings =  @game['pbp']
    @halfs = @loopHalfs @innings

    @totalEvents = @getEvents @halfs
    @currentHalf = @getLast @halfs
    @currentHalfEvents = @currentHalf['pbpDetails']

    @atBats = @getAtBats @currentHalfEvents
    @currentAtBat = @getLast @atBats

    @lastPitch = @getLast @currentAtBat['pitchDetails']
    @pitches = @currentAtBat['pitchDetails']

    # if @game['old']
    #   @old = game['old']
    # @pitchDiff = @pitches.length - @old['lastCount'].length
    # @eventDiff = @totalEvents.length - @old['events']
    # @halfDiff = @halfs.length - @old['halfs']
    #
    #   @isDifferentPitch @pitchDiff
    #   @isDifferentEvent @eventDiff
    #   @isDifferentHalf @halfDiff
    #
    #   # @logger.verbose "Old - [#{@game.name}] Pitch: #{@old['lastCount'].length} -  Event: #{@old['events']} - Half: #{@old['halfs']}"
    #   # @logger.verbose "New - [#{@game.name}] Pitch: #{@pitches.length} -  Event: #{@totalEvents.length} - Half: #{@halfs.length}"
    #   # @logger.verbose "Diff - [#{@game.name}] Pitch: #{@pitchDiff} -  Event: #{@eventDiff} - Half: #{@halfDiff}"
    #   return @updateOld()
    # else
    #   @game['old'] = {}
    @old =
      outs: @game['eventStatus']['outs']
      halfs: @halfs.length
      lastUpdated: new Date()
      inning: @game['eventStatus']['inning']
      events: @totalEvents.length
      lastCount: @pitches
      sequence: @currentAtBat['sequence']
      hitter: @currentAtBat['batter']
      playerId: @currentAtBat['batter']['playerId']

    @game['old'] = @old
    result = @game
    # result.details = @getDetails @game
    return result

  getEvents: (selector) ->  _.flatten _.pluck selector, 'pbpDetails'

  getAtBats: (selector) ->
    _.flatten _.filter(selector, @isPlay)

  # Dont grab events that are lineups (96, 97), substitutions (98), scores on a pitcher (42). Make this into array
  isPlay: (event) -> event['pbpDetailId'] isnt 96 or 97 or 98 or 42
  getLast: (plays) -> if plays or plays.length then plays[plays.length - 1] or 0

  loopHalfs: (innings) ->
    array = _.map innings, (half) ->
      inning: half.inning
      inningDivision: half.inningDivision
      linescore: half.linescore
      pbpDetails: _.toArray _.map half.pbpDetails, (event) ->
        pbpDetailId: event.pbpDetailId
        sequence: event.sequence
        pitches: if event.pitches then event.pitches
        batter: if event.batter then event.batter
        pitchSequence: if event.pitchSequence then event.pitchSequence
        pitchDetails: if event.pitchDetails then event.pitchDetails
        playText: if event.playText then event.playText

    return  _.toArray array

  # cleanHalf: (half) ->
  #   # Take one object and return one object
  #   @logger.verbose half
  #   result =
  #     inning: half.inning
  #     inningDivision: half.inningDivision
  #     linescore: half.linescore
  #     pbpDetails: _.each half.pbpDetails, (event) ->
  #       @cleanEvent(event) # Loop over array of objects and return an array

  # cleanEvent: (event) ->
  #   # Take in one object and return one object
  #   result =


  isDifferentPitch: (diff) ->
    if diff is 1
      @logger.verbose "One New play!"
    else if diff > 1
      @logger.verbose "Missed plays?!"
    else if diff < 0
      @logger.verbose "New batter?"

  isDifferentEvent: (diff) ->
    if diff is 1
      @logger.verbose "One New Event!"
    else if diff > 1
      @logger.verbose "Missed Events?!"

  isDifferentHalf: (diff) ->
    if diff is 1
      @logger.verbose "One Half!"
    else if diff > 1
      @logger.verbose "Missed Halfs?!"

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
