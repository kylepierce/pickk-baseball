createDependencies = require "../../../../helper/dependencies"
settings = (require "../../../../helper/settings")("#{process.env.ROOT_DIR}/settings/test.json")
Promise = require "bluebird"
moment = require "moment"
ImportGames = require "../../../../lib/task/sportRadar/ImportGames"
loadFixtures = require "../../../../helper/loadFixtures"
sportRadarGamesFixtures = require "#{process.env.ROOT_DIR}/test/fixtures/task/sportRadar/importGames/collection/SportRadarGames.json"
sportRadarGamesWithInningsFixtures = require "#{process.env.ROOT_DIR}/test/fixtures/task/sportRadar/importGames/collection/SportRadarGamesWithInnings.json"
SportRadarGame = require "../../../../lib/model/sportRadar/SportRadarGame"

UpdateGamesStrategy = require "../../../../lib/strategy/sportRadar/UpdateGamesStrategy"


describe "Import brief information about games for date specified from SportRadar to Mongo", ->
  dependencies = createDependencies settings, "PickkImport"
  mongodb = dependencies.mongodb

  updateGamesStrategy = new UpdateGamesStrategy dependencies
  SportRadarGames = mongodb.collection("games")

  beforeEach ->
    Promise.bind @
    .then ->
      Promise.all [
        SportRadarGames.remove()
      ]
