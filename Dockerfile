#########################
# multi stage Dockerfile
# 1. set up the build environment and build the expath-package
# 2. run the eXist-db
#########################
FROM openjdk:8-jdk as builder
LABEL maintainer="Peter Stadler"

ENV WEGA_BUILD_HOME="/opt/wega"
ENV WEGALIB_BUILD_HOME="/opt/wega-lib"

ADD https://deb.nodesource.com/setup_12.x /tmp/nodejs_setup 

# installing Saxon, Node and Git
RUN apt-get update \
    && apt-get install -y --no-install-recommends apt-transport-https ant git libsaxonhe-java \
    # installing nodejs
    && chmod 755 /tmp/nodejs_setup \
    && /tmp/nodejs_setup \
    && apt-get install -y nodejs \
    && ln -s /usr/bin/nodejs /usr/local/bin/node \
    && npm install -g yarn


# first building WeGA-WebApp-lib
WORKDIR ${WEGALIB_BUILD_HOME}
RUN git clone https://github.com/Edirom/WeGA-WebApp-lib.git . \
    && ant -lib /usr/share/java


# now building the main WeGA-WebApp
WORKDIR ${WEGA_BUILD_HOME}
COPY . .
RUN addgroup wegabuilder \
    && adduser wegabuilder --ingroup wegabuilder --disabled-password --system \
    && chown -R wegabuilder:wegabuilder ${WEGA_BUILD_HOME}

# running the main build script as non-root user
USER wegabuilder:wegabuilder
RUN ant -lib /usr/share/java 

#CMD ["/bin/bash"]

#########################
# Now running the eXist-db
# and adding our freshly built xar-package
#########################
FROM existdb/existdb:5.2.0

ADD https://weber-gesamtausgabe.de/downloads/WeGA-data-testing-22662_updatedWorks.xar ${EXIST_HOME}/autodeploy/
COPY --from=builder /opt/wega-lib/build/*.xar ${EXIST_HOME}/autodeploy/
COPY --from=builder /opt/wega/build/*.xar ${EXIST_HOME}/autodeploy/
