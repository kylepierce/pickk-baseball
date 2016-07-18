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
    @logger = @dependencies.logger

  execute: ->
    Promise.bind @
    .then -> @Games.find {status: "inprogress"}
    .tap (games) -> @logger.verbose "There are #{games.length} active games" 

