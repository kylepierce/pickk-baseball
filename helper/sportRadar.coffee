SportRadar = require "../lib/api/SportRadar"
Match = require "mtr-match"

module.exports = (options) ->
  Match.check options, Object

  new SportRadar(options)
