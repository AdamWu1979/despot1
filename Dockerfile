FROM khanlab/neuroglia-core:v1.4
MAINTAINER <alik@robarts.ca>


RUN mkdir /opt/despot1
COPY . /opt/despot1

#add path for octave
#RUN echo addpath\(genpath\(\'/diffparcellate/matlab\'\)\)\; >> /etc/octave.conf 

#add path for root folder, deps, and mial-depends
ENV PATH /opt/despot1/bin:$PATH


ENTRYPOINT ["/opt/despot1/run.sh"]
