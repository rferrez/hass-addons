ARG BUILD_FROM
FROM ${BUILD_FROM}

ENV LANG C.UTF-8

COPY run.sh /
RUN chmod a+x /run.sh

# add aws-cli and deps
RUN apk add -v --no-cache \
        aws-cli \
        jq
    
CMD [ "/run.sh" ]  
