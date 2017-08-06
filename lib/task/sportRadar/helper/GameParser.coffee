_ = require "underscore"
Match = require "mtr-match"
Promise = require "bluebird"
moment = require "moment"
Task = require "../../Task"

module.exports = class extends Task
  constructor: (dependencies) ->
    super

    Match.check dependencies, Match.ObjectIncluding
      mongodb: Match.Any

    @logger = @dependencies.logger
    @SportRadarGames = dependencies.mongodb.collection("games")

  getPlay: (game) ->
    @game = game
    @innings = @game['pbp']
    @halfs = @loopHalfs @innings

    @totalEvents = @getEvents @halfs
    @currentHalf = @getLast @halfs
    @currentHalfEvents = @currentHalf['pbpDetails']

    # @atBats = @getAtBats @currentHalfEvents
    @currentAtBat = @getLast @currentHalfEvents

    if @currentAtBat
      @lastPitch = @getLast @currentAtBat['pitchDetails']
      if @currentAtBat['pitchDetails']
        @pitches = @currentAtBat['pitchDetails']
      else
        @pitches = []

    @old =
      outs: @game['eventStatus']['outs']
      halfs: @halfs.length
      inning: @game['eventStatus']['inning']
      inningDivision: @game['eventStatus']['inningDivision']
      eventCount: @totalEvents.length
      eventStatus: @game['eventStatus']
      eventId: if @currentAtBat then @currentAtBat['pbpDetailId'] else undefined
      lastCount: if @pitches then @pitches else []
      hitter: if @currentAtBat then @currentAtBat['batter'] else undefined
      player: if @currentAtBat['batter'] then @currentAtBat['batter'] else undefined
      playerId: if @currentAtBat['batter'] then @currentAtBat['batter']['playerId'] else undefined

      lastUpdate: new Date

    @game['old'] = @old
    result = @game
    return result

  getEvents: (selector) ->  _.flatten _.pluck selector, 'pbpDetails'

  getLast: (plays) ->
    if plays and plays.length > 0
      plays[plays.length - 1]

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

  findSpecificEvent: (parms, eventNumber) ->
    Promise.bind @
      .then -> @SportRadarGames.find {_id: parms.gameId}
      .then (game) -> @loopHalfs game[0]['pbp']
      .then (halfs) -> @getEvents halfs
      .then (events) -> events[eventNumber]
      .then (result) -> return result


      # .then (game) ->
      #   console.log game[0]
      #   innings = @loopHalfs game[0]['pbp']
      #   halfs = @loopHalfs innings
      #   totalEvents = @getEvents halfs
      #   console.log totalEvents

    # console.log parms.gameId
    # innings =  game['pbp']
    # halfs = @loopHalfs innings
    # totalEvents = @getEvents halfs
    # @logger.verbose "Following event... ", totalEvents[eventNumber + 1]
    # console.log totalEvents[eventNumber]
    # return totalEvents[eventNumber]
