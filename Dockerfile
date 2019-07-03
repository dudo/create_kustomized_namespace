FROM ruby:2-slim

LABEL "name"="Kustomized Namespace - Create Overlay"
LABEL "maintainer"="Brett Dudo <brett@dudo.io>"
LABEL "version"="0.9.0"

LABEL "com.github.actions.icon"="git-commit"
LABEL "com.github.actions.color"="green"
LABEL "com.github.actions.name"="Kustomized Namespace - Create Overlay"
LABEL "com.github.actions.description"="This creates an overlay within a namespace for a feature and ensures your services are still connected"
COPY LICENSE README.md /

RUN apt-get update -qq && apt-get install -y curl

ENV KUSTOMIZE=2.1.0
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
