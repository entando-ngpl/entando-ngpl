FROM alpine
MAINTAINER walter <walter@entando.com>

ENV X_USER entando
ENV X_WD /home/$X_USER

RUN apk add --update bash jq xmlstarlet && rm -rf /var/cache/apk/*

RUN adduser --disabled-password --gecos '' $X_USER \
 && mkdir -p $X_WD \
 && chown $X_USER:$X_USER $X_WD
 
USER $X_USER
 
WORKDIR "$X_WD"
CMD ["/bin/bash","-l"]
