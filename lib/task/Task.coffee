Match = require "mtr-match"
Observable = require "./Observable"

module.exports = class extends Observable 
  constructor: (dependencies) ->
    super

    Match.check dependencies, Object
    
    @dependencies = dependencies
