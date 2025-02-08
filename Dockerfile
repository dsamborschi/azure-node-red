FROM nodered/node-red

USER root

WORKDIR /data

# Install themes nodes
RUN npm install @node-red-contrib-themes/theme-collection

RUN chown -R root:node-red /data

RUN npm ci && npm cache clean --force && \
    rm -rf /tmp/* /var/cache/apk/* /root/.npm

#create the folder
WORKDIR /usr/src/node-red

# give the node-red premission to node_modules, for raspberry-pi mostly
RUN chown -R root:node-red /usr/src/node-red/node_modules

# Copy _your_ Node-RED project files into place
COPY src/data/package.json /data
COPY src/data/settings.js /data/settings.js 
COPY src/data/flows.json /data/flows.json