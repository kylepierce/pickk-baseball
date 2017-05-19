SportRadar = require "../lib/api/SportRadar"
Match = require "mtr-match"

module.exports = (options) ->
  Match.check options, Object
  console.log options
  new SportRadar(options)
