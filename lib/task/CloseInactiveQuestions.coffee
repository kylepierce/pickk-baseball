_ = require "underscore"
Match = require "mtr-match"
Promise = require "bluebird"
Task = require "./Task"

module.exports = class extends Task
  constructor: (dependencies) ->
    super

    Match.check dependencies, Match.ObjectIncluding
      mongodb: Match.Any

    @Games = @dependencies.mongodb.collection("games")
    @Questions = @dependencies.mongodb.collection("questions")
    @logger = @dependencies.logger

  execute: ->
    Promise.bind @
    .tap -> @logger.verbose "Start CloseInactiveQuestions"
    .then -> @Games.find {status: "inprogress"}, {_id: 1}
    .then (games) -> _.pluck games, "_id"
    .tap (ids) -> @logger.verbose "Close questions related to games not equal [#{ids}]"
    .then (ids) -> @Questions.update {gameId: {$nin: ids}, active: true}, {$set: {active: false}}, {multi: true}
    .tap (result) -> @logger.verbose result, "#{result.nModified} questions have been closed as inactive"
    .tap -> @logger.verbose "End CloseInactiveQuestions"

