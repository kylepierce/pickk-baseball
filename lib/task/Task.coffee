Match = require "mtr-match"

module.exports = class 
  constructor: (dependencies) ->
    Match.check dependencies, Object
    
    @dependencies = dependencies
