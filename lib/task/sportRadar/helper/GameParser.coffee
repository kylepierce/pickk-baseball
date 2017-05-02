_ = require "underscore"
moment = require "moment"

module.exports = class
  constructor: (dependencies) ->
    @logger = dependencies.logger

  getPlay: (game) ->
    @game = game
    @innings =  @game['pbp']
    @halfs = @loopHalfs @innings

    @totalEvents = @getEvents @halfs
    @currentHalf = @getLast @halfs
    @currentHalfEvents = @currentHalf['pbpDetails']

    @atBats = @getAtBats @currentHalfEvents
    @currentAtBat = @getLast @atBats

    if @currentAtBat
      @logger.verbose "Event: #{@game["eventId"]}"
      @logger.verbose "Event Id: #{@currentAtBat["pbpDetailId"]}"
      @logger.verbose "Pitch Sequence: #{@currentAtBat['pitchDetails']}"

      @lastPitch = @getLast @currentAtBat['pitchDetails']
      @pitches = @currentAtBat['pitchDetails']

      @old =
        outs: @game['eventStatus']['outs']
        halfs: @halfs.length
        lastUpdated: new Date()
        inning: @game['eventStatus']['inning']
        events: @totalEvents.length
        lastCount: if @pitches then @pitches else []
        sequence: @currentAtBat['sequence']
        hitter: @currentAtBat['batter']
        playerId: @currentAtBat['batter']['playerId']

      @game['old'] = @old
      result = @game
      result.details = @getDetails @game
      return result

  getEvents: (selector) ->  _.flatten _.pluck selector, 'pbpDetails'

  getAtBats: (selector) -> _.flatten _.filter(selector, @isPlay)

  isPlay: (event) ->
    # event['pbpDetailId'] isnt (96 or 97 or 98 or 42)
    list = [96, 97, 98, 42]
    if event && event['pbpDetailId'] not in list
      return event
    else
      # console.log event['pbpDetailId']
      # console.log "THIS IS NOT A LEGIT EVENT ID"

  getLast: (plays) ->
    if plays and plays.length > 0
      plays[plays.length - 1]
    else
      @logger.verbose plays
      # undefined

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
