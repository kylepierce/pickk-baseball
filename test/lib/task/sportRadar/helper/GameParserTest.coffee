createDependencies = require "../../../../../helper/dependencies"
_ = require "underscore"
settings = (require "../../../../../helper/settings")("#{process.env.ROOT_DIR}/settings/test.json")
Promise = require "bluebird"
moment = require "moment"
ImportGames = require "../../../../../lib/task/sportRadar/ImportGames"
loadFixtures = require "../../../../../helper/loadFixtures"
GameParser = require "../../../../../lib/task/sportRadar/helper/GameParser"
SportRadarGame = require "../../../../../lib/model/sportRadar/SportRadarGame"
ActiveFullGameWithLineUp = require "#{process.env.ROOT_DIR}/test/fixtures/task/sportRadar/processGame/collection/ActiveFullGameWithLineUp.json"
ActiveGameNoInningsFixtures = require "#{process.env.ROOT_DIR}/test/fixtures/task/sportRadar/processGame/collection/ActiveGameNoInnings.json"
ActiveGameNoPlaysFixtures = require "#{process.env.ROOT_DIR}/test/fixtures/task/sportRadar/processGame/collection/ActiveGameNoPlays.json"
ActiveGameEndOfInningFixtures = require "#{process.env.ROOT_DIR}/test/fixtures/task/sportRadar/processGame/collection/ActiveGameEndOfInning.json"
ActiveGameEndOfHalfFixtures = require "#{process.env.ROOT_DIR}/test/fixtures/task/sportRadar/processGame/collection/ActiveGameEndOfHalf.json"
ActiveGameEndOfPlayFixtures = require "#{process.env.ROOT_DIR}/test/fixtures/task/sportRadar/processGame/collection/ActiveGameEndOfPlay.json"
ActiveGameMiddleOfPlayFixtures = require "#{process.env.ROOT_DIR}/test/fixtures/task/sportRadar/processGame/collection/ActiveGameMiddleOfPlay.json"

describe "Process imported games and question management", ->
  dependencies = createDependencies settings, "PickkImport"
  mongodb = dependencies.mongodb

  gameParser = undefined
  
  SportRadarGames = mongodb.collection("games")
  Questions = mongodb.collection("questions")

  beforeEach ->
    gameParser = new GameParser dependencies

    Promise.bind @
    .then ->
      Promise.all [
        SportRadarGames.remove()
        Questions.remove()
      ]

  it 'should parse game correctly', ->
    Promise.bind @
    .then -> loadFixtures ActiveFullGameWithLineUp, mongodb
    .then -> SportRadarGames.findOne({id: "77ba61aa-d576-4a85-88b1-d5e40938dbbc"})
    .then (game) -> gameParser.getPlay game
    .then (result) ->
      should.exist result
      result.should.be.an "object"

      {hitter, balls, strikes} = result

      should.exist hitter
      hitter.should.be.an "object"
      {last_name} = hitter
      should.exist last_name
      last_name.should.be.equal 'Naquin'

      should.exist balls
      balls.should.be.equal 0

      should.exist strikes
      strikes.should.be.equal 0

  it 'should parse game with no innings correctly', ->
    Promise.bind @
    .then -> loadFixtures ActiveGameNoInningsFixtures, mongodb
    .then -> SportRadarGames.findOne()
    .then (game) -> gameParser.getPlay game
    .then (result) ->
      should.not.exist result

  it 'should parse game with no plays', ->
    Promise.bind @
    .then -> loadFixtures ActiveGameNoPlaysFixtures, mongodb
    .then -> SportRadarGames.findOne()
    .then (game) -> gameParser.getPlay game
    .then (result) ->
      should.exist result
      result.should.be.an "object"

      {hitter, balls, strikes} = result

      should.exist hitter
      hitter.should.be.an "object"
      {player_id} = hitter
      should.exist player_id
      player_id.should.be.equal "92500d32-2314-4c7c-91c5-110f95229f9a"

      should.exist balls
      balls.should.be.equal 0

      should.exist strikes
      strikes.should.be.equal 0

  it 'should parse game with a half is finished', ->
    Promise.bind @
    .then -> loadFixtures ActiveGameEndOfHalfFixtures, mongodb
    .then -> SportRadarGames.findOne()
    .then (game) -> gameParser.getPlay game
    .then (result) ->
      should.exist result
      result.should.be.an "object"

      {hitter, balls, strikes} = result

      should.exist hitter
      hitter.should.be.an "object"
      {player_id} = hitter
      should.exist player_id
      player_id.should.be.equal "1a0bef4b-f97b-453d-80ed-5fde2c80acc8"

      should.exist balls
      balls.should.be.equal 0

      should.exist strikes
      strikes.should.be.equal 0

  it 'should parse game with an inning is finished', ->
    Promise.bind @
    .then -> loadFixtures ActiveGameEndOfInningFixtures, mongodb
    .then -> SportRadarGames.findOne()
    .then (game) -> gameParser.getPlay game
    .then (result) ->
      should.exist result
      result.should.be.an "object"

      {hitter, balls, strikes} = result

      should.exist hitter
      hitter.should.be.an "object"
      {player_id} = hitter
      should.exist player_id
      player_id.should.be.equal "3cfaa9a7-8dea-4590-8ea5-c8e1b51232cf"

      should.exist balls
      balls.should.be.equal 0

      should.exist strikes
      strikes.should.be.equal 0

  it 'should parse game with a play is finished', ->
    Promise.bind @
    .then -> loadFixtures ActiveGameEndOfPlayFixtures, mongodb
    .then -> SportRadarGames.findOne()
    .then (game) -> gameParser.getPlay game
    .then (result) ->
      should.exist result
      result.should.be.an "object"

      {hitter, balls, strikes} = result

      should.exist hitter
      hitter.should.be.an "object"
      {player_id} = hitter
      should.exist player_id
      player_id.should.be.equal "6ac6fa53-ea9b-467d-87aa-6429a6bcb90c"

      should.exist balls
      balls.should.be.equal 0

      should.exist strikes
      strikes.should.be.equal 0

  it 'should parse game with a play is in progress', ->
    Promise.bind @
    .then -> loadFixtures ActiveGameMiddleOfPlayFixtures, mongodb
    .then -> SportRadarGames.findOne()
    .then (game) -> gameParser.getPlay game
    .then (result) ->
      should.exist result
      result.should.be.an "object"

      {hitter, balls, strikes, pitch} = result

      should.exist hitter
      hitter.should.be.an "object"
      {player_id} = hitter
      should.exist player_id
      player_id.should.be.equal "c401dbb6-2208-45f4-9947-db11881daf4f"

      should.exist balls
      balls.should.be.equal 0

      should.exist strikes
      strikes.should.be.equal 2

      should.exist pitch

  it 'should provide pitch by its Id', ->
    Promise.bind @
    .then -> loadFixtures ActiveGameMiddleOfPlayFixtures, mongodb
    .then -> SportRadarGames.findOne()
    .then (game) -> gameParser.getPitchById game, '2a587da9-9b2c-4082-90d3-515e2ef6d010'
    .then (pitch) ->
      should.exist pitch
      pitch.should.be.an "object"

      {outcome_id} = pitch

      should.exist outcome_id
      outcome_id.should.equal "bB"

  it 'should calculate play and pitch number correctly for the beginning of the match', ->
    Promise.bind @
    .then -> loadFixtures ActiveGameNoPlaysFixtures, mongodb
    .then -> SportRadarGames.findOne()
    .then (game) -> gameParser.getPlay game
    .then (result) ->
      should.exist result
      result.should.be.an "object"

      {playNumber, pitchNumber} = result

      should.exist playNumber
      playNumber.should.equal 1

      should.exist pitchNumber
      pitchNumber.should.equal 1

  it 'should calculate play and pitch number correctly for an unfinished play', ->
    Promise.bind @
    .then -> loadFixtures ActiveGameMiddleOfPlayFixtures, mongodb
    .then -> SportRadarGames.findOne()
    .then (game) -> gameParser.getPlay game
    .then (result) ->
      should.exist result
      result.should.be.an "object"

      {playNumber, pitchNumber} = result

      should.exist playNumber
      playNumber.should.equal 7

      should.exist pitchNumber
      pitchNumber.should.equal 3

  it 'should calculate play and pitch number correctly for an finished play', ->
    Promise.bind @
    .then -> loadFixtures ActiveGameEndOfPlayFixtures, mongodb
    .then -> SportRadarGames.findOne()
    .then (game) -> gameParser.getPlay game
    .then (result) ->
      should.exist result
      result.should.be.an "object"

      {playNumber, pitchNumber} = result

      should.exist playNumber
      playNumber.should.equal 8

      should.exist pitchNumber
      pitchNumber.should.equal 1

  it 'should return correct outcome for play and pitch specified', ->
    Promise.bind @
    .then -> loadFixtures ActiveGameEndOfPlayFixtures, mongodb
    .then -> SportRadarGames.findOne()
    .then (game) -> gameParser.getPlay game
    .then (result) ->
      should.exist result
      result.should.be.an "object"

      {plays} = result

      should.exist plays
      plays.should.be.an "array"

      play = plays[3]

      should.exist play
      play.should.be.an "object"

      {pitches, outcome} = play

      should.exist outcome
      outcome.should.equal "Walk"

      should.exist pitches
      pitches.should.be.an "array"

      outcome = pitches[1]

      should.exist outcome
      outcome.should.equal "Foul Ball"

  it 'should return another correct outcome for play and pitch specified', ->
    Promise.bind @
    .then -> loadFixtures ActiveGameEndOfPlayFixtures, mongodb
    .then -> SportRadarGames.findOne()
    .then (game) -> gameParser.getPlay game
    .then (result) ->
      should.exist result
      result.should.be.an "object"

      {plays} = result

      should.exist plays
      plays.should.be.an "array"

      play = plays[4]

      should.exist play
      play.should.be.an "object"

      {pitches, outcome} = play

      should.exist outcome
      outcome.should.equal "Single"

      should.exist pitches
      pitches.should.be.an "array"

      outcome = pitches[3]

      should.exist outcome
      outcome.should.equal "Hit"

  it 'should parse teams', ->
    Promise.bind @
    .then -> loadFixtures ActiveGameEndOfPlayFixtures, mongodb
    .then -> SportRadarGames.findOne()
    .then (game) -> gameParser.getPlay game
    .then (result) ->
      should.exist result
      result.should.be.an "object"

      {teams} = result

      should.exist teams
      teams.should.be.an "object"
      {home} = teams
      should.exist home

      {name} = home
      should.exist name
      name.should.be.equal "White Sox"

  it 'should parse players', ->
    Promise.bind @
    .then -> loadFixtures ActiveGameEndOfPlayFixtures, mongodb
    .then -> SportRadarGames.findOne()
    .then (game) -> gameParser.getPlay game
    .then (result) ->
      should.exist result
      result.should.be.an "object"

      {players} = result

      should.exist players
      players.should.be.an "array"
      players.length.should.equal 20
      player = _.findWhere players, {player_id: "92500d32-2314-4c7c-91c5-110f95229f9a"}

      {first_name} = player
      should.exist first_name
      first_name.should.be.equal "Whitley"

  it 'should provide game details', ->
    Promise.bind @
    .then -> loadFixtures ActiveGameEndOfPlayFixtures, mongodb
    .then -> SportRadarGames.findOne()
    .then (game) -> gameParser.getPlay game
    .then (result) ->
      should.exist result
      result.should.be.an "object"

      {details} = result

      {dateCreated, name, live, completed, commercial, gameDate, tv, teams, outs, inning, topOfInning, playersOnBase, users, nonActive} = details

      should.exist dateCreated
      dateCreated.getTime().should.equal moment.utc("2016-06-11").toDate().getTime()

      should.exist name
      name.should.equal "White Sox vs Royals"

      should.exist live
      live.should.equal true

      should.exist completed
      completed.should.equal false

      should.exist commercial
      commercial.should.equal false

      should.exist gameDate
      gameDate.should.equal "Jun 11th 6:10 PM"

      should.exist tv
      tv.should.equal "WGN"

      should.exist teams
      teams.should.be.an "array"

      home = _.findWhere teams, {teamId: "47f490cd-2f58-4ef7-9dfd-2ad6ba6c1ae8"}
      should.exist home
      home.should.be.an "object"

      {batterNum, pitcher, battingLineUp} = home

      should.exist batterNum
      batterNum.should.equal (5 - 1)

      should.exist pitcher
      pitcher.should.be.an "array"

      should.exist battingLineUp
      battingLineUp.should.be.an "array"
      battingLineUp.length.should.equal 10
      ("cbfa52c5-ef2e-4d7c-8e28-0ec6a63c6c6f" in battingLineUp).should.equal true

      away = _.findWhere teams, {teamId: "833a51a9-0d84-410f-bd77-da08c3e5e26e"}
      should.exist away
      away.should.be.an "object"

      {batterNum, pitcher, battingLineUp} = away

      should.exist batterNum
      batterNum.should.equal (4 - 1)

      should.exist pitcher
      pitcher.should.be.an "array"

      should.exist battingLineUp
      battingLineUp.should.be.an "array"
      battingLineUp.length.should.equal 10
      ("92500d32-2314-4c7c-91c5-110f95229f9a" in battingLineUp).should.equal true

      should.exist outs
      outs.should.equal 2

      should.exist inning
      inning.should.equal 1

      should.exist topOfInning
      topOfInning.should.equal false

      should.exist playersOnBase
      playersOnBase.should.be.an "object"

      {first, second, third} = playersOnBase

      should.exist first
      first.should.equal false

      should.exist second
      second.should.equal true

      should.exist third
      third.should.equal true

      should.exist users
      users.should.be.an "array"

      should.exist nonActive
      nonActive.should.be.an "array"

