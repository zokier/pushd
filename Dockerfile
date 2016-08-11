FROM    node:latest

RUN npm install -g coffee-script
RUN mkdir /pushd
WORKDIR /pushd
COPY package.json /pushd/
RUN npm install
COPY . /pushd

EXPOSE  8000

CMD ["coffee", "./pushd.coffee"]
