_ = require "underscore"
Match = require "mtr-match"
Promise = require "bluebird"
Task = require "../Task"
SportRadarGame = require "../../model/sportRadar/SportRadarGame"
moment = require "moment"

module.exports = class extends Task
  constructor: (dependencies) ->
    super

    Match.check dependencies, Match.ObjectIncluding
      mongodb: Match.Any

    @logger = @dependencies.logger
    @SportRadarGames = dependencies.mongodb.collection("SportRadarGames")
    @Questions = dependencies.mongodb.collection("questions")

  execute: ->
    Promise.bind @
    .tap -> @logger.verbose "Start ProcessGames task"
    .then -> @getActiveGames()
    .tap (games) -> @logger.verbose "ProcessGames: There are #{games.length} active game(s)"
    .tap @closeQuestionsForInactiveGames
    .map @handleGame
    .return true

  getActiveGames: ->
    @SportRadarGames.find({status: "inprogress"})

  closeQuestionsForInactiveGames: (activeGames) ->
    ids = _.pluck activeGames, "id"

    Promise.bind @
    .then -> @Questions.update {game_id: {$nin: ids}, active: true}, {$set: {active: false}}, {multi: true}
    .tap (updated) -> @logger.verbose "ProcessGames: #{updated.nModified} questions have been closed as inactive"

  handleGame: (game) ->
    promises = []
    
    players = @getPlayers game
    
    inning = @getLastInning game
    if inning
      @logger.verbose "The last inning has number ##{inning.number}"

      half = @getLastHalf inning
      if half
        @logger.verbose "The last half has marker \"##{half.half}\""

        play = @getLastPlay half
        if play
          @logger.verbose "The last play has id #{play.id}"

          promises.push @handlePlay(game, players, play)

          pitch = @getLastPitch play
          if pitch
            @logger.verbose "The last pitch has id #{pitch.id}"
            
            promises.push @handlePitch(game, players, play, pitch)
          else
            @logger.verbose "There is no play events for game with id '#{game.id}' within inning ##{inning.number} and half #{half.half} and play #{play.id}"

          Promise.all promises
        else
          @logger.verbose "There is no half events for game with id '#{game.id}' within inning ##{inning.number} and half #{half.half}"
      else
        @logger.verbose "There is no halfs for game with id '#{game.id}' within inning ##{inning.number}"
    else
      @logger.verbose "There is no innings for game with id '#{game.id}'"

  getPlayers: (game) ->
    players = {}

    inning = @getFirstInning game
    for half in inning.halfs
      for event in half.events
        data = event.lineup
        players[data.player_id] = data

    players
    
  handlePlay: (game, players, play) ->
    @logger.verbose "Handle play(#{play.id}) of game (#{game.id})"

    playerId = play['hitter_id']
    player = players[playerId]
    throw new Error("Player with ID(#{playerId}) was not found") if not player
    question = "End of #{player['first_name']} #{player['last_name']}'s at bat."

    pitch = @getLastPitch play
    if pitch
      balls = pitch.count.balls
      strikes = pitch.count.strikes

    title1 = "Strike"
    title2 = "Ball"
    title3 = "Hit"
    title4 = "Out"
    title5 = undefined

    if balls is 3
      title2 = "Walk"
      title3 = "Hit"
      title4 = "Out"

    if strikes is 2
      title1 = "Strike Out"
      title3 = "Foul Ball"
      title4 = "Hit"
      title5 = "Out"

    options =
      option1: {title: title1, usersPicked: [], multiplier: 2.1 }
      option2: {title: title2, usersPicked: [], multiplier: 2.2 }
      option3: {title: title3, usersPicked: [], multiplier: 2.3 }
      option4: {title: title4, usersPicked: [], multiplier: 2.4 }

    options.option5 = {title: title5, usersPicked: [], multiplier: 1 } if title5

    Promise.bind @
    .then ->
      @Questions.update {game_id: game.id, play_id: play.id},
        $set:
          dateCreated: new Date()
          playerId: play['hitter_id']
          atBatQuestion: true
          gameId: game._id
          active: true
          commercial: false
          que: question
          options: options
      , {upsert: true}
    .tap -> @logger.verbose "Upsert play question \"#{question}\" with game(#{game.id}) and play(#{play.id})"
    .then -> @closeInactivePlays game, play

  closeInactivePlays: (game, play) ->
    Promise.bind @
    .then ->
      @Questions.update {game_id: game.id, play_id: {$exists: true, $ne: play.id}, active: true},
        $set: {active: false},
        {multi: true}
    .tap (updated) -> @logger.verbose "ProcessGames: #{updated.nModified} play questions have been closed as inactive"

  handlePitch: (game, players, play, pitch) ->
    @logger.verbose "Handle pitch(#{pitch.id}) of play(#{play.id}) of game(#{game.id})"

    playerId = play['hitter_id']
    player = players[playerId]
    throw new Error("Player with ID(#{playerId}) was not found") if not player
    question = "End of #{player['first_name']} #{player['last_name']}'s at bat."

    balls = pitch.count.balls
    strikes = pitch.count.strikes
    question = "#{player['first_name']} #{player['last_name']}: " + balls + " - " + strikes

    options =
      option1: { title: "Option1", usersPicked: [], multiplier: 1.45 }
      option2: { title: "Option2", usersPicked: [], multiplier: 1.65 }
      option3: { title: "Option3", usersPicked: [], multiplier: 7.35 }
      option4: { title: "Option4", usersPicked: [], multiplier: 3.23 }

    Promise.bind @
    .then ->
      @Questions.update {game_id: game.id, pitch_id: pitch.id},
        $set:
          dateCreated: new Date()
          playerId: play['hitter_id']
          gameId: game._id
          active: true
          commercial: false
          que: question
          options: options
      , {upsert: true}
    .tap -> @logger.verbose "Upsert pitch question \"#{question}\" with game(#{game.id}), play(#{play.id}) and pitch(#{pitch.id})"
    .then -> @closeInactivePitches game, play, pitch

  closeInactivePitches: (game, play, pitch) ->
    Promise.bind @
    .then ->
      @Questions.update {game_id: game.id, pitch_id: {$exists: true, $ne: pitch.id}, active: true},
        $set: {active: false},
        {multi: true}
    .tap (updated) -> @logger.verbose "ProcessGames: #{updated.nModified} pitch questions have been closed as inactive"

  getFirstInning: (game) ->
    innings =  _.sortBy game['innings'], "number"
    innings.shift()

  getLastInning: (game) ->
    innings =  _.sortBy game['innings'], "number"
    innings.pop()

  getLastHalf: (inning) ->
    halfs = _.sortBy inning['halfs'], @_halfSorter
    halfs.pop()

  getLastPlay: (half) ->
    halfEvents = half['events']
    @logger.verbose "There are #{halfEvents.length} half events"
    if halfEvents.length
      halfEvents = _.filter halfEvents, @_atBatEventFilter
      @logger.verbose "There are #{halfEvents.length} at bat plays"
      halfEvents = _.pluck halfEvents, 'at_bat'
      halfEvents = _.sortBy halfEvents, @_sortHalfEvents
      halfEvents.pop()

  getLastPitch: (play) ->
    playEvents = play['events']
    if playEvents.length
      @logger.verbose "There are #{playEvents.length} play events"
      playEvents = _.filter playEvents, @_pitchFilter
      @logger.verbose "There are #{playEvents.length} pitch events"
      playEvents = _.sortBy playEvents, @_sortPlayEvents
      playEvents.pop()

  _halfSorter: (half) ->
    if half.half is "B" then 1 else 0

  _atBatEventFilter: (event) ->
    event['at_bat']

  _sortHalfEvents: (play) ->
    events = _.sortBy play['events'], @_sortPlayEvents
    event = events.pop()
    # if there is no pitches with timestamp - it's the latest play
    if event then moment(event.created_at).toDate() else Number.MAX_VALUE

  _sortPlayEvents: (event) ->
    moment(event.created_at).toDate()

  _pitchFilter: (event) ->
    event.type is 'pitch'
