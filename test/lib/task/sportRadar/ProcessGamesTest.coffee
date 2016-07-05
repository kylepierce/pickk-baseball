createDependencies = require "../../../../helper/dependencies"
settings = (require "../../../../helper/settings")("#{process.env.ROOT_DIR}/settings/test.json")
Promise = require "bluebird"
moment = require "moment"
_ = require "underscore"
ImportGames = require "../../../../lib/task/sportRadar/ImportGames"
loadFixtures = require "../../../../helper/loadFixtures"
ProcessGames = require "../../../../lib/task/sportRadar/ProcessGames"
SportRadarGame = require "../../../../lib/model/sportRadar/SportRadarGame"
TwoActiveGamesFixtures = require "#{process.env.ROOT_DIR}/test/fixtures/task/sportRadar/processGames/collection/TwoActiveGames.json"
QuestionsFixtures = require "#{process.env.ROOT_DIR}/test/fixtures/task/sportRadar/processGames/collection/Questions.json"
ActualQuestionsFixtures = require "#{process.env.ROOT_DIR}/test/fixtures/task/sportRadar/processGames/collection/ActualQuestions.json"
NonActualQuestionsFixtures = require "#{process.env.ROOT_DIR}/test/fixtures/task/sportRadar/processGames/collection/NonActualQuestions.json"
ActiveFullGameFixtures = require "#{process.env.ROOT_DIR}/test/fixtures/task/sportRadar/processGames/collection/ActiveFullGame.json"
ActiveFullGameWithLineUp = require "#{process.env.ROOT_DIR}/test/fixtures/task/sportRadar/processGames/collection/ActiveFullGameWithLineUp.json"
ActiveGameNoInningsFixtures = require "#{process.env.ROOT_DIR}/test/fixtures/task/sportRadar/processGames/collection/ActiveGameNoInnings.json"
ActiveGameNoPlaysFixtures = require "#{process.env.ROOT_DIR}/test/fixtures/task/sportRadar/processGames/collection/ActiveGameNoPlays.json"
ActiveGameEndOfInningFixtures = require "#{process.env.ROOT_DIR}/test/fixtures/task/sportRadar/processGames/collection/ActiveGameEndOfInning.json"
ActiveGameEndOfHalfFixtures = require "#{process.env.ROOT_DIR}/test/fixtures/task/sportRadar/processGames/collection/ActiveGameEndOfHalf.json"
ActiveGameEndOfPlayFixtures = require "#{process.env.ROOT_DIR}/test/fixtures/task/sportRadar/processGames/collection/ActiveGameEndOfPlay.json"
ActiveGameMiddleOfPlayFixtures = require "#{process.env.ROOT_DIR}/test/fixtures/task/sportRadar/processGames/collection/ActiveGameMiddleOfPlay.json"
TeamsFixtures = require "#{process.env.ROOT_DIR}/test/fixtures/task/sportRadar/processGames/collection/Teams.json"

describe "Process imported games and question management", ->
  dependencies = createDependencies settings, "PickkImport"
  mongodb = dependencies.mongodb

  processGames = undefined

  SportRadarGames = mongodb.collection("games")
  Teams = mongodb.collection("teams")
  Questions = mongodb.collection("questions")

  activeGameId = "fec58a7a-eff7-4eec-9535-f64c42cc4870"
  inactiveGameId = "2b0ba18a-41f5-46d7-beb3-1e86b9a4acc0"
  actualActiveQuestionId = "active_question_for_active_game"
  nonActualActiveQuestionId = "active_question_for_inactive_game"

  beforeEach ->
    processGames = new ProcessGames dependencies

    Promise.bind @
    .then ->
      Promise.all [
        SportRadarGames.remove()
        Teams.remove()
        Questions.remove()
      ]

  it 'should fetch only active games', ->
    Promise.bind @
    .then -> loadFixtures TwoActiveGamesFixtures, mongodb 
    .then -> processGames.getActiveGames()
    .then (games) -> 
      should.exist games
      games.should.be.an "array"
      games.length.should.be.equal 2

  it 'should disable active questions for inactive games', ->
    Promise.bind @
    .then -> loadFixtures TwoActiveGamesFixtures, mongodb
    .then -> loadFixtures QuestionsFixtures, mongodb
    .then -> Questions.findOne({id: actualActiveQuestionId})
    .then (question) ->
      # this question shouldn't be disabled
      should.exist question
      question.should.be.an "object"
      {active} = question
      should.exist active
      active.should.be.equal true
    .then -> Questions.findOne({id: nonActualActiveQuestionId})
    .then (question) ->
      # but this should be
      should.exist question
      question.should.be.an "object"
      {active} = question
      should.exist active
      active.should.be.equal true
    .then -> processGames.getActiveGames()
    .then (games) -> processGames.closeQuestionsForInactiveGames(games)
    .then -> Questions.findOne({id: actualActiveQuestionId})
    .then (question) ->
      # it's still active
      should.exist question
      question.should.be.an "object"
      {active} = question
      should.exist active
      active.should.be.equal true
    .then -> Questions.findOne({id: nonActualActiveQuestionId})
    .then (question) ->
      # and this one have had to be disabled
      should.exist question
      question.should.be.an "object"
      {active} = question
      should.exist active
      active.should.be.equal false

  it 'should create new play question', ->
    Promise.bind @
    .then -> loadFixtures ActiveFullGameFixtures, mongodb
    .then -> SportRadarGames.findOne({id: activeGameId})
    .then (game) -> processGames.handleGame game
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
    .then (game) -> processGames.handleGame game
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
    .then (game) -> processGames.handleGame game
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
    .then (game) -> processGames.handleGame game
    .then -> Questions.findOne({game_id: activeGameId, player_id: "abbda8e1-2274-4bf0-931c-691cf8bf24c6", atBatQuestion: {$exists: false}})
    .then (question) ->
      should.exist question
      question.should.be.an "object"

      {active} = question
      should.exist active
      active.should.be.equal true

  it 'should update actual pitch question', ->
    Promise.bind @
    .then -> loadFixtures ActiveFullGameFixtures, mongodb
    .then -> loadFixtures ActualQuestionsFixtures, mongodb
    .then -> SportRadarGames.findOne({id: activeGameId})
    .then (game) -> processGames.handleGame game
    .then -> Questions.findOne({id: "active_pitch_question_for_active_game"})
    .then (question) ->
      should.exist question
      question.should.be.an "object"

      {active, options} = question
      should.exist active
      # should be still active
      active.should.be.equal true

      # check options have been updated
      should.exist options

  it 'should disable non-actual pitch question', ->
    Promise.bind @
    .then -> loadFixtures ActiveFullGameFixtures, mongodb
    .then -> loadFixtures NonActualQuestionsFixtures, mongodb
    .then -> SportRadarGames.findOne({id: activeGameId})
    .then (game) -> processGames.handleGame game
    .then -> Questions.findOne({id: "non_actual_pitch_question_for_active_game"})
    .then (question) ->
      should.exist question
      question.should.be.an "object"

      {active} = question
      should.exist active
      # should be still active
      active.should.be.equal false

  it 'should works correctly when no innings are present', ->
    Promise.bind @
    .then -> loadFixtures ActiveGameNoInningsFixtures, mongodb
    .then -> SportRadarGames.findOne({id: activeGameId})
    .then (game) -> processGames.handleGame game
    .then -> Questions.count()
    .then (result) ->
      should.exist result
      result.should.be.equal 0

  it 'should works correctly when no plays are present', ->
    Promise.bind @
    .then -> loadFixtures ActiveGameNoPlaysFixtures, mongodb
    .then -> SportRadarGames.findOne({id: activeGameId})
    .then (game) -> processGames.handleGame game
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
    .then (game) -> processGames.handleGame game
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
    .then (game) -> processGames.handleGame game
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
    .then (game) -> processGames.handleGame game
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
    .then (game) -> processGames.handleGame game
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
    .then (game) -> processGames.handleGame game
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
    .then (game) -> processGames.handleGame game
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
