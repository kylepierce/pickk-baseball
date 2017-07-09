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
    @GamePlayed = dependencies.mongodb.collection("gamePlayed")
    @Users = dependencies.mongodb.collection("users")
    @Notifications = dependencies.mongodb.collection("notifications")
    @gameParser = new GameParser dependencies

  execute: (parms) ->
    # Requirements: gameId, gameName, inning, inningDivision, oldPlayer, oldInning, newInning, atBatId, team
    if parms.oldInning isnt parms.newInning
      console.log "---------------------------\n", "New inning!!!!!!", "---------------------------\n"

      Promise.bind @
        .then -> @handleCommercialBreak parms
        .then -> @resolveCommercialQuestions parms, true
        .then -> @createCommercialQuestions gameId, inning, team

  handleCommercialBreak: (parms) ->
    #Requirements: gameId, gameName
    if not parms.commercial
      Promise.bind @
      .then -> @SportRadarGames.update {_id: parms.gameId}, {$set: {commercial: true, commercialStartedAt: new Date()}}
      .tap -> @logger.verbose "Commercial flag has been set for game (#{parms.gameName})"

  resolveCommercialQuestions: (parms, inningCompleted, event) ->
    # Requirements: gameId, inning, inningDivision, inningCompleted, event
    Promise.bind @
      .then -> @Questions.find {gameId: parms.gameId, commercial: true, processed: false, active: null, inning: parms.inning, inningDivision: parms.inningDivision
      }.map (question) ->
        if inningCompleted is true
          @rewardForCommercialQuestion parms.gameId, question, false
        else
          list = question['outcomes']
          onList = list.indexOf event['pbpDetailId']
          if (onList) > -1
            @rewardForCommercialQuestion parms.gameId, question, true

  rewardForCommercialQuestion: (gameId, question, correct) ->
    # Requirements: gameId, question Object, correct
    if correct
      outcome = "option1"
    else if !correct
      outcome = "option2"

    Promise.bind @
      .then -> @Questions.update {_id: question._id}, {$set: {active: false, outcome: outcome, processed: true, lastUpdated: new Date()}}
      .then -> @Answers.update {questionId: question._id, answered: {$ne: outcome}}, {$set: {outcome: "lose"}}, {multi: true}
      .then -> @Answers.find {questionId: question._id, answered: outcome}
      .map (answer) ->
        reward = @dependencies.settings['common']['commercialReward']
        Promise.bind @
        .then -> @Answers.update {_id: answer._id}, {$set: {outcome: "win"}}
        .then -> @GamePlayed.update {userId: answer['userId'], gameId: gameId}, {$inc: {coins: reward}}
        .then ->
          notificationId = chance.guid()
          @Notifications.insert
            _id: notificationId
            userId: answer['userId']
            gameId: gameId
            type: "coins"
            value: reward
            read: false
            notificationId: notificationId
            dateCreated: new Date()
            message: "Nice Pickk! You got #{reward} Coins!"
            sharable: false
            shareMessage: ""
        # .tap -> @logger.verbose "Reward user (#{answer['userId']}) with coins (#{reward}) for question (#{question['que']})"
        # .tap -> @logger.verbose "Outcome of the question... ", question

  createCommercialQuestions: (parms) ->
    #Requires gameId, inning, team Object with id and nickname
    templates = [
      title: "Hit a Single"
      outcomes: [1, 2, 3, 4, 5, 6, 122]
    ,
      title: "Hit a Double"
      outcomes: [7, 8, 9, 10, 11, 123]
    ,
      title: "Hit a Triple"
      outcomes: [12, 13, 124]
    ,
      title: "Hit a Home Run"
      outcomes: [15, 16, 17, 18]
    ,
      title: "Steal a Base"
      outcomes: [15, 16, 17, 18]
    ,
      title: "Get Hit by a Pitch"
      outcomes: ["61"]
    ]

    Promise.bind @
      .return parms.team
      .then (team) ->
        name = team.nickname
        inningGrammer = "Th"
        templates = _.sample templates, 2
        Promise.all (for template in templates
          do (template) =>
            text = "Will #{name} #{template.title} in the #{inning}#{inningGrammer} inning?"

            options =
              option1: {title: "True", number: 1, multiplier: 4}
              option2: {title: "False",  number: 2, multiplier: 4}

            Promise.bind @
            .then ->
              @Questions.insert
                _id: @Questions.db.ObjectId().toString()
                que: text
                type: "freePickk"
                game_id: parms.gameId
                gameId: parms.gameId
                teamId: team.teamId
                inningDivision: parms.inningDivision
                inning: parms.inning
                period: 0
                dateCreated: new Date()
                active: true
                processed: false
                commercial: true
                binaryChoice: true
                options: options
                outcomes: template.outcomes
                usersAnswered: []
            .tap ->
              @logger.verbose "Create commercial question '#{text}' for the game (#{game.name})"
        )

  closeActiveCommercialQuestions: (gameId, gameName) ->
    Promise.bind @
    .then -> @Questions.find {commercial: true, game_id: gameId, active: true}
    .map (question) ->
      Promise.bind @
      .then -> @Questions.update {_id: question._id}, {$set: {active: null, lastUpdated: new Date()}}
      .tap ->
        @logger.info "Close commercial question '#{question['que']}' for the game (#{gameName})"
