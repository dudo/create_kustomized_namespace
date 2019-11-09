FROM ruby:2-slim

LABEL "name"="Kustomized Namespace - Create Overlay"
LABEL "maintainer"="Brett Dudo <brett@dudo.io>"

COPY LICENSE README.md /

RUN apt-get update -qq && apt-get install -y curl

ENV KUSTOMIZE=3.3.1
RUN curl -so /bin/kustomize https://github.com/kubernetes-sigs/kustomize/releases/download/v${KUSTOMIZE}/kustomize_${KUSTOMIZE}_linux_amd64
RUN chmod u+x /bin/kustomize

COPY Gemfile Gemfile.lock ./
RUN bundle install --without=development test

COPY create_overlay.rb /bin/create_overlay
COPY manifest.rb /bin/manifest.rb
COPY templates /bin/templates
RUN chmod +x /bin/create_overlay

ENTRYPOINT ["create_overlay"]
CMD ["help"]
