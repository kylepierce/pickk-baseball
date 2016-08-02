# README #

This application was developed to import data from Sport Radar API.

First of all it's necessary to install *pm2* and coffeescript packages:

```
#!bash

sudo npm install -g coffee-script
sudo npm install -g pm2
```
Then install packages required by the application: 
```
#!bash

cd PICKK_IMPORT_APPLICATION
npm install
```
## How can I start periodical import procedure on local machine? ##

Start **main** *pickk* application:
```
#!bash

cd MAIN_PICKK_APPLICATION
meteor run --settings settings.json
```
Return back to *pickk-import*:
```
#!bash

cd PICKK_IMPORT_APPLICATION
```

In order to start basic tasks prompt:
```
#!bash

pm2 start pm2/actors.dev.json
```

In order to stop tasks started before prompt:
```
#!bash

pm2 delete pm2/actors.dev.json
```

In order to see logs call:
```
#!bash

pm2 logs
```

In order to see active tasks call:
```
#!bash

pm2 status
```

In order to deploy the application on the stage or production server call:
```
#!bash

./bin/deploy stag
or
./bin/deploy prod
```

In order to restart the application on the stage or production server call:
```
#!bash

./bin/restart stag
or
./bin/restart prod
```

Open [this](http://localhost:3000/sportRadarGames) URL to show games for today.
