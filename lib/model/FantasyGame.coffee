Match = require "mtr-match"
_ = require "underscore"

module.exports = class
  constructor: (data) ->
    Match.check data, Object

    _.extend @, data

  getSelector: ->
    "Game.GameID": @["Game"]["GameID"]
