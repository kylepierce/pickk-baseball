createDependencies = require "../../../../helper/dependencies"
settings = (require "../../../../helper/settings")("#{process.env.ROOT_DIR}/settings/test.json")
Promise = require "bluebird"
moment = require "moment"
UpdateTeam = require "../../../../lib/task/sportRadar/UpdateTeam"
loadFixtures = require "../../../../helper/loadFixtures"
ExistingTeamFixtures = require "#{process.env.ROOT_DIR}/test/fixtures/task/sportRadar/updateTeam/collection/ExistingTeam.json"
ExistingPlayerFixtures = require "#{process.env.ROOT_DIR}/test/fixtures/task/sportRadar/updateTeam/collection/ExistingPlayer.json"

describe "Import detailed information about teams and players", ->
  dependencies = createDependencies settings, "PickkImport"
  mongodb = dependencies.mongodb

  updateTeam = undefined
  Teams = mongodb.collection("teams")
  Players = mongodb.collection("players")

  teamId = "833a51a9-0d84-410f-bd77-da08c3e5e26e"
  playerId = "9baf07d4-b1cb-4494-8c95-600d9e8de1a9"

  beforeEach ->
    updateTeam = new UpdateTeam dependencies

    Promise.bind @
    .then ->
      Promise.all [
        Teams.remove()
        Players.remove()
      ]

  it 'should import a team and its players', ->
    @timeout 300000

    playerNumber = undefined

    new Promise (resolve, reject) ->
      nock.back "test/fixtures/task/sportRadar/updateTeam/request/create.json", (recordingDone) ->
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

          {nickname, updatedAt} = team
          should.exist nickname
          nickname.should.be.equal "Royals"

          should.exist updatedAt
          updatedAt.should.be.a "date"
          (moment().diff(updatedAt, 'hour') is 0).should.be.equal true
        .then -> Players.count()
        .then (count) ->
          count.should.be.equal 40
        .then -> Players.findOne({_id: playerId})
        .then (player) ->
          should.exist player

          {team, name, stats} = player
          should.exist team
          team.should.be.equal teamId

          should.exist name
          name.should.be.equal "Salvador Perez"

          should.exist stats
          {three_year} = stats
          should.exist three_year
          three_year.should.be.an "object"

          {bases_loaded} = three_year
          should.exist bases_loaded
          bases_loaded.should.be.an "object"

          {avg} = bases_loaded
          should.exist avg
          avg.should.be.equal ".238"
        .then @assertScopesFinished
        .then resolve
        .catch reject
        .finally recordingDone

  it "shouldn't update existing team because it's up to date", ->
    @timeout 30000

    recently = moment().subtract(2, 'hour').toDate()

    new Promise (resolve, reject) ->
      nock.back "test/fixtures/task/sportRadar/updateTeam/request/empty.json", (recordingDone) ->
        Promise.bind @
        .then -> loadFixtures ExistingTeamFixtures, mongodb
        .then -> Teams.update({_id: teamId}, {$set: {updatedAt: recently}})
        .then -> updateTeam.execute teamId
        .then -> Teams.count()
        .then (count) ->
          count.should.be.equal 1
        .then -> Teams.findOne({_id: teamId})
        .then (team) ->
          should.exist team

          # fake nickname should be present
          {nickname} = team
          should.exist nickname
          nickname.should.be.equal "Stanford Rockies"
        .then @assertScopesFinished
        .then resolve
        .catch reject
        .finally recordingDone

  it "should update existed team because its data is out-of-date", ->
    @timeout 30000

    late = moment().subtract(2, 'day').toDate()

    new Promise (resolve, reject) ->
      nock.back "test/fixtures/task/sportRadar/updateTeam/request/update.json", (recordingDone) ->
        Promise.bind @
        .then -> loadFixtures ExistingTeamFixtures, mongodb
        .then -> Teams.update({_id: teamId}, {$set: {updatedAt: late}})
        .then -> updateTeam.execute teamId
        .then -> Teams.count()
        .then (count) ->
          count.should.be.equal 1
        .then -> Teams.findOne({_id: teamId})
        .then (team) ->
          should.exist team

          # nickname should be updated on a real one
          {nickname} = team
          should.exist nickname
          nickname.should.be.equal "Royals"
        .then @assertScopesFinished
        .then resolve
        .catch reject
        .finally recordingDone

  it "shouldn't update existing player because it's up to date", ->
    @timeout 30000

    recently = moment().subtract(2, 'hour').toDate()

    new Promise (resolve, reject) ->
      nock.back "test/fixtures/task/sportRadar/updateTeam/request/empty.json", (recordingDone) ->
        Promise.bind @
        .then -> loadFixtures ExistingTeamFixtures, mongodb
        .then -> loadFixtures ExistingPlayerFixtures, mongodb
        .then -> Players.update({_id: playerId}, {$set: {updatedAt: recently}})
        .then -> updateTeam.execute teamId
        .then -> Teams.count()
        .then (count) ->
          count.should.be.equal 1
        .then -> Players.findOne({_id: playerId})
        .then (player) ->
          should.exist player

          # fake nickname should be present
          {firstName} = player
          should.exist firstName
          firstName.should.be.equal "John"
        .then @assertScopesFinished
        .then resolve
        .catch reject
        .finally recordingDone

  it "should update existing player because its data is out-of-date", ->
    @timeout 30000

    late = moment().subtract(2, 'day').toDate()

    new Promise (resolve, reject) ->
      nock.back "test/fixtures/task/sportRadar/updateTeam/request/empty.json", (recordingDone) ->
        Promise.bind @
        .then -> loadFixtures ExistingTeamFixtures, mongodb
        .then -> loadFixtures ExistingPlayerFixtures, mongodb
        .then -> Players.update({_id: playerId}, {$set: {updatedAt: late}})
        .then -> updateTeam.execute teamId
        .then -> Teams.count()
        .then (count) ->
          count.should.be.equal 1
        .then -> Players.findOne({_id: playerId})
        .then (player) ->
          should.exist player

          # fake nickname should be present
          {firstName} = player
          should.exist firstName
          firstName.should.be.equal "Salvador"
        .then @assertScopesFinished
        .then resolve
        .catch reject
        .finally recordingDone

