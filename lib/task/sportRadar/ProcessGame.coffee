_ = require "underscore"
Match = require "mtr-match"
Promise = require "bluebird"
Task = require "../Task"
SportRadarGame = require "../../model/sportRadar/SportRadarGame"
Team = require "../../model/Team"
Player = require "../../model/Player"
GameParser = require "./helper/GameParser"
moment = require "moment"
promiseRetry = require 'promise-retry'
chance = new (require 'chance')

module.exports = class extends Task
  constructor: (dependencies) ->
    super

    Match.check dependencies, Match.ObjectIncluding
      mongodb: Match.Any

    @logger = @dependencies.logger
    @SportRadarGames = dependencies.mongodb.collection("games")
    @Teams = dependencies.mongodb.collection("teams")
    @Players = dependencies.mongodb.collection("players")
    @Questions = dependencies.mongodb.collection("questions")
    @AtBats = dependencies.mongodb.collection("atBat")
    @Answers = dependencies.mongodb.collection("answers")
    @Users = dependencies.mongodb.collection("users")
    @gameParser = new GameParser dependencies

  execute: (game) ->
    promiseRetry (retry) =>
      Promise.bind @
      .tap -> @logger.verbose "Start ProcessGames"
      .then -> @handleGame game
      .return true
      .catch (error) =>
        @logger.error error.message, _.extend({stack: error.stack}, error.details)
        retry(error)

  handleGame: (game) ->
    result = @gameParser.getPlay game

    if result
      Promise.bind @
      .then -> @enrichGame game, result.details
      .then -> @handlePlay game, result
      .then -> @handlePitch game, result
      .then -> @handleAtBat game, result

  handleAtBat: (game, result) ->
    Promise.bind @
    .then -> @AtBats.update {gameId: game._id, playerId: result.hitter['player_id'], active: true}, {$set: {ballCount: result.balls, strikeCount: result.strikes, dateCreated: new Date()}}, {upsert: true}
    .then -> @AtBats.update {gameId: game._id, playerId: {$ne: result.hitter['player_id']}}, {$set: {active: false}}, {multi: true}

  enrichGame: (game, details) ->
    @logger.verbose "Enrich game (#{game.id})"

    @SportRadarGames.update {_id: game._id}, {$set: details}

  handlePlay: (game, result) ->
    player = result['hitter']
    playerId = player['player_id']
    play = result.playNumber
    bases = game.playersOnBase
    question = "End of #{player['first_name']} #{player['last_name']}'s at bat."

    @logger.verbose "Handle play of hitter (#{player['first_name']} #{player['last_name']})", {gameId: game.id, playerId: playerId}

    Promise.bind @
    .then -> @calculateMultipliersForPlay bases, playerId
    .then (multipliers) ->
      options =
        option1: {title: "Out", multiplier: multipliers['out'] }
        option2: {title: "Walk", multiplier: multipliers['walk'] }
        option3: {title: "Single", multiplier: multipliers['single'] }
        option4: {title: "Double", multiplier: multipliers['double'] }
        option5: {title: "Triple", multiplier: multipliers['triple'] }
        option6: {title: "Home Run", multiplier: multipliers['homerun'] }

      Promise.bind @
      .then -> @closeInactivePlays game, result
      .then -> @Questions.count {game_id: game.id, player_id: player['player_id'], atBatQuestion: true, play: play}
      .then (found) ->
        if not found
          Promise.bind @
          .then ->
            @Questions.insert
              game_id: game.id
              player_id: player['player_id']
              atBatQuestion: true
              play: play
              dateCreated: new Date()
              gameId: game['_id']
              playNumber: result.playNumber
              active: true
              player: player
              commercial: false
              que: question
              options: options
              _id: @Questions.db.ObjectId().toString()
              usersAnswered: []
          .tap ->
            questionId = result.upserted?[0]?._id
            @logger.info "Create play question (#{question})"
            @logger.verbose "Create play question (#{question})", {gameId: game.id, playerId: playerId, play: play, questionId: questionId}

  closeInactivePlays: (game, result) ->
    playNumber = result.playNumber

    Promise.bind @
    .then -> @Questions.find {game_id: game.id, active: true, atBatQuestion: true, play: {$ne: playNumber}}
    .map (question) ->
      play = result['plays'][question['play'] - 1]
      outcome = play.outcome

      map = _.invert _.mapObject question['options'], (option) -> option['title']
      outcomeOption = map[outcome]

      Promise.bind @
      .then -> @Questions.update {_id: question._id}, $set: {active: false, outcome: outcomeOption}
      .tap -> @logger.info "Close play question (#{question['que']}) with outcome (#{outcome})"
      .tap -> @logger.verbose "Close play question (#{question['que']}) with outcome (#{outcome})", {questionId: question['_id'], outcome: outcomeOption, play: question['play']}
      .then -> @Answers.update {questionId: question._id, answered: {$ne: outcomeOption}}, {$set: {outcome: "loose"}}, {multi: true}
      .tap (result) -> @logger.verbose "There are (#{result.n}) negative answer(s) for question (#{question['que']})"
      .then -> @Answers.find {questionId: question._id, answered: outcomeOption}
      .tap (answers) -> @logger.info "There are (#{answers.length}) positive answer(s) for question (#{question['que']})"
      .map (answer) ->
        reward = Math.floor answer['wager'] * answer['multiplier']
        Promise.bind @
        .then -> @Answers.update {_id: answer._id}, {$set: {outcome: "win"}}
        .then ->
          notificationId = chance.guid()
          @Users.update {_id: answer['userId']},
            $inc: {"profile.coins": reward}
            $push:
              pendingNotifications:
                _id: notificationId,
                type: "score",
                read: false,
                notificationId: notificationId,
                dateCreated: new Date(),
                message: "Nice Pickk! You got #{reward} Coins!",
                sharable: false,
                shareMessage: ""
        .tap -> @logger.verbose "Reward user (#{answer['userId']}) with coins (#{reward}) for question (#{question['que']})"

  handlePitch: (game, result) ->
    player = result['hitter']
    playerId = player['player_id']
    balls = result.balls
    strikes = result.strikes
    play = result.playNumber
    pitch = result.pitchNumber
    balls = result.balls
    strikes = result.strikes
    question = "#{player['first_name']} #{player['last_name']}: " + balls + " - " + strikes

    @logger.verbose "Handle pitch of hitter (#{player['first_name']} #{player['last_name']}) with count (#{balls} - #{strikes})",
      gameId: game.id
      playerId: playerId
      play: play
      pitch: pitch

    Promise.bind @
    .then -> @calculateMultipliersForPitch playerId, balls, strikes
    .then (multipliers) ->
      option1 = {title: "Strike", multiplier: multipliers['strike']}
      option2 = {title: "Ball", multiplier: multipliers['ball']}
      option3 = {title: "Hit", multiplier: multipliers['hit']}
      option4 = {title: "Out", multiplier: multipliers['out']}
      option5 = undefined

      if balls is 3
        option2.title = "Walk"

      if strikes is 2
        option1.title = "Strike Out"
        option3 = {title: "Foul Ball", multiplier: multipliers['foulball']}
        option4 = {title: "Hit", multiplier: multipliers['hit']}
        option5 = {title: "Out", multiplier: multipliers['out']}

      options = {option1, option2, option3, option4}
      options.option5 = option5 if option5

      Promise.bind @
      .then -> @closeInactivePitches game, result
      .then -> @Questions.count {game_id: game.id, player_id: player['player_id'], atBatQuestion: {$exists: false}, play: play, pitch: pitch}
      .then (found) ->
        if not found
          Promise.bind @
          .then ->
            @Questions.insert
              game_id: game.id
              player_id: player['player_id']
              play: play
              pitch: pitch
              dateCreated: new Date()
              gameId: game['_id']
              active: true
              player: player
              commercial: false
              que: question
              options: options
              _id: @Questions.db.ObjectId().toString()
              usersAnswered: []
          .tap ->
            questionId = result.upserted?[0]?._id
            @logger.info "Create pitch question (#{question})"
            @logger.verbose "Create pitch question (#{question})", {gameId: game.id, playerId: playerId, play: play, pitch: pitch, questionId: questionId}

  closeInactivePitches: (game, result) ->
    playNumber = result.playNumber
    pitchNumber = result.pitchNumber

    Promise.bind @
    .then -> @Questions.find {game_id: game.id, active: true, atBatQuestion: {$exists: false}, $or: [{play: {$ne: playNumber}}, {pitch: {$ne: pitchNumber}}]}
    .map (question) ->
      play = result['plays'][question['play'] - 1]
      outcome = play.pitches[question['pitch'] - 1]

      map = _.invert _.mapObject question['options'], (option) -> option['title']
      outcomeOption = map[outcome]

      Promise.bind @
      .then -> @Questions.update {_id: question._id}, $set: {active: false, outcome: outcomeOption}
      .tap -> @logger.info "Close pitch question (#{question['que']})  with outcome (#{outcome})"
      .tap -> @logger.verbose "Close pitch question (#{question['que']})  with outcome (#{outcome})", {questionId: question['_id'], outcome: outcomeOption, play: question['play'], pitch: question['pitch']}
      .then -> @Answers.update {questionId: question._id, answered: {$ne: outcomeOption}}, {$set: {outcome: "loose"}}, {multi: true}
      .tap (result) -> @logger.verbose "There are (#{result.n}) negative answer(s) for question (#{question['que']})"
      .then -> @Answers.find {questionId: question._id, answered: outcomeOption}
      .tap (answers) -> @logger.info "There are (#{answers.length}) positive answer(s) for question (#{question['que']})"
      .map (answer) ->
        reward = Math.floor answer['wager'] * answer['multiplier']
        Promise.bind @
        .then -> @Answers.update {_id: answer._id}, {$set: {outcome: "win"}}
        .then ->
          notificationId = chance.guid()
          @Users.update {_id: answer['userId']},
            $inc: {"profile.coins": reward}
            $push:
              pendingNotifications:
                _id: notificationId,
                type: "score",
                read: false,
                notificationId: notificationId,
                dateCreated: new Date(),
                message: "Nice Pickk! You got #{reward} Coins!",
                sharable: false,
                shareMessage: ""
        .tap -> @logger.verbose "Reward user (#{answer['userId']}) with coins (#{reward}) for question (#{question['que']})"

  calculateMultipliersForPlay: (bases, playerId) ->
    Promise.bind @
    .then -> @Players.findOne({_id: playerId})
    .then (player) ->
      # fallback
      return @getGenericMultipliersForPlay() if not player.stats

      stat = if player.stats.three_year['no_statistics_available_'] then player.stats.y2016extended else player.stats.three_year

      situation = switch true
        when bases.first and bases.second and bases.third then stat['bases_loaded']
        when bases.first then stat['runners_on']
        when bases.second and bases.third then stat['scoring_position']
        else stat['total']

      atBats = situation.ab
      avg = situation.avg
      hit = situation.h
      walk = parseInt(situation.bb)
      hitByBall = parseInt(situation.hbp)
      walkPercent = (walk + hitByBall ) / atBats
      homeRun = parseInt(situation.hr)
      homeRunPercent = homeRun / atBats
      triple = parseInt(situation.triple)
      triplePercent = triple / atBats
      double = parseInt(situation.double)
      doublePercent = double / atBats
      single = parseInt(hit - homeRun - double - triple)
      singlePercent = single / atBats
      outs = (atBats - hitByBall - walk - homeRun - triple - double - single)
      outPercent = outs / atBats

      outPercent = (100 - (outPercent*100).toFixed(2))
      walkPercent = (100 - (walkPercent*100).toFixed(2))
      singlePercent = (100 - (singlePercent*100).toFixed(2))
      doublePercent = (100 - (doublePercent*100).toFixed(2))
      triplePercent = (100 - (triplePercent*100).toFixed(2))
      homeRunPercent = (100 - (homeRunPercent*100).toFixed(2))

      toMultiplier = (value) =>
        switch true
          when value < 25 then @getRandomArbitrary 1.5, 1.95
          when value < 50 then @getRandomArbitrary 1.7, 2.3
          when value < 60 then @getRandomArbitrary 2.2, 2.7
          when value < 75 then @getRandomArbitrary 2.65, 3.15
          when value < 85 then @getRandomArbitrary 2.75, 3.35
          when value < 90 then @getRandomArbitrary 3.25, 3.75
          when value < 95 then @getRandomArbitrary 3.65, 3.95
          when value < 99 then @getRandomArbitrary 3.95, 4.5
          else @getRandomArbitrary 5.5, 7

      out: toMultiplier outPercent
      walk: toMultiplier walkPercent
      single: toMultiplier singlePercent
      double: toMultiplier doublePercent
      triple: toMultiplier triplePercent
      homerun: toMultiplier homeRunPercent

  calculateMultipliersForPitch: (playerId, balls, strikes) ->
    Promise.bind @
    .then -> @Players.findOne({_id: playerId})
    .then (player) ->
      # fallback
      return @getGenericMultipliersForPitch() if not player.stats

      stat = if player.stats.three_year['no_statistics_available_'] then player.stats.y2016extended else player.stats.three_year
      totalAtBat = stat.total['ab']

      currentPlayKey = "count_#{balls}_#{strikes}"
      play = stat[currentPlayKey] or player.stats.career
      playEoP = play['ab']

      # End of Play probability
      EoP = parseInt(playEoP) / parseInt(totalAtBat)
      remainingPercent = 1 - EoP
      hitPercent = play['avg'] * EoP
      outPercent = (1 - hitPercent) * EoP

      if strikes is 2
        option1EoP = play['so']
      else
        nextPlayKey = "count_#{balls}_#{strikes + 1}"
        nextPlay = stat[nextPlayKey]
        option1EoP = nextPlay?['ab'] or 1

      if balls is 3
        option2EoP = play['bb']
      else
        nextPlayKey = "count_#{balls + 1}_#{strikes}"
        nextPlay = stat[nextPlayKey]
        option2EoP = nextPlay?['ab'] or 1

      option1EoP = parseInt option1EoP
      option2EoP = parseInt option2EoP
      combinedEoP = option1EoP + option2EoP
      option1EoPPercentage = (( option1EoP / combinedEoP ) * remainingPercent).toFixed(4)
      option2EoPPercentage = (( option2EoP / combinedEoP ) * remainingPercent).toFixed(4)

      strikePercent = (100 - (option1EoPPercentage * 100).toFixed(2))
      ballPercent = (100 - (option2EoPPercentage *100).toFixed(2))
      outPercent = (100 - (outPercent*100).toFixed(2))
      hitPercent = (100 - (hitPercent*100).toFixed(2))

      toMultiplier = (value) =>
        switch true
          when value < 25 then @getRandomArbitrary 1.15,1.25
          when value < 50 then @getRandomArbitrary 1.25, 1.5
          when value < 60 then @getRandomArbitrary 1.5,1.75
          when value < 75 then @getRandomArbitrary 1.75, 2.25
          when value < 85 then @getRandomArbitrary 2.25, 2.75
          when value < 90 then @getRandomArbitrary 2.75, 3.5
          else @getRandomArbitrary 3.5, 4.5

      strike: toMultiplier strikePercent
      ball: toMultiplier ballPercent
      out: toMultiplier outPercent
      hit: toMultiplier hitPercent
      foulball: @getRandomArbitrary(1.5, 2)

  getGenericMultipliersForPlay: ->
    out: @getRandomArbitrary 1.05, 1.65
    walk: @getRandomArbitrary 1.05, 1.65
    single: @getRandomArbitrary 1.05, 1.65
    double: @getRandomArbitrary 1.05, 1.65
    triple: @getRandomArbitrary 1.05, 1.65
    homerun: @getRandomArbitrary 1.05, 1.65

  getGenericMultipliersForPitch: ->
    strike: @getRandomArbitrary 1.05, 1.65
    ball: @getRandomArbitrary 1.05, 1.65
    out: @getRandomArbitrary 1.05, 1.65
    hit: @getRandomArbitrary 1.05, 1.65
    foulball: @getRandomArbitrary 1.05, 1.65

  getRandomArbitrary: (min, max) -> parseFloat((Math.random() * (max - min) + min).toFixed(2))
