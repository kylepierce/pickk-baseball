createDependencies = require "../../../../helper/dependencies"
settings = (require "../../../../helper/settings")("#{process.env.ROOT_DIR}/settings/test.json")
Promise = require "bluebird"
moment = require "moment"
UpdateTeam = require "../../../../lib/task/sportRadar/UpdateTeam"
loadFixtures = require "../../../../helper/loadFixtures"
#sportRadarGamesFixtures = require "#{process.env.ROOT_DIR}/test/fixtures/task/sportRadar/importGames/collection/SportRadarGames.json"
#sportRadarGamesWithInningsFixtures = require "#{process.env.ROOT_DIR}/test/fixtures/task/sportRadar/importGames/collection/SportRadarGamesWithInnings.json"

describe "Import detailed information about teams and players", ->
  dependencies = createDependencies settings, "PickkImport"
  mongodb = dependencies.mongodb

  updateTeam = undefined
  Teams = mongodb.collection("teams")
  Players = mongodb.collection("players")

  teamId = "833a51a9-0d84-410f-bd77-da08c3e5e26e"

  beforeEach ->
    updateTeam = new UpdateTeam dependencies

    Promise.bind @
    .then ->
      Promise.all [
        Teams.remove()
        Players.remove()
      ]

  it 'should import a team and its players', ->
    @timeout 30000

    playerNumber = undefined

    new Promise (resolve, reject) ->
      nock.back "test/fixtures/task/sportRadar/updateTeam/request/team.json", (recordingDone) ->
        Promise.bind @
        .then -> dependencies.sportRadar.getTeamProfile teamId
        .then (result) -> playerNumber = result.players.length
        .then -> updateTeam.execute teamId
        .then -> Teams.count()
        .then (count) ->
          count.should.be.equal 1
        .then -> Teams.findOne({_id: teamId})
        .then (team) ->
          should.exist team

          {nickname} = team
          should.exist nickname
          nickname.should.be.equal "Royals"
        .then -> Players.count()
        .then (count) ->
          count.should.be.equal 40
        .then -> Players.findOne({_id: "9baf07d4-b1cb-4494-8c95-600d9e8de1a9"})
        .then (player) ->
          should.exist player

          {team, name, stats} = player
          should.exist team
          team.should.be.equal teamId

          should.exist name
          name.should.be.equal "Salvador Perez"

          should.exist stats
          console.log stats
        .then @assertScopesFinished
        .then resolve
        .catch reject
        .finally recordingDone
