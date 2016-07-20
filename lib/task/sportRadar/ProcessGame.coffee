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
      .then -> @handleTeams game, result.teams
      .then -> @handlePlayers game, result.players
      .then -> @handlePlay game, result
      .then -> @handlePitch game, result
      .then -> @handleAtBat game, result

  handleAtBat: (game, result) ->
    Promise.bind @
    .then -> @AtBats.update {gameId: game._id, playerId: result.hitter['player_id'], active: true}, {$set: {ballCount: result.balls, strikeCount: result.strikes, dateCreated: new Date()}}, {upsert: true}
    .then -> @AtBats.update {gameId: game._id, playerId: {$ne: result.hitter['player_id']}}, {$set: {active: false}}, {multi: true}

  handleTeams: (game, teams) ->
    @logger.verbose "Handle teams of game (#{game.id})"

    Promise.all (for data in _.values teams
      Promise.bind @
      .return new Team(data)
      .then (team) ->
        Promise.bind @
        .then -> @Teams.update team.getSelector(), {$set: team}, {upsert: true}
        .tap (result) ->
          if not result['nModified']
            @logger.verbose "Update team (#{team.fullName})", {gameId: game.id}
          else
            teamId = result.upserted?[0]?._id
            @logger.info "Create team (#{team.fullName})"
            @logger.verbose "Create team (#{team.fullName})", {gameId: game.id, teamId: teamId}
    )

  enrichGame: (game, details) ->
    @logger.verbose "Enrich game (#{game.id})"

    @SportRadarGames.update {_id: game._id}, {$set: details}

  handlePlayers: (game, players) ->
    @logger.verbose "Handle players of game (#{game.id})"

    Promise.all (for data in players
      Promise.bind @
      .return new Player(data)
      .then (player) ->
        Promise.bind @
        .then -> @Players.update player.getSelector(), {$set: player}, {upsert: true}
        .tap (result) ->
          if not result['nModified']
            @logger.verbose "Update player (#{player.name})", {gameId: game.id}
          else
            playerId = result.upserted?[0]?._id
            @logger.info "Create player (#{player.name})"
            @logger.verbose "Create player (#{player.name})", {gameId: game.id, playerId: playerId}
    )

  handlePlay: (game, result) ->
    player = result['hitter']
    playerId = player['player_id']
    play = result.playNumber
    question = "End of #{player['first_name']} #{player['last_name']}'s at bat."

    @logger.verbose "Handle play of hitter (#{player['first_name']} #{player['last_name']})", {gameId: game.id, playerId: playerId}

    options =
      option1: {title: "Out", multiplier: 2.1 }
      option2: {title: "Walk", multiplier: 2.2 }
      option3: {title: "Single", multiplier: 2.3 }
      option4: {title: "Double", multiplier: 2.4 }
      option5: {title: "Triple", multiplier: 2.3 }
      option6: {title: "Home Run", multiplier: 2.4 }

    Promise.bind @
    .then -> @closeInactivePlays game, result
    .then ->
      @Questions.update {game_id: game.id, player_id: player['player_id'], atBatQuestion: true, play: play},
        $set:
          dateCreated: new Date()
          gameId: game['_id']
          playNumber: result.playNumber
          active: true
          player: player
          commercial: false
          que: question
          options: options
        $setOnInsert:
          _id: @Questions.db.ObjectId().toString()
          usersAnswered: []
      , {upsert: true}
    .tap (result) ->
      if not result['upserted']
        @logger.verbose "Update play question (#{question})", {gameId: game.id, playerId: playerId, play: play}
      else
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
        .then -> @Users.update {_id: answer['userId']}, {$inc: {"profile.coins": reward}}
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


    title1 = "Strike"
    title2 = "Ball"
    title3 = "Hit"
    title4 = "Out"
    title5 = undefined

    if balls is 3
      title2 = "Walk"

    if strikes is 2
      title1 = "Strike Out"
      title3 = "Foul Ball"
      title4 = "Hit"
      title5 = "Out"

    options =
      option1: { title: title1, multiplier: 1.45 }
      option2: { title: title2, multiplier: 1.65 }
      option3: { title: title3, multiplier: 7.35 }
      option4: { title: title4, multiplier: 3.23 }

    options.option5 = { title: title5, multiplier: 1 } if title5

    Promise.bind @
    .then -> @closeInactivePitches game, result
    .then ->
      @Questions.update {game_id: game.id, player_id: player['player_id'], atBatQuestion: {$exists: false}, play: play, pitch: pitch},
        $set:
          dateCreated: new Date()
          gameId: game['_id']
          active: true
          player: player
          commercial: false
          que: question
          options: options
        $setOnInsert:
          _id: @Questions.db.ObjectId().toString()
          usersAnswered: []
      , {upsert: true}
    .tap (result) ->
      if not result['upserted']
        @logger.verbose "Update pitch question (#{question})", {gameId: game.id, playerId: playerId, play: play, pitch: pitch}
      else
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
        .then -> @Users.update {_id: answer['userId']}, {$inc: {"profile.coins": reward}}
        .tap -> @logger.verbose "Reward user (#{answer['userId']}) with coins (#{reward}) for question (#{question['que']})"
