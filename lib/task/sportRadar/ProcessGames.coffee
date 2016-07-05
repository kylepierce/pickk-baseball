_ = require "underscore"
Match = require "mtr-match"
Promise = require "bluebird"
Task = require "../Task"
SportRadarGame = require "../../model/sportRadar/SportRadarGame"
Team = require "../../model/Team"
Player = require "../../model/Player"
GameParser = require "./helper/GameParser"
moment = require "moment"

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
    @gameParser = new GameParser dependencies

  execute: ->
    Promise.bind @
    .tap -> @logger.verbose "Start ProcessGames task"
    .then -> @getActiveGames()
    .tap (games) -> @logger.verbose "ProcessGames: There are #{games.length} active game(s)"
    .tap @closeQuestionsForInactiveGames
    .map @handleGame, {concurrency: 1} # to sort questions properly on the client
    .return true

  getActiveGames: ->
    @SportRadarGames.find({status: "inprogress"})

  closeQuestionsForInactiveGames: (activeGames) ->
    ids = _.pluck activeGames, "id"

    Promise.bind @
    .then -> @Questions.update {game_id: {$nin: ids}, active: true}, {$set: {active: false}}, {multi: true}
    .tap (updated) -> @logger.verbose "ProcessGames: #{updated['nModified']} questions have been closed as inactive"

  handleGame: (game) ->
    result = @gameParser.getPlay game

    if result
      Promise.bind @
      .then -> @handleTeams game, result.teams
      .then -> @handlePlayers game, result.players
      .then -> @handlePlay game, result
      .then -> @handlePitch game, result

  handleTeams: (game, teams) ->
    @logger.verbose "Handle teams of game (#{game.id})"

    Promise.all (for data in _.values teams
      team = new Team data
      @Teams.update team.getSelector(), {$set: team}, {upsert: true}
    )

  handlePlayers: (game, players) ->
    @logger.verbose "Handle players of game (#{game.id})"

    Promise.all (for data in players
      player = new Player data
      @Players.update player.getSelector(), {$set: player}, {upsert: true}
    )

  handlePlay: (game, result) ->
    @logger.verbose "Handle play of game (#{game.id}) for player(#{result['hitter']['player_id']})"

    player = result['hitter']
    question = "End of #{player['first_name']} #{player['last_name']}'s at bat."

    options =
      option1: {title: "Out", multiplier: 2.1 }
      option2: {title: "Walk", multiplier: 2.2 }
      option3: {title: "Single", multiplier: 2.3 }
      option4: {title: "Double", multiplier: 2.4 }
      option5: {title: "Triple", multiplier: 2.3 }
      option6: {title: "Home Run", multiplier: 2.4 }

    Promise.bind @
    .then ->
      @Questions.update {game_id: game.id, player_id: player['player_id'], atBatQuestion: true},
        $set:
          dateCreated: new Date()
          gameId: game['_id']
          active: true
          player: player
          commercial: false
          que: question
          options: options
      , {upsert: true}
    .tap -> @logger.verbose "Upsert play question \"#{question}\" with game(#{game.id}) and playerId(#{player['player_id']})"
    .then -> @closeInactivePlays game, player

  closeInactivePlays: (game, player) ->
    Promise.bind @
    .then ->
      @Questions.update {game_id: game.id, player_id: {$ne: player['player_id']}, active: true, atBatQuestion: true},
        $set: {active: false},
        {multi: true}
    .tap (updated) -> @logger.verbose "ProcessGames: #{updated['nModified']} play questions have been closed as inactive"

  handlePitch: (game, result) ->
    @logger.verbose "Handle pitch of game (#{game.id}) for player(#{result['hitter']['player_id']})"

    player = result['hitter']
    balls = result.balls
    strikes = result.strikes

    balls = result.balls
    strikes = result.strikes
    question = "#{player['first_name']} #{player['last_name']}: " + balls + " - " + strikes

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
      option1: { title: title1, multiplier: 1.45 }
      option2: { title: title2, multiplier: 1.65 }
      option3: { title: title3, multiplier: 7.35 }
      option4: { title: title4, multiplier: 3.23 }

    options.option5 = {title: title5, multiplier: 1 } if title5

    Promise.bind @
    .then ->
      @Questions.update {game_id: game.id, player_id: player['player_id'], atBatQuestion: {$exists: false}},
        $set:
          dateCreated: new Date()
          gameId: game['_id']
          active: true
          player: player
          commercial: false
          que: question
          options: options
      , {upsert: true}
    .tap -> @logger.verbose "Upsert pitch question \"#{question}\" with game(#{game.id}) and playerId(#{player['player_id']})"
    .then -> @closeInactivePitches game, player

  closeInactivePitches: (game, player) ->
    Promise.bind @
    .then ->
      @Questions.update {game_id: game.id, player_id: {$ne: player['player_id']}, active: true, atBatQuestion: {$exists: false}},
        $set: {active: false},
        {multi: true}
    .tap (updated) -> @logger.verbose "ProcessGames: #{updated['nModified']} pitch questions have been closed as inactive"
