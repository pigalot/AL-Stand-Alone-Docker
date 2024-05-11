FROM node:16

# update base image and get latest packages
RUN apt-get update && apt-get upgrade -y

# get the dev version of python2 to install the reqs lower
RUN apt-get install python2-dev -y

# curl used to download pip
RUN apt-get install curl -y

# git used to donwload the app server
RUN apt-get install git -y

# cloning the app server into the docker container
RUN git clone https://github.com/kaansoral/adventureland-appserver appserver

# fixing the internal IP address range that wizard put serious limitations on
# for example, you could have 192.168.1.125 but not 192.168.0.1 /shrug
RUN sed -i 's/192.168.1\\..?.?.?/192\\.168\\.(0\\.([1-9]|[1-9]\\d|[12]\\d\\d)|([1-9]|[1-9]\\d|[12]\\d\\d)\\.([1-9]?\\d|[12]\\d\\d))/' /appserver/sdk/lib/cherrypy/cherrypy/wsgiserver/wsgiserver2.py
RUN sed -i 's/allowed_ips=\[/allowed_ips=["^172\\.(16\\.0\\.([1-9]|[1-9]\\d|[12]\\d\\d)|16\\.([1-9]|[1-9]\\d|[12]\\d\\d)\\.([1-9]?\\d|[12]\\d\\d)|(1[7-9]|2\\d|3[01])(\\.([1-9]?\\d|[12]\\d\\d)){2})$",/g'  /appserver/sdk/lib/cherrypy/cherrypy/wsgiserver/wsgiserver2.py

# get the pip like we discussed
RUN curl https://bootstrap.pypa.io/pip/2.7/get-pip.py --output get-pip.py

# use python to install pip
RUN python2 get-pip.py

# wizard told us to install lxml but python2 can't handle it out with
# supplimentary libraries
RUN apt-get install libxml2-dev libxslt-dev

# install lxml
# TODO: remove lxml since it's not used
# Imported, not used in config.py: from lxml import etree as lxmletree
RUN pip install lxml

# make the AL directory, and enter it
RUN mkdir adventureland && cd adventureland

# copy from the current location to our AL folder
COPY ./adventureland /adventureland

# copy config
COPY ./useful/template.secrets.py /adventureland/secrets.py
COPY ./useful/template.variables.js /adventureland/node/variables.js
COPY ./useful/template.live_variables.js /adventureland/node/live_variables.js

# copy entrypoints
COPY ./docker-entrypoint.sh /adventureland/docker-entrypoint.sh
COPY ./node-entrypoint.sh /adventureland/node-entrypoint.sh

RUN pip install flask -t /adventureland/lib

# npm install performs from the workdir. why? idk. it's stupid
WORKDIR /adventureland/scripts

# install the scripts
RUN npm install

# see why it's stupid? gotta change the workdir to install something else
WORKDIR /adventureland/node

# install the something else
RUN npm install

# i don't think we need all of these. need to do more research
EXPOSE 8082
EXPOSE 8083
EXPOSE 43291
EXPOSE 8000

# add execution perms to the entrypoints
RUN chmod +x /adventureland/docker-entrypoint.sh
RUN chmod +x /adventureland/node-entrypoint.sh

# ###################################################################
# #                                                                 #
# #                             Config                              #
# #                                                                 #
# ###################################################################

# Turn off DRM
RUN sed -i -e 's/drm_check: 1/drm_check: 0/g' /adventureland/node/server.js

# Set Admin email
ARG admin_email
RUN sed -i -e "s/your_email_here/$admin_email/g" /adventureland/admin.py

# Set the config correctly
RUN sed -i -e "s#^from design\.animations import \*#is_sdk = True\n\0#g" /adventureland/config.py

RUN sed -i -e 's#^HTTPS_MODE=True#HTTPS_MODE=False#g' /adventureland/config.py
RUN sed -i -e 's#^always_amazon_ses=True#always_amazon_ses=False#g' /adventureland/config.py
RUN sed -i -e "s#^live_domain='adventure.land'#live_domain=\[\'localhost\'\]#g" /adventureland/config.py
RUN sed -i -e "s#^sdk_domain='thegame.com'#sdk_domain=\[\'localhost\'\]#g" /adventureland/config.py

RUN sed -i -e 's#^\t\tdomain\.base_url=protocol.*hostname$#\0\n\t\tdomain\.base_url="http:\/\/localhost:8083"#g' /adventureland/config.py
RUN sed -i -e 's#^\t\tdomain\.pref_url=domain\.base_url#\t\tdomain\.pref_url="http:\/\/localhost:8083"#g' /adventureland/config.py
RUN sed -i -e 's#^\t\tdomain\.server_ip="192\.168\.1\.125"#\t\tdomain\.server_ip="localhost"#g' /adventureland/config.py
RUN sed -i -e 's#^\t\tdomain\.domain=hostname#\t\tdomain\.domain=\["localhost"\]#g' /adventureland/config.py

# This one is a bit odd, Atlus has loads of code here but as far as I can tell the desired effect is to return false.
# Having looked at the function I am just goingto bypass it as it would be simple to fake anyway.
RUN sed -i -e 's#^def security_threat.request,domain.:$#\0\n\treturn False#g' /adventureland/functions.py

RUN sed -i -E 's#window\.location\.host=="x\.thegame\.com"(..) server_addr="192\.168\.1\.125";#window\.location\.host=="localhost:8083"\1 server_addr="localhost"#g' /adventureland/js/game.js
RUN sed -i -e 's#^\t\tif.window\.location\.origin=='"'"'http:\/\/127\.0\.0\.1\/'"'"'. server_addr="127\.0\.0\.1";$#\/\/\0#g' /adventureland/js/game.js
RUN sed -i -e 's#^\t\telse server_addr="0\.0\.0\.0";$#\/\/\0\n\t\tserver_addr = window\.location\.hostname#g' /adventureland/js/game.js

RUN sed -i -e 's#^var host = .*$#var host = "localhost";#g' /adventureland/origin/server/server.js
RUN sed -i -e 's#^var port = .*$#var port = 8022;#g' /adventureland/origin/server/server.js

# set the default entry point
ENTRYPOINT ["/adventureland/docker-entrypoint.sh"]
