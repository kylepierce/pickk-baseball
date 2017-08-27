_ = require "underscore"
Match = require "mtr-match"
Promise = require "bluebird"
Task = require "./Task"
moment = require "moment"

module.exports = class extends Task
  constructor: (dependencies) ->
    super

    Match.check dependencies, Match.ObjectIncluding
      mongodb: Match.Any

    @Games = @dependencies.mongodb.collection("games")
    @logger = @dependencies.logger

  execute: ->
    Promise.bind @
      .then -> @Games.find {sport: "MLB", manual: {$exists: false}, $or: [{status: "In-Progress"}, {close_processed: false}]}
