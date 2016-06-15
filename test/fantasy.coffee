createDependencies = require "../helper/dependencies"
settings = (require "../helper/settings")("#{process.env.ROOT_DIR}/settings/test.json")

describe "Fantasy API", ->

  it "should work", ->
    dependencies = createDependencies settings, "PickkImport"
    console.log dependencies
