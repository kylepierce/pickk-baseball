_ = require "underscore"
Match = require "mtr-match"
Promise = require "bluebird"
Strategy = require "../Strategy"
ImportGames = require "../../task/sportRadar/ImportGames"
GetActiveGames = require "../../task/GetActiveGames"
ImportGameDetails = require "../../task/sportRadar/ImportGameDetails"
CloseInactiveAtBats = require "../../task/CloseInactiveAtBats"
CloseInactiveQuestions = require "../../task/CloseInactiveQuestions"
ProcessGame = require "../../task/sportRadar/ProcessGame"
promiseRetry = require 'promise-retry'

module.exports = class extends Strategy
  constructor: (dependencies) ->
    super

    @importGames = new ImportGames dependencies
    @getActiveGames = new GetActiveGames dependencies
    @importGameDetails = new ImportGameDetails dependencies
    @closeInactiveAtBats = new CloseInactiveAtBats dependencies
    @closeInactiveQuestions = new CloseInactiveQuestions dependencies
    @processGame = new ProcessGame dependencies

    @logger = dependencies.logger

  execute: ->
    # do not allow it to crash!
    # Test importanting data without live server
    # @game =
    #   _id: "59083b877fd19f536d726f45"
    #   commercialBreak: false,
    #   sequence: 8,
    #   lastUpdated: "2017-04-30T23:51:02.265Z",
    #   lastCount: [
    #     {
    #       sequence: 1,
    #       result: "B",
    #       balls: 0,
    #       strikes: 0
    #     },
    #     {
    #       sequence: 2,
    #       result: "H",
    #       balls: 1,
    #       strikes: 0
    #     }
    #   ],
    #   eventStatus: {
    #     eventStatusId: 2,
    #     isUnderReview: false,
    #     balls: 1,
    #     strikes: 0,
    #     outs: 2,
    #     inning: 12,
    #     inningDivision: "Bottom",
    #     isActive: true,
    #     name: "In-Progress",
    #     runnersOnBase: [
    #       {
    #         baseNumber: 2,
    #       }
    #     ]
    #   },
    #   events: 119,
    #   hitter: {
    #     playerId: 254756,
    #     firstName: "Chris",
    #     lastName: "Iannetta",
    #     uniform: 8,
    #     battingSlot: 7,
    #     endBase: 0,
    #     batSide: {
    #       handId: 2,
    #       name: "Right"
    #     }
    #   },
    #   playerId: 254756,
    #   outs: 2,
    #   halfs: 23,
    #   inning: 12
    # @result =
    #   old:
    #     _id: "59083b877fd19f536d726f45"
    #     commercialBreak: false,
    #     sequence: 8,
    #     lastUpdated: "2017-04-30T23:51:02.265Z",
    #     lastCount: [
    #       {
    #         sequence: 1,
    #         result: "B",
    #         balls: 0,
    #         strikes: 0
    #       },
    #       {
    #         sequence: 2,
    #         result: "H",
    #         balls: 1,
    #         strikes: 0
    #       }
    #     ],
    #     events: 119,
    #     hitter: {
    #       playerId: 254756,
    #       firstName: "Chris",
    #       lastName: "Iannetta",
    #       uniform: 8,
    #       battingSlot: 7,
    #       endBase: 0,
    #       batSide: {
    #         handId: 2,
    #         name: "Right"
    #       }
    #     },
    #     playerId: 254756,
    #     outs: 2,
    #     halfs: 23,
    #     inning: 12

    promiseRetry {retries: 1000, factor: 1}, (retry) =>
      Promise.bind @
      .then -> @processGame.execute @game, @result
      # .then -> @importGames.execute()
      # .then -> @closeInactiveQuestions.execute() # This just closes the questions. It does not award the users.
      # .then -> @closeInactiveAtBats.execute() # This just closes the questions. It does not award the users.
      # .then -> @getActiveGames.execute()
      # .map (game) ->
      #   Promise.bind @
      #   .then -> @importGameDetails.execute game['eventId']
      #   .then (result) -> @processGame.execute game, result
      # , {concurrency: 1} #❗️ This is probably causing the issue. Its updating the file after starting the process. Game is the new data.
      # .catch (error) =>
      #   @logger.error error.message, _.extend({stack: error.stack}, error.details)
      #   retry error
