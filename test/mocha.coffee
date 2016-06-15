process.env.ROOT_DIR ?= process.cwd()

chai = require "chai"
global.should = chai.should()
#chai.config.includeStack = true

chaiAsPromised = require "chai-as-promised"
chai.use(chaiAsPromised)

chaiThings = require "chai-things"
chai.use(chaiThings)

chaiSinon = require "sinon-chai"
chai.use(chaiSinon)

global.sinon = require("sinon")

Promise = require "bluebird"
process.env.BLUEBIRD_DEBUG=1

global.nock = require "nock"
global.nock.back.fixtures = "#{process.env.ROOT_DIR}"
# run "rm test/fixtures/[path-to-your-fixture].json; NOCK_BACK_MODE=record mocha test/[path-to-your-test]Spec.coffee" manually to record API responses
