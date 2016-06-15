createMongoDB = require "promised-mongo"
Match = require "mtr-match"

module.exports = (options) ->
  Match.check options,
    url: String
  createMongoDB(options.url)