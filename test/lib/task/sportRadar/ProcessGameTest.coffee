createDependencies = require "../../../../helper/dependencies"
settings = (require "../../../../helper/settings")("#{process.env.ROOT_DIR}/settings/test.json")
Promise = require "bluebird"
moment = require "moment"
_ = require "underscore"
ImportGames = require "../../../../lib/task/sportRadar/ImportGames"
loadFixtures = require "../../../../helper/loadFixtures"
ProcessGame = require "../../../../lib/task/sportRadar/ProcessGame"
SportRadarGame = require "../../../../lib/model/sportRadar/SportRadarGame"
TwoActiveGamesFixtures = require "#{process.env.ROOT_DIR}/test/fixtures/task/sportRadar/processGame/collection/TwoActiveGames.json"
QuestionsFixtures = require "#{process.env.ROOT_DIR}/test/fixtures/task/sportRadar/processGame/collection/Questions.json"
ActualQuestionsFixtures = require "#{process.env.ROOT_DIR}/test/fixtures/task/sportRadar/processGame/collection/ActualQuestions.json"
NonActualQuestionsFixtures = require "#{process.env.ROOT_DIR}/test/fixtures/task/sportRadar/processGame/collection/NonActualQuestions.json"
NonActualPitchQuestionsFixtures = require "#{process.env.ROOT_DIR}/test/fixtures/task/sportRadar/processGame/collection/NonActualPitchQuestions.json"
ActiveFullGameFixtures = require "#{process.env.ROOT_DIR}/test/fixtures/task/sportRadar/processGame/collection/ActiveFullGame.json"
ActiveFullGameWithLineUp = require "#{process.env.ROOT_DIR}/test/fixtures/task/sportRadar/processGame/collection/ActiveFullGameWithLineUp.json"
ActiveGameNoInningsFixtures = require "#{process.env.ROOT_DIR}/test/fixtures/task/sportRadar/processGame/collection/ActiveGameNoInnings.json"
ActiveGameNoPlaysFixtures = require "#{process.env.ROOT_DIR}/test/fixtures/task/sportRadar/processGame/collection/ActiveGameNoPlays.json"
ActiveGameEndOfInningFixtures = require "#{process.env.ROOT_DIR}/test/fixtures/task/sportRadar/processGame/collection/ActiveGameEndOfInning.json"
ActiveGameEndOfHalfFixtures = require "#{process.env.ROOT_DIR}/test/fixtures/task/sportRadar/processGame/collection/ActiveGameEndOfHalf.json"
ActiveGameEndOfPlayFixtures = require "#{process.env.ROOT_DIR}/test/fixtures/task/sportRadar/processGame/collection/ActiveGameEndOfPlay.json"
ActiveGameMiddleOfPlayFixtures = require "#{process.env.ROOT_DIR}/test/fixtures/task/sportRadar/processGame/collection/ActiveGameMiddleOfPlay.json"
TeamsFixtures = require "#{process.env.ROOT_DIR}/test/fixtures/task/sportRadar/processGame/collection/Teams.json"
PlayersFixtures = require "#{process.env.ROOT_DIR}/test/fixtures/task/sportRadar/processGame/collection/Players.json"
AtBatsFixtures = require "#{process.env.ROOT_DIR}/test/fixtures/task/sportRadar/processGame/collection/AtBats.json"
ActiveAtBatFixtures = require "#{process.env.ROOT_DIR}/test/fixtures/task/sportRadar/processGame/collection/ActiveAtBat.json"
UsersFixtures = require "#{process.env.ROOT_DIR}/test/fixtures/task/sportRadar/processGame/collection/Users.json"
AnswersFixtures = require "#{process.env.ROOT_DIR}/test/fixtures/task/sportRadar/processGame/collection/Answers.json"
WrongAnswersFixtures = require "#{process.env.ROOT_DIR}/test/fixtures/task/sportRadar/processGame/collection/WrongAnswers.json"

describe "Process imported games and question management", ->
  dependencies = createDependencies settings, "PickkImport"
  mongodb = dependencies.mongodb

  processGame = undefined

  SportRadarGames = mongodb.collection("games")
  Teams = mongodb.collection("teams")
  Players = mongodb.collection("players")
  Questions = mongodb.collection("questions")
  AtBats = mongodb.collection("atBat")
  Users = mongodb.collection("users")
  Answers = mongodb.collection("answers")

  activeGameId = "fec58a7a-eff7-4eec-9535-f64c42cc4870"
  inactiveGameId = "2b0ba18a-41f5-46d7-beb3-1e86b9a4acc0"
  actualActiveQuestionId = "active_question_for_active_game"
  nonActualActiveQuestionId = "active_question_for_inactive_game"

  beforeEach ->
    processGame = new ProcessGame dependencies

    Promise.bind @
    .then ->
      Promise.all [
        SportRadarGames.remove()
        Teams.remove()
        Players.remove()
        Questions.remove()
        AtBats.remove()
        Users.remove()
        Answers.remove()
      ]

  it 'should create new play question', ->
    Promise.bind @
    .then -> loadFixtures ActiveFullGameFixtures, mongodb
    .then -> SportRadarGames.findOne({id: activeGameId})
    .then (game) -> processGame.execute game
    .then -> Questions.findOne({game_id: activeGameId, player_id: "abbda8e1-2274-4bf0-931c-691cf8bf24c6", atBatQuestion: true})
    .then (question) ->
      should.exist question
      question.should.be.an "object"

      {active} = question
      should.exist active
      active.should.be.equal true

  it 'should update actual play question', ->
    Promise.bind @
    .then -> loadFixtures ActiveFullGameFixtures, mongodb
    .then -> loadFixtures ActualQuestionsFixtures, mongodb
    .then -> SportRadarGames.findOne({id: activeGameId})
    .then (game) -> processGame.execute game
    .then -> Questions.findOne({id: "active_question_for_active_game"})
    .then (question) ->
      should.exist question
      question.should.be.an "object"

      {active, options} = question
      should.exist active
      # should be still active
      active.should.be.equal true

      # check options have been updated
      should.exist options

  it 'should disable non-actual play question', ->
    Promise.bind @
    .then -> loadFixtures ActiveFullGameFixtures, mongodb
    .then -> loadFixtures NonActualQuestionsFixtures, mongodb
    .then -> SportRadarGames.findOne({id: activeGameId})
    .then (game) -> processGame.execute game
    .then -> Questions.findOne({id: "non_actual_question_for_active_game"})
    .then (question) ->
      should.exist question
      question.should.be.an "object"

      {active} = question
      should.exist active
      active.should.be.equal false

  it 'should create new pitch question', ->
    Promise.bind @
    .then -> loadFixtures ActiveFullGameFixtures, mongodb
    .then -> SportRadarGames.findOne({id: activeGameId})
    .then (game) -> processGame.execute game
    .then -> Questions.findOne({game_id: activeGameId, player_id: "abbda8e1-2274-4bf0-931c-691cf8bf24c6", atBatQuestion: {$exists: false}})
    .then (question) ->
      should.exist question
      question.should.be.an "object"

      {active, play, pitch} = question
      should.exist active
      active.should.be.equal true

      should.exist play
      play.should.be.equal 28

      should.exist pitch
      pitch.should.be.equal 6

  it 'should update actual pitch question with the same play and pitch number', ->
    Promise.bind @
    .then -> loadFixtures ActiveFullGameFixtures, mongodb
    .then -> loadFixtures ActualQuestionsFixtures, mongodb
    .then -> SportRadarGames.findOne({id: activeGameId})
    .then (game) -> processGame.execute game
    .then -> Questions.findOne({id: "active_pitch_question_for_active_game"})
    .then (question) ->
      should.exist question
      question.should.be.an "object"

      {active, play, pitch} = question

      should.exist active
      # should be still active
      active.should.be.equal true

      should.exist play
      play.should.be.equal 28

      should.exist pitch
      pitch.should.be.equal 6

  it 'should create a pitch question if play and pitch number is different', ->
    game = undefined

    Promise.bind @
    .then -> loadFixtures ActiveFullGameFixtures, mongodb
    .then -> loadFixtures NonActualPitchQuestionsFixtures, mongodb
    .then -> SportRadarGames.findOne({id: activeGameId})
    .then (_game) -> game = _game; processGame.execute game
    .then -> Questions.findOne({id: "active_non_actual_pitch_question_for_active_game"})
    .then (question) ->
      should.exist question
      question.should.be.an "object"

      {active, play, pitch} = question

      should.exist active
      active.should.be.equal false

      should.exist play
      play.should.be.equal 28

      should.exist pitch
      pitch.should.be.equal

    .then -> Questions.findOne({gameId: game._id, active: true, atBatQuestion: {$exists: false}})
    .then (question) ->
      should.exist question
      question.should.be.an "object"

      {play, pitch} = question

      should.exist play
      play.should.be.equal 28

      should.exist pitch
      pitch.should.be.equal 6

  it 'should disable non-actual pitch question', ->
    Promise.bind @
    .then -> loadFixtures ActiveFullGameFixtures, mongodb
    .then -> loadFixtures NonActualQuestionsFixtures, mongodb
    .then -> SportRadarGames.findOne({id: activeGameId})
    .then (game) -> processGame.execute game
    .then -> Questions.findOne({id: "non_actual_pitch_question_for_active_game"})
    .then (question) ->
      should.exist question
      question.should.be.an "object"

      {active} = question
      should.exist active
      # should be still active
      active.should.be.equal false

  it 'should reward the user for right answer on pitch question', ->
    Promise.bind @
    .then -> loadFixtures ActiveFullGameFixtures, mongodb
    .then -> loadFixtures NonActualPitchQuestionsFixtures, mongodb
    .then -> loadFixtures UsersFixtures, mongodb
    .then -> loadFixtures AnswersFixtures, mongodb
    .then -> SportRadarGames.findOne({id: activeGameId})
    .then (game) -> processGame.execute game
    .then -> Users.findOne({_id: "Charlie"})
    .then (user) ->
      should.exist user
      user.should.be.an "object"

      {profile} = user
      should.exist profile
      profile.should.be.an "object"

      {coins} = profile
      should.exist coins
      coins.should.be.equal 10435

  it 'should reward the user for right answer on play question', ->
    Promise.bind @
    .then -> loadFixtures ActiveFullGameFixtures, mongodb
    .then -> loadFixtures NonActualQuestionsFixtures, mongodb
    .then -> loadFixtures UsersFixtures, mongodb
    .then -> loadFixtures AnswersFixtures, mongodb
    .then -> SportRadarGames.findOne({id: activeGameId})
    .then (game) -> processGame.execute game
    .then -> Users.findOne({_id: "Charlie"})
    .then (user) ->
      should.exist user
      user.should.be.an "object"

      {profile} = user
      should.exist profile
      profile.should.be.an "object"

      {coins} = profile
      should.exist coins
      coins.should.be.equal 10735

  it 'shouldn\'t reward the user for wrong answer on pitch question', ->
    Promise.bind @
    .then -> loadFixtures ActiveFullGameFixtures, mongodb
    .then -> loadFixtures NonActualQuestionsFixtures, mongodb
    .then -> loadFixtures UsersFixtures, mongodb
    .then -> loadFixtures WrongAnswersFixtures, mongodb
    .then -> SportRadarGames.findOne({id: activeGameId})
    .then (game) -> processGame.execute game
    .then -> Users.findOne({_id: "Charlie"})
    .then (user) ->
      should.exist user
      user.should.be.an "object"

      {profile} = user
      should.exist profile
      profile.should.be.an "object"

      {coins} = profile
      should.exist coins
      coins.should.be.equal 10000

  it 'shouldn\'t reward the user for wrong answer on play question', ->
    Promise.bind @
    .then -> loadFixtures ActiveFullGameFixtures, mongodb
    .then -> loadFixtures NonActualQuestionsFixtures, mongodb
    .then -> loadFixtures UsersFixtures, mongodb
    .then -> loadFixtures WrongAnswersFixtures, mongodb
    .then -> SportRadarGames.findOne({id: activeGameId})
    .then (game) -> processGame.execute game
    .then -> Users.findOne({_id: "Charlie"})
    .then (user) ->
      should.exist user
      user.should.be.an "object"

      {profile} = user
      should.exist profile
      profile.should.be.an "object"

      {coins} = profile
      should.exist coins
      coins.should.be.equal 10000

  it 'should works correctly when no innings are present', ->
    Promise.bind @
    .then -> loadFixtures ActiveGameNoInningsFixtures, mongodb
    .then -> SportRadarGames.findOne({id: activeGameId})
    .then (game) -> processGame.execute game
    .then -> Questions.count()
    .then (result) ->
      should.exist result
      result.should.be.equal 0

  it 'should works correctly when no plays are present', ->
    Promise.bind @
    .then -> loadFixtures ActiveGameNoPlaysFixtures, mongodb
    .then -> SportRadarGames.findOne({id: activeGameId})
    .then (game) -> processGame.execute game
    .then -> Questions.findOne({game_id: activeGameId, player_id: "92500d32-2314-4c7c-91c5-110f95229f9a", atBatQuestion: {$exists: false}})
    .then (question) ->
      should.exist question
      question.should.be.an "object"

      {active} = question
      should.exist active
      active.should.be.equal true
    .then -> Questions.findOne({game_id: activeGameId, player_id: "92500d32-2314-4c7c-91c5-110f95229f9a", atBatQuestion: true})
    .then (question) ->
      should.exist question
      question.should.be.an "object"

      {active} = question
      should.exist active
      active.should.be.equal true

  it 'should works correctly when a half is finished', ->
    Promise.bind @
    .then -> loadFixtures ActiveGameEndOfHalfFixtures, mongodb
    .then -> SportRadarGames.findOne({id: activeGameId})
    .then (game) -> processGame.execute game
    .then -> Questions.findOne({game_id: activeGameId, player_id: "1a0bef4b-f97b-453d-80ed-5fde2c80acc8", atBatQuestion: {$exists: false}})
    .then (question) ->
      should.exist question
      question.should.be.an "object"

      {active} = question
      should.exist active
      active.should.be.equal true
    .then -> Questions.findOne({game_id: activeGameId, player_id: "1a0bef4b-f97b-453d-80ed-5fde2c80acc8", atBatQuestion: true})
    .then (question) ->
      should.exist question
      question.should.be.an "object"

      {active} = question
      should.exist active
      active.should.be.equal true

  it 'should works correctly when an inning is finished', ->
    Promise.bind @
    .then -> loadFixtures ActiveGameEndOfInningFixtures, mongodb
    .then -> SportRadarGames.findOne({id: activeGameId})
    .then (game) -> processGame.execute game
    .then -> Questions.findOne({game_id: activeGameId, player_id: "3cfaa9a7-8dea-4590-8ea5-c8e1b51232cf", atBatQuestion: {$exists: false}})
    .then (question) ->
      should.exist question
      question.should.be.an "object"

      {active} = question
      should.exist active
      active.should.be.equal true
    .then -> Questions.findOne({game_id: activeGameId, player_id: "3cfaa9a7-8dea-4590-8ea5-c8e1b51232cf", atBatQuestion: true})
    .then (question) ->
      should.exist question
      question.should.be.an "object"

      {active} = question
      should.exist active
      active.should.be.equal true

  it 'should works correctly when a play is finished', ->
    Promise.bind @
    .then -> loadFixtures ActiveGameEndOfPlayFixtures, mongodb
    .then -> SportRadarGames.findOne({id: activeGameId})
    .then (game) -> processGame.execute game
    .then -> Questions.findOne({game_id: activeGameId, player_id: "6ac6fa53-ea9b-467d-87aa-6429a6bcb90c", atBatQuestion: {$exists: false}})
    .then (question) ->
      should.exist question
      question.should.be.an "object"

      {active} = question
      should.exist active
      active.should.be.equal true
    .then -> Questions.findOne({game_id: activeGameId, player_id: "6ac6fa53-ea9b-467d-87aa-6429a6bcb90c", atBatQuestion: true})
    .then (question) ->
      should.exist question
      question.should.be.an "object"

      {active} = question
      should.exist active
      active.should.be.equal true

  it 'should works correctly when a play is in progress', ->
    Promise.bind @
    .then -> loadFixtures ActiveGameMiddleOfPlayFixtures, mongodb
    .then -> SportRadarGames.findOne({id: activeGameId})
    .then (game) -> processGame.execute game
    .then -> Questions.findOne({game_id: activeGameId, player_id: "c401dbb6-2208-45f4-9947-db11881daf4f", atBatQuestion: {$exists: false}})
    .then (question) ->
      should.exist question
      question.should.be.an "object"

      {active} = question
      should.exist active
      active.should.be.equal true
    .then -> Questions.findOne({game_id: activeGameId, player_id: "c401dbb6-2208-45f4-9947-db11881daf4f", atBatQuestion: true})
    .then (question) ->
      should.exist question
      question.should.be.an "object"

      {active} = question
      should.exist active
      active.should.be.equal true

  it 'should store teams into database', ->
    Promise.bind @
    .then -> loadFixtures ActiveGameEndOfPlayFixtures, mongodb
    .then -> SportRadarGames.findOne({id: activeGameId})
    .then (game) -> processGame.execute game
    .then -> Teams.find()
    .then (teams) ->
      should.exist teams
      teams.should.be.an "array"
      teams.length.should.equal 2

      home = _.findWhere teams, {_id: "47f490cd-2f58-4ef7-9dfd-2ad6ba6c1ae8"}
      should.exist home
      home.should.be.an "object"
      
      {fullName, nickname, computerName, city, state} = home

      should.exist fullName
      fullName.should.equal "Chicago White Sox"

      should.exist nickname
      nickname.should.equal "White Sox"

      should.exist computerName
      computerName.should.equal "cws"

      should.exist city
      city.should.equal "Chicago"

      should.exist state
      state.should.equal ""

  it 'should update existing team', ->
    Promise.bind @
    .then -> loadFixtures ActiveGameEndOfPlayFixtures, mongodb
    .then -> loadFixtures TeamsFixtures, mongodb
    .then -> SportRadarGames.findOne({id: activeGameId})
    .then (game) -> processGame.execute game
    .then -> Teams.find()
    .then (teams) ->
      should.exist teams
      teams.should.be.an "array"
      teams.length.should.equal 2

      home = _.findWhere teams, {_id: "47f490cd-2f58-4ef7-9dfd-2ad6ba6c1ae8"}
      should.exist home
      home.should.be.an "object"

      {city} = home

      should.exist city
      city.should.equal "Chicago"
  
  it 'should store players into database', ->
    Promise.bind @
    .then -> loadFixtures ActiveGameEndOfPlayFixtures, mongodb
    .then -> SportRadarGames.findOne({id: activeGameId})
    .then (game) -> processGame.execute game
    .then -> Players.find()
    .then (players) ->
      should.exist players
      players.should.be.an "array"
      players.length.should.equal 20

      player = _.findWhere players, {_id: "92500d32-2314-4c7c-91c5-110f95229f9a"}
      should.exist player
      player.should.be.an "object"
      
      {playerId, name, team, position} = player

      should.exist playerId
      playerId.should.equal "92500d32-2314-4c7c-91c5-110f95229f9a"

      should.exist name
      name.should.equal "Whitley Merrifield"

      should.exist team
      team.should.equal "833a51a9-0d84-410f-bd77-da08c3e5e26e"

      should.exist position
      position.should.equal 7

  it 'should update existing player', ->
    Promise.bind @
    .then -> loadFixtures ActiveGameEndOfPlayFixtures, mongodb
    .then -> loadFixtures PlayersFixtures, mongodb
    .then -> SportRadarGames.findOne({id: activeGameId})
    .then (game) -> processGame.execute game
    .then -> Players.find()
    .then (players) ->
      should.exist players
      players.should.be.an "array"
      players.length.should.equal 20

      player = _.findWhere players, {_id: "92500d32-2314-4c7c-91c5-110f95229f9a"}
      should.exist player
      player.should.be.an "object"

      {position} = player

      should.exist position
      position.should.equal 7

  it 'should create atBat for active batter', ->
    game = undefined

    Promise.bind @
    .then -> loadFixtures ActiveGameEndOfPlayFixtures, mongodb
    .then -> SportRadarGames.findOne({id: activeGameId})
    .then (_game) -> game = _game; processGame.execute game
    .then -> AtBats.find()
    .then (bats) ->
      should.exist bats
      bats.should.be.an "array"
      bats.length.should.equal 1

      bat = bats[0]
      should.exist bat
      bat.should.be.an "object"

      {active, playerId, gameId, ballCount, strikeCount} = bat

      should.exist active
      active.should.equal true

      should.exist playerId
      playerId.should.equal "6ac6fa53-ea9b-467d-87aa-6429a6bcb90c"

      should.exist gameId
      gameId.toString().should.equal game._id.toString()

      should.exist ballCount
      ballCount.should.equal 0

      should.exist strikeCount
      strikeCount.should.equal 0

  it 'should create new atBat and close another one', ->
    game = undefined

    Promise.bind @
    .then -> loadFixtures ActiveGameEndOfPlayFixtures, mongodb
    .then -> loadFixtures AtBatsFixtures, mongodb
    .then -> SportRadarGames.findOne({id: activeGameId})
    .then (_game) -> game = _game; processGame.execute game
    .then -> AtBats.find()
    .then (bats) ->
      should.exist bats
      bats.should.be.an "array"
      bats.length.should.equal 2

      activeBat = _.findWhere bats, {active: true}
      should.exist activeBat
      activeBat.should.be.an "object"

      {playerId} = activeBat

      should.exist playerId
      playerId.should.equal "6ac6fa53-ea9b-467d-87aa-6429a6bcb90c"

      inactiveBat = _.findWhere bats, {active: false}
      should.exist inactiveBat

  it 'should update existing active atBat', ->
    game = undefined

    Promise.bind @
    .then -> loadFixtures ActiveGameEndOfPlayFixtures, mongodb
    .then -> loadFixtures ActiveAtBatFixtures, mongodb
    .then -> SportRadarGames.findOne({id: activeGameId})
    .then (_game) -> game = _game; processGame.execute game
    .then -> AtBats.find()
    .then (bats) ->
      should.exist bats
      bats.should.be.an "array"
      bats.length.should.equal 1

      bat = bats[0]
      should.exist bat
      bat.should.be.an "object"

      {ballCount, strikeCount} = bat

      should.exist ballCount
      ballCount.should.equal 0

      should.exist strikeCount
      strikeCount.should.equal 0

  it 'should enrich the game by new fields', ->
    Promise.bind @
    .then -> loadFixtures ActiveGameEndOfPlayFixtures, mongodb
    .then -> SportRadarGames.findOne({id: activeGameId})
    .then (game) -> processGame.execute game
    .then -> SportRadarGames.findOne({id: activeGameId})
    .then (game) ->
      should.exist game
      game.should.be.an "object"

      {dateCreated, name, live, completed, commercial, gameDate, tv, teams, outs, inning, topOfInning, playersOnBase, users, nonActive} = game

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

#  it 'should enrich the game by new fields, case 2', ->
#    Promise.bind @
#    .then -> loadFixtures ActiveGameEndOfInningFixtures, mongodb
#    .then -> SportRadarGames.findOne({id: activeGameId})
#    .then (game) -> processGame.execute game
#    .then -> SportRadarGames.findOne({id: activeGameId})
#    .then (game) ->
#      should.exist game
#      game.should.be.an "object"
#
#      {dateCreated, name, live, completed, commercial, gameDate, tv, teams, outs, inning, topOfInning, playersOnBase, users, nonActive} = game
#
#      home = _.findWhere teams, {teamId: "47f490cd-2f58-4ef7-9dfd-2ad6ba6c1ae8"}
#      should.exist home
#      home.should.be.an "object"
#
#      {batterNum} = home
#
#      should.exist batterNum
#      batterNum.should.equal (6 - 1)
#
#      away = _.findWhere teams, {teamId: "833a51a9-0d84-410f-bd77-da08c3e5e26e"}
#      should.exist away
#      away.should.be.an "object"
#
#      {batterNum} = away
#
#      should.exist batterNum
#      batterNum.should.equal (1 - 1)
#
#      should.exist outs
#      outs.should.equal 0
#
#      should.exist inning
#      inning.should.equal 2
#
#      should.exist topOfInning
#      topOfInning.should.equal true
#
#      should.exist playersOnBase
#      playersOnBase.should.be.an "object"
#
#      {first, second, third} = playersOnBase
#
#      should.exist first
#      first.should.equal false
#
#      should.exist second
#      second.should.equal false
#
#      should.exist third
#      third.should.equal false
