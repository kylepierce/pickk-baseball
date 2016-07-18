_ = require "underscore"
createDependencies = require "../../../helper/dependencies"
settings = (require "../../../helper/settings")("#{process.env.ROOT_DIR}/settings/test.json")
Promise = require "bluebird"
GetActiveGames = require "../../../lib/task/GetActiveGames"
loadFixtures = require "../../../helper/loadFixtures"
gamesFixtures = require "#{process.env.ROOT_DIR}/test/fixtures/task/getActiveGames/collection/games.json"
noActiveGamesFixtures = require "#{process.env.ROOT_DIR}/test/fixtures/task/getActiveGames/collection/no_active_games.json"

describe "Fetch active games from Mongo", ->
  dependencies = createDependencies settings, "PickkImport"
  mongodb = dependencies.mongodb

  getActiveGames = new GetActiveGames dependencies
  SportRadarGames = mongodb.collection("games")

  beforeEach ->
    Promise.bind @
    .then ->
      Promise.all [
        SportRadarGames.remove()
      ]

  it 'should fetch all active games from the collection', ->
    Promise.bind @
    .then -> loadFixtures gamesFixtures, mongodb
    .then -> getActiveGames.execute()
    .then (games) ->
      should.exist games

      games.should.be.an "array"
      games.length.should.be.equal 2

      ids = _.pluck games, "id"
      (id in ids).should.be.equal true for id in ["fec58a7a-eff7-4eec-9535-f64c42cc4944", "fec58a7a-eff7-4eec-9535-f64c42cc4870"]

  it 'should return an empty array if there is no active games at the moment', ->
    Promise.bind @
    .then -> loadFixtures noActiveGamesFixtures, mongodb
    .then -> getActiveGames.execute()
    .then (games) ->
      should.exist games

      games.should.be.an "array"
      games.length.should.be.equal 0
